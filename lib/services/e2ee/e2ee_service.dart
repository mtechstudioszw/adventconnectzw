import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../secure_storage_service.dart';
import 'e2ee_store.dart';

/// An encrypted payload, ready to be written to `messages`.
///
/// [type] is not decoration. A PreKeySignalMessage and an ordinary
/// SignalMessage are both opaque bytes, and the recipient cannot tell
/// them apart by looking — guessing wrong throws
/// `InvalidMessageException`. It rides in `messages.ciphertext_type`.
@immutable
class EncryptedPayload {
  const EncryptedPayload({
    required this.ciphertext,
    required this.type,
    required this.senderDeviceId,
  });

  /// Base64 of the serialised ciphertext. Goes in `messages.content`.
  final String ciphertext;

  /// One of [CiphertextMessage]'s type constants.
  final int type;

  /// Which of the sender's devices produced this. The recipient needs it
  /// to pick the right session.
  final int senderDeviceId;
}

/// End-to-end encryption, the Signal protocol as WhatsApp uses it.
///
/// X3DH + Double Ratchet for 1:1, Sender Keys for groups. The server
/// holds public keys only — see `database/patch_211_e2ee_key_directory
/// .sql`, which has no column for a private key and must never get one.
///
/// ## What this deliberately does not do
///
/// **No key backup.** Founder's call, and it is WhatsApp's default: the
/// identity lives in the device keystore and a reinstall starts fresh.
/// That is why there is no restore path here — there is nothing to
/// restore from, on purpose.
///
/// **Never throws on a decrypt failure.** A message that cannot be opened
/// must render as a placeholder, not take the thread down with it. One
/// unreadable message is a nuisance; an exception escaping into the list
/// builder is a chat screen that will not paint at all.
class E2eeService {
  E2eeService._();

  static final SupabaseClient _client = Supabase.instance.client;

  /// How many one-time prekeys to publish at a time, and the level below
  /// which we top up. Each one is consumed by exactly one person opening
  /// a conversation with you, so running out means new senders fall back
  /// to the signed prekey alone — still encrypted, weaker forward
  /// secrecy for that first message only.
  static const int _prekeyBatch = 100;
  static const int _prekeyLowWater = 20;

  /// The wire-format version stamped into `messages.e2ee_version`.
  ///
  /// A recipient on an older build sees an unknown version and renders
  /// the placeholder rather than a wall of base64. Bump this only for a
  /// change that older clients genuinely cannot read.
  static const int wireVersion = 1;

  /// Version stamped on an encrypted photo or voice note (1 Nov 2026).
  /// Its body is a key envelope, not text; a build that only knows v1
  /// would decrypt it and print the JSON. Stamping 2 makes those builds
  /// show the placeholder instead. Text stays on [wireVersion].
  static const int mediaWireVersion = 2;

  /// The newest version this build can open.
  static const int maxReadableVersion = mediaWireVersion;

  static E2eeStore? _store;
  static int? _deviceId;

  /// Remote kill switch (`app_config.e2ee_enabled`). **Default OFF.**
  ///
  /// Encryption ships dark. There is no device on the build machine to
  /// verify a real send/receive on, and the failure mode is not a broken
  /// screen — it is messages nobody can ever read. So the code lands,
  /// rides a release, and is switched on only once a real handset has
  /// been seen to work. Keys are still published while it is off, which
  /// is what makes the switch-on instant rather than a slow rollout
  /// waiting for everyone to register.
  static bool _enabled = false;

  /// Whether new messages should actually be encrypted.
  ///
  /// Decryption is deliberately NOT gated on this: once a member has
  /// received an encrypted message it must stay readable even if the
  /// flag is turned back off, or flipping the switch would orphan
  /// everything sent while it was on.
  static bool get isEncryptionOn => _enabled && isReady;

  static String _deviceIdKey(String userId) => 'e2ee_deviceid:$userId';

  /// True once [start] has completed for the signed-in member.
  static bool get isReady => _store != null && _deviceId != null;

  /// Test seam for the flag, which is otherwise only set from
  /// `app_config`.
  @visibleForTesting
  static void debugSetEnabled({required bool enabled}) => _enabled = enabled;

  /// The device id for this install, or null before [start].
  static int? get deviceId => _deviceId;

  /// Opens the local store and makes sure this device is published.
  ///
  /// Safe to call on every launch. The publish is idempotent — an upsert
  /// on (user_id, device_id) — and the prekey top-up is a no-op while
  /// stock is healthy.
  static Future<void> start(String userId) async {
    if (userId.isEmpty) return;
    try {
      _store = await E2eeStore.open(userId);
      _deviceId = await _resolveDeviceId(userId);
      await _publishDevice(userId);
      await _topUpPrekeys(userId);
      await _readFlag(userId);
    } catch (e, st) {
      // Never let key setup take the app down. Without it, sending falls
      // back to plaintext, which is exactly the behaviour of every build
      // before this one — degraded, not broken.
      debugPrint('E2eeService.start failed: $e\n$st');
      _store = null;
      _deviceId = null;
    }
  }

  /// Drops in-memory handles on sign-out.
  ///
  /// The Hive box and the keystore entries stay: they are namespaced by
  /// user id, so the next member cannot read them, and keeping them means
  /// signing back in does not look like a reinstall to your contacts.
  static void stop() {
    _store = null;
    _deviceId = null;
  }

  /// A stable per-install device id.
  ///
  /// Random rather than a fixed 1: two phones signed into one account
  /// would otherwise collide on the `e2ee_devices` primary key and each
  /// overwrite the other's identity, which reads as a security-code
  /// change flapping back and forth forever.
  static Future<int> _resolveDeviceId(String userId) async {
    final existing = await SecureStorageService.read(_deviceIdKey(userId));
    final parsed = int.tryParse(existing ?? '');
    if (parsed != null) return parsed;
    // 1..2^31-1. Not zero: libsignal treats device 0 as unset.
    final generated = Random.secure().nextInt(0x7ffffffe) + 1;
    await SecureStorageService.write(
      _deviceIdKey(userId),
      generated.toString(),
    );
    return generated;
  }

  /// Reads `app_config.e2ee_enabled`. Fails CLOSED — any error leaves
  /// encryption off, because sending ciphertext a recipient's build
  /// cannot open is worse than sending plaintext the way we always have.
  ///
  /// Three accepted values, and the third one is the important one:
  ///
  ///   `0` / `false` / empty  — off for everyone. The shipping default.
  ///   `1` / `true`           — on for everyone.
  ///   a list of user ids     — on ONLY for those accounts.
  ///
  /// The list exists because turning this on is otherwise a catch-22:
  /// the standing instruction is "flip it only after a real send and
  /// receive on two handsets", but with the flag off there is no way to
  /// perform that test — encryption never runs. The honest options were to
  /// flip it globally and hope, or to test on real devices with only your
  /// own account exposed. This is the second one.
  ///
  /// **Why it matters that this is not a global switch.** A failure here
  /// does not look like a broken screen. It writes ciphertext nobody holds
  /// a key for, and those messages are unreadable *forever* — there is no
  /// repair, no migration, no support ticket that recovers them. An
  /// allowlist bounds that blast radius to the accounts you name.
  ///
  /// Put the founder's user id in, send and receive between two handsets
  /// signed into two allowlisted accounts, confirm the bubbles read
  /// correctly on BOTH and survive a force-quit, and only then set `1`.
  static Future<void> _readFlag(String userId) async {
    try {
      final row = await _client
          .from('app_config')
          .select('value')
          .eq('key', 'e2ee_enabled')
          .maybeSingle()
          .timeout(const Duration(seconds: 4));
      final raw = (row?['value'] ?? '').toString().trim();
      final value = raw.toLowerCase();
      if (value == '1' || value == 'true') {
        _enabled = true;
        return;
      }
      if (value.isEmpty || value == '0' || value == 'false') {
        _enabled = false;
        return;
      }
      // Anything else is an allowlist. Split on commas/whitespace so the
      // value can be pasted from the dashboard in whatever shape is handy.
      final allowed = raw
          .split(RegExp(r'[\s,]+'))
          .map((e) => e.trim().toLowerCase())
          .where((e) => e.isNotEmpty)
          .toSet();
      _enabled = allowed.contains(userId.trim().toLowerCase());
    } catch (_) {
      _enabled = false;
    }
  }

  static Future<void> _publishDevice(String userId) async {
    final store = _store!;
    final identity = await store.getIdentityKeyPair();
    await _client.from('e2ee_devices').upsert({
      'user_id': userId,
      'device_id': _deviceId,
      'registration_id': await store.getLocalRegistrationId(),
      'identity_key': base64Encode(identity.getPublicKey().serialize()),
      'last_seen_at': DateTime.now().toUtc().toIso8601String(),
    });

    // A signed prekey the peer can verify came from our identity. Rotated
    // on a fresh publish rather than never — a signed prekey that lives
    // forever is a single key protecting every future conversation.
    const signedId = 1;
    if (!await store.containsSignedPreKey(signedId)) {
      final signed = generateSignedPreKey(identity, signedId);
      await store.storeSignedPreKey(signedId, signed);
      await _client.from('e2ee_signed_prekeys').upsert({
        'user_id': userId,
        'device_id': _deviceId,
        'key_id': signed.id,
        'public_key': base64Encode(signed.getKeyPair().publicKey.serialize()),
        'signature': base64Encode(signed.signature),
      });
    }
  }

  static Future<void> _topUpPrekeys(String userId) async {
    final store = _store!;
    int remaining;
    try {
      remaining =
          await _client.rpc(
                'my_unclaimed_prekey_count',
                params: {'p_device': _deviceId},
              )
              as int;
    } catch (_) {
      // Could not ask (offline, a timeout, the server overloaded). Do NOT
      // assume zero and upload another batch: that is how some devices
      // piled up 2,000-3,900 unused prekeys — one extra batch for every
      // launch the count failed (found 1 Nov 2026, 117,000 surplus rows).
      // Try again next launch instead.
      return;
    }
    if (remaining >= _prekeyLowWater) return;

    // Start above anything already issued so ids never collide with a
    // prekey somebody is mid-way through claiming.
    final start = DateTime.now().millisecondsSinceEpoch % 100000;
    final keys = generatePreKeys(start, _prekeyBatch);
    final rows = <Map<String, dynamic>>[];
    for (final key in keys) {
      await store.storePreKey(key.id, key);
      rows.add({
        'user_id': userId,
        'device_id': _deviceId,
        'key_id': key.id,
        'public_key': base64Encode(key.getKeyPair().publicKey.serialize()),
      });
    }
    await _client.from('e2ee_prekeys').upsert(rows);
  }

  // ---------- 1:1 ----------

  static SignalProtocolAddress _address(String userId, int deviceId) =>
      SignalProtocolAddress(userId, deviceId);

  /// Encrypts [plaintext] for [recipientUserId], establishing a session
  /// from their published bundle if this is the first message.
  ///
  /// Returns null when encryption is not possible — no local store, or
  /// the recipient has no keys published because they are still on an
  /// older build. The caller sends plaintext in that case; refusing to
  /// send at all would make the app look broken to whoever upgraded
  /// first.
  static Future<EncryptedPayload?> encryptDirect({
    required String recipientUserId,
    required String plaintext,
  }) async {
    final store = _store;
    final myDevice = _deviceId;
    if (store == null || myDevice == null) return null;

    try {
      // patch_298: with a session already open to their current phone,
      // encrypt straight away. Claiming a bundle per message used up one
      // of their one-time keys on every send.
      final latest = await _latestDevice(recipientUserId);
      if (latest != null) {
        final open = _address(recipientUserId, latest);
        if (await store.containsSession(open)) {
          final message = await SessionCipher.fromStore(
            store,
            open,
          ).encrypt(Uint8List.fromList(utf8.encode(plaintext)));
          return EncryptedPayload(
            ciphertext: base64Encode(message.serialize()),
            type: message.getType(),
            senderDeviceId: myDevice,
          );
        }
      }
      final bundle = await _claimBundle(recipientUserId);
      if (bundle == null && !await _hasAnySession(store, recipientUserId)) {
        return null; // they are not on an E2EE build
      }

      final address = bundle != null
          ? _address(recipientUserId, bundle.deviceId)
          : (await _existingAddress(store, recipientUserId))!;

      if (bundle != null && !await store.containsSession(address)) {
        await SessionBuilder.fromSignalStore(
          store,
          address,
        ).processPreKeyBundle(bundle.toPreKeyBundle());
      }

      final message = await SessionCipher.fromStore(
        store,
        address,
      ).encrypt(Uint8List.fromList(utf8.encode(plaintext)));

      return EncryptedPayload(
        ciphertext: base64Encode(message.serialize()),
        type: message.getType(),
        senderDeviceId: myDevice,
      );
    } catch (e, st) {
      debugPrint('E2eeService.encryptDirect failed: $e\n$st');
      return null;
    }
  }

  /// Decrypts a 1:1 message. Returns null if it cannot be opened.
  ///
  /// Null is a normal outcome, not a bug: a message encrypted to a
  /// previous install of this app is genuinely unreadable, and the UI
  /// shows "Waiting for this message" rather than pretending otherwise.
  static Future<String?> decryptDirect({
    required String senderUserId,
    required int senderDeviceId,
    required String ciphertextB64,
    required int type,
  }) async {
    final store = _store;
    if (store == null) return null;
    try {
      final bytes = base64Decode(ciphertextB64);
      final address = _address(senderUserId, senderDeviceId);
      final cipher = SessionCipher.fromStore(store, address);

      final plain = type == CiphertextMessage.prekeyType
          ? await cipher.decryptWithCallback(PreKeySignalMessage(bytes), (_) {})
          : await cipher.decryptFromSignal(SignalMessage.fromSerialized(bytes));
      return utf8.decode(plain);
    } catch (e) {
      // Includes DuplicateMessageException, which realtime + the polling
      // reconcile make routine — the same row can arrive twice and the
      // ratchet refuses to open it a second time.
      debugPrint('E2eeService.decryptDirect: ${e.runtimeType}');
      return null;
    }
  }

  // ---------- groups ----------

  /// Our sender-key chain for [conversationId].
  static SenderKeyName _senderKeyName(String conversationId, String userId) =>
      SenderKeyName(conversationId, _address(userId, _deviceId!));

  /// Creates (or reuses) our sender key for a group and returns the
  /// distribution message every member needs before they can read us.
  ///
  /// The distribution is sent to each member over the PAIRWISE encrypted
  /// channel — never through the server in the clear. That is what keeps
  /// the group's message key away from the database, and it is why there
  /// is no sender-key table in patch_211.
  static Future<String?> createGroupDistribution({
    required String conversationId,
    required String myUserId,
  }) async {
    final store = _store;
    if (store == null || _deviceId == null) return null;
    try {
      final message = await GroupSessionBuilder(
        store,
      ).create(_senderKeyName(conversationId, myUserId));
      return base64Encode(message.serialize());
    } catch (e, st) {
      debugPrint('E2eeService.createGroupDistribution failed: $e\n$st');
      return null;
    }
  }

  /// Accepts another member's sender key so their messages can be read.
  static Future<bool> processGroupDistribution({
    required String conversationId,
    required String senderUserId,
    required int senderDeviceId,
    required String distributionB64,
  }) async {
    final store = _store;
    if (store == null) return false;
    try {
      await GroupSessionBuilder(store).process(
        SenderKeyName(conversationId, _address(senderUserId, senderDeviceId)),
        SenderKeyDistributionMessageWrapper.fromSerialized(
          base64Decode(distributionB64),
        ),
      );
      return true;
    } catch (e, st) {
      debugPrint('E2eeService.processGroupDistribution failed: $e\n$st');
      return false;
    }
  }

  /// Encrypts once for the whole group.
  static Future<EncryptedPayload?> encryptGroup({
    required String conversationId,
    required String myUserId,
    required String plaintext,
  }) async {
    final store = _store;
    final myDevice = _deviceId;
    if (store == null || myDevice == null) return null;
    try {
      final cipher = GroupCipher(
        store,
        _senderKeyName(conversationId, myUserId),
      );
      final bytes = await cipher.encrypt(
        Uint8List.fromList(utf8.encode(plaintext)),
      );
      return EncryptedPayload(
        ciphertext: base64Encode(bytes),
        type: CiphertextMessage.senderKeyType,
        senderDeviceId: myDevice,
      );
    } catch (e, st) {
      debugPrint('E2eeService.encryptGroup failed: $e\n$st');
      return null;
    }
  }

  /// Decrypts a group message. Null when the sender's key has not
  /// arrived yet — the caller should ask them to redistribute.
  static Future<String?> decryptGroup({
    required String conversationId,
    required String senderUserId,
    required int senderDeviceId,
    required String ciphertextB64,
  }) async {
    final store = _store;
    if (store == null) return null;
    try {
      final cipher = GroupCipher(
        store,
        SenderKeyName(conversationId, _address(senderUserId, senderDeviceId)),
      );
      final plain = await cipher.decrypt(base64Decode(ciphertextB64));
      return utf8.decode(plain);
    } catch (e) {
      debugPrint('E2eeService.decryptGroup: ${e.runtimeType}');
      return null;
    }
  }

  /// Forget every sender key for a group, forcing a fresh chain.
  ///
  /// Called when membership changes. Without this, someone removed from
  /// a group could still read everything said afterwards, because they
  /// already hold the chain key.
  static Future<void> rotateGroup(String conversationId) async {
    await _store?.clearGroupSenderKeys(conversationId);
  }

  // ---------- retry receipts (patch_298) ----------
  //
  // A NEW message that this phone cannot open (a group key that hasn't
  // arrived, a message that went to the member's other phone, our own
  // message sent from another phone) is asked for again; the sender's
  // phone re-encrypts it for this device. Messages older than this
  // install stay "Waiting for this message" — the server refuses those
  // requests (owner, 1 Nov 2026).

  /// Bumped when a copy arrives, so an open thread re-reads its rows.
  static final ValueNotifier<int> plaintextRevision = ValueNotifier(0);

  static final Set<String> _requested = {};

  /// Old messages the server will not re-send (older than this install):
  /// never asked about again this session — they stay "Waiting".
  static final Set<String> _refused = {};

  /// Ids this phone has asked for and not yet opened.
  static bool isAwaitingCopy(String messageId) =>
      _requested.contains(messageId);

  static Future<int?> _latestDevice(String userId) async {
    try {
      final r = await _client.rpc(
        'e2ee_latest_device',
        params: {'p_user': userId},
      );
      return (r as num?)?.toInt();
    } catch (_) {
      return null; // patch_298 not applied: the old path still works
    }
  }

  /// Encrypts [plaintext] for [userId]'s CURRENT phone, saying which one
  /// (story keys are stored per device). Null when they have no keys.
  static Future<({EncryptedPayload payload, int deviceId})?> encryptForUser({
    required String userId,
    required String plaintext,
  }) async {
    final device = await _latestDevice(userId);
    if (device == null) return null;
    final payload = await encryptToDevice(
      userId: userId,
      deviceId: device,
      plaintext: plaintext,
    );
    return payload == null ? null : (payload: payload, deviceId: device);
  }

  /// Encrypts [plaintext] for ONE device of [userId].
  static Future<EncryptedPayload?> encryptToDevice({
    required String userId,
    required int deviceId,
    required String plaintext,
  }) async {
    final store = _store;
    final myDevice = _deviceId;
    if (store == null || myDevice == null) return null;
    try {
      final address = _address(userId, deviceId);
      if (!await store.containsSession(address)) {
        final rows = await _client.rpc(
          'claim_prekey_bundle_for',
          params: {'p_user': userId, 'p_device': deviceId},
        );
        if (rows is! List || rows.isEmpty) return null;
        final bundle = ClaimedBundle.fromJson(
          Map<String, dynamic>.from(rows.first as Map),
        );
        await SessionBuilder.fromSignalStore(
          store,
          address,
        ).processPreKeyBundle(bundle.toPreKeyBundle());
      }
      final message = await SessionCipher.fromStore(
        store,
        address,
      ).encrypt(Uint8List.fromList(utf8.encode(plaintext)));
      return EncryptedPayload(
        ciphertext: base64Encode(message.serialize()),
        type: message.getType(),
        senderDeviceId: myDevice,
      );
    } catch (e) {
      debugPrint('E2eeService.encryptToDevice: $e');
      return null;
    }
  }

  /// Picks up copies for [messageIds] and opens them. Returns id → text
  /// for every one that opened (and caches it). Asks the sender for any
  /// that have no copy yet. Never throws.
  static Future<Map<String, String>> recoverMessages(
    List<String> messageIds,
  ) async {
    final device = _deviceId;
    final out = <String, String>{};
    messageIds = messageIds.where((id) => !_refused.contains(id)).toList();
    if (device == null || messageIds.isEmpty) return out;
    final ids = messageIds
        .map(int.tryParse)
        .whereType<int>()
        .take(200)
        .toList();
    if (ids.isEmpty) return out;
    try {
      final rows = await _client.rpc(
        'e2ee_copies_for',
        params: {'p_messages': ids, 'p_device': device},
      );
      for (final raw in (rows as List? ?? const [])) {
        final r = Map<String, dynamic>.from(raw as Map);
        final id = '${r['message_id']}';
        final plain = await decryptDirect(
          senderUserId: '${r['sender_id']}',
          senderDeviceId: (r['sender_device'] as num).toInt(),
          ciphertextB64: '${r['ciphertext']}',
          type: (r['ciphertext_type'] as num).toInt(),
        );
        if (plain != null) {
          await cachePlaintext(id, plain);
          _requested.remove(id);
          out[id] = plain;
        }
      }
    } catch (e) {
      debugPrint('E2eeService.recoverMessages copies: $e');
    }
    for (final id in messageIds) {
      if (out.containsKey(id) || _requested.contains(id)) continue;
      final n = int.tryParse(id);
      if (n == null) continue;
      try {
        final ok = await _client.rpc(
          'e2ee_request_resend',
          params: {'p_message': n, 'p_device': device},
        );
        if (ok == true) {
          _requested.add(id);
        } else {
          _refused.add(id);
        }
      } catch (_) {
        // patch_298 not applied yet: nothing to ask.
      }
    }
    if (_requested.isNotEmpty) _schedulePickup();
    return out;
  }

  static bool _pickupScheduled = false;
  static int _pickupRounds = 0;

  /// Checks back for copies a few times after asking — the sender's
  /// phone answers whenever it is next online.
  static void _schedulePickup() {
    if (_pickupScheduled) return;
    _pickupScheduled = true;
    Future<void>.delayed(const Duration(seconds: 20), () async {
      _pickupScheduled = false;
      if (_requested.isEmpty) {
        _pickupRounds = 0;
        return;
      }
      final got = await recoverMessages(_requested.toList());
      if (got.isNotEmpty) plaintextRevision.value++;
      // ~10 minutes of checking, then wait for the next chat open.
      if (_requested.isNotEmpty && ++_pickupRounds < 30) _schedulePickup();
    });
  }

  static bool _serving = false;

  /// Answers other phones' requests for messages WE sent, from the
  /// plaintext kept on this phone. Safe to call often. Never throws.
  static Future<int> serveResends() async {
    if (_serving || !isReady) return 0;
    _serving = true;
    var served = 0;
    try {
      final rows = await _client.rpc('e2ee_pending_resends');
      for (final raw in (rows as List? ?? const [])) {
        final r = Map<String, dynamic>.from(raw as Map);
        final id = '${r['message_id']}';
        final plain = cachedPlaintext(id);
        if (plain == null) continue; // not on this phone — another may have it
        final user = '${r['requester_user']}';
        final device = (r['requester_device'] as num).toInt();
        final payload = await encryptToDevice(
          userId: user,
          deviceId: device,
          plaintext: plain,
        );
        if (payload == null) continue;
        await _client.rpc(
          'e2ee_fulfill_resend',
          params: {
            'p_message': int.parse(id),
            'p_user': user,
            'p_device': device,
            'p_sender_device': payload.senderDeviceId,
            'p_ciphertext': payload.ciphertext,
            'p_type': payload.type,
          },
        );
        served++;
      }
    } catch (e) {
      debugPrint('E2eeService.serveResends: $e');
    } finally {
      _serving = false;
    }
    return served;
  }

  // ---------- the local plaintext store ----------

  /// The already-decrypted body of [messageId], or null.
  ///
  /// Callers MUST consult this before decrypting: the ratchet opens a
  /// given message exactly once, and this app reads every message
  /// several times (fetch, realtime, tick reconcile). See the note in
  /// [E2eeStore].
  static String? cachedPlaintext(String messageId) =>
      _store?.readPlaintext(messageId);

  /// Remembers a decrypted (or, at send time, pre-encryption) body.
  static Future<void> cachePlaintext(String messageId, String plaintext) async {
    await _store?.writePlaintext(messageId, plaintext);
  }

  /// Forgets one message's plaintext — "delete for me".
  static Future<void> forgetPlaintext(String messageId) async {
    await _store?.deletePlaintext(messageId);
  }

  /// When [peerUserId]'s security code last changed, or null.
  ///
  /// The chat screen turns this into WhatsApp's system line. Almost
  /// always a reinstall or a new phone — but it is shown either way,
  /// because the case it cannot distinguish from those is someone
  /// interposing, and that is precisely the case worth surfacing.
  static DateTime? identityChangedAt(String peerUserId) =>
      _store?.readIdentityChange(peerUserId);

  /// Dismisses the notice once the member has seen it.
  static Future<void> acknowledgeIdentityChange(String peerUserId) async {
    await _store?.clearIdentityChange(peerUserId);
  }

  /// Signal's iteration count for the numeric fingerprint.
  ///
  /// NOT a tunable. The digits are the output of this many SHA-512
  /// rounds, so changing it changes every security code in the app — two
  /// members on different app versions would compare codes, see a
  /// mismatch, and conclude they were being intercepted when they were
  /// not. It matches Signal's 5200 so the numbers are comparable with
  /// every other implementation of the same spec.
  static const int _fingerprintIterations = 5200;

  /// Version tag baked into the *scannable* (QR) half of the fingerprint.
  /// The 60 digits do not depend on it; kept separate from [wireVersion]
  /// so bumping the message wire format cannot silently move it.
  static const int _fingerprintVersion = 1;

  /// The security code for the conversation with [peerUserId] — 60 digits,
  /// grouped for reading aloud — or null when there is nothing to compare.
  ///
  /// This is Signal's "safety number": a hash over BOTH identity public
  /// keys. Both phones derive the same digits because the generator sorts
  /// the two halves, which is the whole point — the members read it to
  /// each other over a channel an attacker does not control, and a
  /// mismatch means somebody is sitting in the middle re-encrypting.
  ///
  /// Returns null rather than a placeholder string when this device has
  /// never held the peer's identity key. A code shown in that state would
  /// be derived from our own key alone and would never match theirs, so
  /// the UI must say "not available yet" — a wrong code is worse than no
  /// code, because members are told to act on a mismatch.
  ///
  /// Async and not cheap (5200 SHA-512 rounds per side): call it once and
  /// hold the result, never from `build`.
  static Future<String?> securityCode(String peerUserId) async {
    final store = _store;
    if (store == null || peerUserId.isEmpty) return null;
    try {
      final remote = await _peerIdentityKey(store, peerUserId);
      if (remote == null) return null;
      final local = (await store.getIdentityKeyPair()).getPublicKey();
      final fingerprint = NumericFingerprintGenerator(_fingerprintIterations)
          .createFor(
            _fingerprintVersion,
            Uint8List.fromList(utf8.encode(store.userId)),
            local,
            Uint8List.fromList(utf8.encode(peerUserId)),
            remote,
          );
      return _groupDigits(fingerprint.displayableFingerprint.getDisplayText());
    } catch (e, st) {
      debugPrint('E2eeService.securityCode failed: $e\n$st');
      return null;
    }
  }

  /// The peer's identity public key, preferring the one we have actually
  /// been talking to over whatever the directory currently advertises.
  ///
  /// That order matters: a session's stored identity is the key this
  /// device has been encrypting to, so it is the one a mismatch would
  /// expose. Reading the directory first would paper over exactly the
  /// swap the security code exists to reveal. The directory is only a
  /// fallback so the code is visible before the first message is sent.
  static Future<IdentityKey?> _peerIdentityKey(
    E2eeStore store,
    String peerUserId,
  ) async {
    final devices = await store.getSubDeviceSessions(peerUserId);
    for (final deviceId in devices) {
      final known = await store.getIdentity(_address(peerUserId, deviceId));
      if (known != null) return known;
    }
    try {
      final row = await _client
          .from('e2ee_devices')
          .select('identity_key')
          .eq('user_id', peerUserId)
          .order('device_id')
          .limit(1)
          .maybeSingle();
      final encoded = row?['identity_key']?.toString() ?? '';
      if (encoded.isEmpty) return null;
      return IdentityKey.fromBytes(base64Decode(encoded), 0);
    } catch (e) {
      debugPrint('E2eeService._peerIdentityKey: $e');
      return null;
    }
  }

  /// 60 digits → four groups of five per line, three lines. Signal's
  /// layout, and the reason is legibility under pressure: nobody reads a
  /// 60-digit run aloud correctly, and this is read aloud by design.
  static String _groupDigits(String digits) {
    final out = StringBuffer();
    for (var i = 0; i < digits.length; i += 5) {
      if (i > 0) out.write(i % 20 == 0 ? '\n' : '  ');
      out.write(digits.substring(i, min(i + 5, digits.length)));
    }
    return out.toString();
  }

  /// The inbox preview for [conversationId], decrypted, from this
  /// device's own store.
  ///
  /// The server holds only a sentinel for an encrypted thread, so this
  /// is the only source. Null means "this device has never opened that
  /// conversation" — a real state after a reinstall, which reads as
  /// `E2eeEnvelope.previewPlaceholder`.
  static String? cachedPreview(String conversationId) =>
      _store?.readPreview(conversationId);

  /// Remembers the newest readable line for an inbox row.
  static Future<void> cachePreview(
    String conversationId,
    String preview,
  ) async {
    await _store?.writePreview(conversationId, preview);
  }

  // ---------- helpers ----------

  static Future<bool> _hasAnySession(E2eeStore store, String userId) async =>
      (await store.getSubDeviceSessions(userId)).isNotEmpty;

  static Future<SignalProtocolAddress?> _existingAddress(
    E2eeStore store,
    String userId,
  ) async {
    final devices = await store.getSubDeviceSessions(userId);
    return devices.isEmpty ? null : _address(userId, devices.first);
  }

  static Future<ClaimedBundle?> _claimBundle(String userId) async {
    try {
      final rows = await _client.rpc(
        'claim_prekey_bundle',
        params: {'p_user': userId},
      );
      if (rows is! List || rows.isEmpty) return null;
      return ClaimedBundle.fromJson(
        Map<String, dynamic>.from(rows.first as Map),
      );
    } catch (e) {
      debugPrint('E2eeService._claimBundle: $e');
      return null;
    }
  }
}

/// One row out of `claim_prekey_bundle()` (patch_211).
///
/// Public so a test can pin the wire format. This is the seam where a
/// Postgres `RETURNS TABLE` meets libsignal's binary key encoding, and
/// nothing about a base64 or offset mistake here fails loudly — it fails
/// as a session that will not establish, on someone else's phone.
class ClaimedBundle {
  const ClaimedBundle({
    required this.deviceId,
    required this.registrationId,
    required this.identityKey,
    required this.signedKeyId,
    required this.signedKey,
    required this.signedSig,
    required this.prekeyId,
    required this.prekey,
  });

  final int deviceId;
  final int registrationId;
  final String identityKey;
  final int signedKeyId;
  final String signedKey;
  final String signedSig;

  /// Null when the peer has run out of one-time prekeys. X3DH still
  /// works from the signed prekey alone.
  final int? prekeyId;
  final String? prekey;

  factory ClaimedBundle.fromJson(Map<String, dynamic> json) => ClaimedBundle(
    deviceId: (json['device_id'] as num).toInt(),
    registrationId: (json['registration_id'] as num).toInt(),
    identityKey: json['identity_key'].toString(),
    signedKeyId: (json['signed_key_id'] as num).toInt(),
    signedKey: json['signed_key'].toString(),
    signedSig: json['signed_sig'].toString(),
    prekeyId: json['prekey_id'] == null
        ? null
        : (json['prekey_id'] as num).toInt(),
    prekey: json['prekey']?.toString(),
  );

  PreKeyBundle toPreKeyBundle() => PreKeyBundle(
    registrationId,
    deviceId,
    prekeyId,
    prekey == null ? null : Curve.decodePoint(base64Decode(prekey!), 0),
    signedKeyId,
    Curve.decodePoint(base64Decode(signedKey), 0),
    base64Decode(signedSig),
    IdentityKey.fromBytes(base64Decode(identityKey), 0),
  );
}
