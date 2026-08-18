import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';

import '../secure_storage_service.dart';

/// Durable Signal protocol state for one signed-in member.
///
/// Everything the ratchet needs to keep working across launches:
/// sessions, one-time prekeys, signed prekeys, the identities we have
/// seen, and group sender keys. The in-memory stores libsignal ships are
/// fine for tests and useless in an app — losing this state does not
/// degrade gracefully, it makes every message in every thread
/// permanently unreadable.
///
/// **This is NOT in CacheService, on purpose.** That box has a 24-hour
/// janitor that deletes anything without a `pref:` prefix, and it has
/// already silently eaten "downloaded" content once. Session state must
/// never be a cache-eviction candidate, so it lives in its own box that
/// nothing prunes.
///
/// **Namespaced per user id.** The box name and the secure-storage keys
/// both carry the member's id, so a second person signing in on the same
/// handset reads a different box, finds nothing, and generates their own
/// identity. It also means signing out and back in KEEPS your sessions —
/// which is right: a sign-out is not a reinstall, and regenerating an
/// identity would tell every one of your contacts your security code
/// changed for no reason.
class E2eeStore implements SignalProtocolStore, SenderKeyStore {
  E2eeStore._(this.userId, this._box, this._identity, this._registrationId);

  final String userId;
  final Box<String> _box;
  final IdentityKeyPair _identity;
  final int _registrationId;

  static String boxName(String userId) => 'e2ee_v1_$userId';
  static String identityStorageKey(String userId) => 'e2ee_identity:$userId';
  static String registrationStorageKey(String userId) => 'e2ee_regid:$userId';

  /// Opens the store for [userId], generating an identity on first use.
  ///
  /// The identity PRIVATE key goes to the platform keystore
  /// (flutter_secure_storage), never to Hive and never to the server.
  static Future<E2eeStore> open(String userId) async {
    final box = await Hive.openBox<String>(boxName(userId));

    var identityB64 = await SecureStorageService.read(
      identityStorageKey(userId),
    );
    var regIdRaw = await SecureStorageService.read(
      registrationStorageKey(userId),
    );

    if (identityB64 == null || regIdRaw == null) {
      // First run on this device for this member. A fresh identity is
      // exactly what a reinstall produces, and is what makes the peer's
      // "security code changed" notice fire.
      final identity = generateIdentityKeyPair();
      final registrationId = generateRegistrationId(false);
      identityB64 = base64Encode(identity.serialize());
      regIdRaw = registrationId.toString();
      await SecureStorageService.write(
        identityStorageKey(userId),
        identityB64,
      );
      await SecureStorageService.write(
        registrationStorageKey(userId),
        regIdRaw,
      );
    }

    return E2eeStore._(
      userId,
      box,
      IdentityKeyPair.fromSerialized(base64Decode(identityB64)),
      int.parse(regIdRaw),
    );
  }

  /// Test seam: a store over a box the caller already opened, so the
  /// whole thing can be exercised without a platform keystore.
  @visibleForTesting
  static E2eeStore forTesting({
    required String userId,
    required Box<String> box,
    required IdentityKeyPair identity,
    required int registrationId,
  }) => E2eeStore._(userId, box, identity, registrationId);

  // ---------- key layout ----------
  // One flat box with prefixed keys, rather than five boxes, so wiping a
  // member is a single deleteFromDisk.
  String _sessionKey(SignalProtocolAddress a) =>
      'session/${a.getName()}/${a.getDeviceId()}';
  String _preKeyKey(int id) => 'prekey/$id';
  String _signedKey(int id) => 'signed/$id';
  String _identityKeyFor(SignalProtocolAddress a) =>
      'identity/${a.getName()}/${a.getDeviceId()}';
  String _senderKeyKey(SenderKeyName n) =>
      'senderkey/${n.groupId}/${n.sender.getName()}/${n.sender.getDeviceId()}';

  Uint8List? _readBytes(String key) {
    final raw = _box.get(key);
    return raw == null ? null : base64Decode(raw);
  }

  Future<void> _writeBytes(String key, Uint8List value) =>
      _box.put(key, base64Encode(value));

  static bool _sameBytes(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  // ---------- IdentityKeyStore ----------

  @override
  Future<IdentityKeyPair> getIdentityKeyPair() async => _identity;

  @override
  Future<int> getLocalRegistrationId() async => _registrationId;

  @override
  Future<bool> saveIdentity(
    SignalProtocolAddress address,
    IdentityKey? identityKey,
  ) async {
    if (identityKey == null) return false;
    final key = _identityKeyFor(address);
    final existing = _readBytes(key);
    final incoming = identityKey.serialize();
    await _writeBytes(key, incoming);
    // The contract is "did this REPLACE a different key" — i.e. did their
    // security code change. A first-ever save is not a change, or every
    // new contact would be announced as one.
    if (existing == null) return false;
    final changed = !_sameBytes(existing, incoming);
    if (changed) {
      // Record it HERE rather than at the call sites. libsignal invokes
      // saveIdentity from inside both the send path (processPreKeyBundle)
      // and the receive path (decrypting a PreKeySignalMessage), and its
      // return value is swallowed in both — so this is the one place that
      // sees every key change in either direction.
      await _box.put(
        _keyChangeKey(address.getName()),
        DateTime.now().toUtc().toIso8601String(),
      );
    }
    return changed;
  }

  String _keyChangeKey(String userId) => 'keychange/$userId';

  /// When [userId]'s security code last changed, or null.
  ///
  /// Almost always means they reinstalled or moved to a new phone. It can
  /// also mean someone is interposing, which is why the member is told
  /// rather than quietly reconnected.
  DateTime? readIdentityChange(String userId) {
    final raw = _box.get(_keyChangeKey(userId));
    return raw == null ? null : DateTime.tryParse(raw);
  }

  /// Clears the marker once the member has been shown it.
  Future<void> clearIdentityChange(String userId) =>
      _box.delete(_keyChangeKey(userId));

  @override
  Future<bool> isTrustedIdentity(
    SignalProtocolAddress address,
    IdentityKey? identityKey,
    Direction direction,
  ) async {
    if (identityKey == null) return false;
    // Trust on first use, and keep trusting after a change — WhatsApp's
    // behaviour. Refusing a changed key would break the thread of anyone
    // who simply got a new phone, which is the common case by far. The
    // member is TOLD instead; see [isKnownDifferentIdentity].
    return true;
  }

  @override
  Future<IdentityKey?> getIdentity(SignalProtocolAddress address) async {
    final bytes = _readBytes(_identityKeyFor(address));
    return bytes == null ? null : IdentityKey.fromBytes(bytes, 0);
  }

  /// Whether [identityKey] differs from the one already on file.
  ///
  /// Separate from [saveIdentity] because the answer is needed BEFORE the
  /// save, and because saveIdentity is called from deep inside libsignal
  /// where its return value never reaches us.
  bool isKnownDifferentIdentity(
    SignalProtocolAddress address,
    IdentityKey identityKey,
  ) {
    final known = _readBytes(_identityKeyFor(address));
    if (known == null) return false;
    return !_sameBytes(known, identityKey.serialize());
  }

  // ---------- PreKeyStore ----------

  @override
  Future<PreKeyRecord> loadPreKey(int preKeyId) async {
    final bytes = _readBytes(_preKeyKey(preKeyId));
    if (bytes == null) {
      throw InvalidKeyIdException('No prekey $preKeyId on this device');
    }
    return PreKeyRecord.fromBuffer(bytes);
  }

  @override
  Future<void> storePreKey(int preKeyId, PreKeyRecord record) =>
      _writeBytes(_preKeyKey(preKeyId), record.serialize());

  @override
  Future<bool> containsPreKey(int preKeyId) async =>
      _box.containsKey(_preKeyKey(preKeyId));

  @override
  Future<void> removePreKey(int preKeyId) => _box.delete(_preKeyKey(preKeyId));

  // ---------- SignedPreKeyStore ----------

  @override
  Future<SignedPreKeyRecord> loadSignedPreKey(int signedPreKeyId) async {
    final bytes = _readBytes(_signedKey(signedPreKeyId));
    if (bytes == null) {
      throw InvalidKeyIdException('No signed prekey $signedPreKeyId');
    }
    return SignedPreKeyRecord.fromSerialized(bytes);
  }

  @override
  Future<List<SignedPreKeyRecord>> loadSignedPreKeys() async => [
    for (final key in _box.keys)
      if (key is String && key.startsWith('signed/'))
        SignedPreKeyRecord.fromSerialized(_readBytes(key)!),
  ];

  @override
  Future<void> storeSignedPreKey(int id, SignedPreKeyRecord record) =>
      _writeBytes(_signedKey(id), record.serialize());

  @override
  Future<bool> containsSignedPreKey(int id) async =>
      _box.containsKey(_signedKey(id));

  @override
  Future<void> removeSignedPreKey(int id) => _box.delete(_signedKey(id));

  // ---------- SessionStore ----------

  @override
  Future<SessionRecord> loadSession(SignalProtocolAddress address) async {
    final bytes = _readBytes(_sessionKey(address));
    // A missing session is normal, not an error: it is what "we have
    // never spoken" looks like, and the caller builds one from a bundle.
    return bytes == null
        ? SessionRecord()
        : SessionRecord.fromSerialized(bytes);
  }

  @override
  Future<List<int>> getSubDeviceSessions(String name) async => [
    for (final key in _box.keys)
      if (key is String && key.startsWith('session/$name/'))
        int.parse(key.split('/').last),
  ];

  @override
  Future<void> storeSession(
    SignalProtocolAddress address,
    SessionRecord record,
  ) => _writeBytes(_sessionKey(address), record.serialize());

  @override
  Future<bool> containsSession(SignalProtocolAddress address) async =>
      _box.containsKey(_sessionKey(address));

  @override
  Future<void> deleteSession(SignalProtocolAddress address) =>
      _box.delete(_sessionKey(address));

  @override
  Future<void> deleteAllSessions(String name) async {
    final doomed = <String>[
      for (final key in _box.keys)
        if (key is String && key.startsWith('session/$name/')) key,
    ];
    await _box.deleteAll(doomed);
  }

  // ---------- SenderKeyStore (groups) ----------

  @override
  Future<void> storeSenderKey(
    SenderKeyName senderKeyName,
    SenderKeyRecord record,
  ) => _writeBytes(_senderKeyKey(senderKeyName), record.serialize());

  @override
  Future<SenderKeyRecord> loadSenderKey(SenderKeyName senderKeyName) async {
    final bytes = _readBytes(_senderKeyKey(senderKeyName));
    return bytes == null
        ? SenderKeyRecord()
        : SenderKeyRecord.fromSerialized(bytes);
  }

  // ---------- decrypted plaintext ----------
  //
  // WhatsApp keeps a local plaintext database, and so must this, for a
  // reason that is not about convenience: **the Double Ratchet advances
  // once per message and refuses to open the same one twice.**
  //
  // Every message in this app is read at least twice — `fetchMessages`
  // pulls the last 500 on open, `streamMessages` delivers it again over
  // realtime, and `_reconcileTicks` re-reads the thread. Decrypting on
  // each of those would succeed once and then throw
  // DuplicateMessageException forever after, so a message would appear
  // correctly and turn into "Waiting for this message" a second later.
  //
  // So: decrypt exactly once, keep the result here, and let every later
  // read hit this instead. It is also what makes offline reading, inbox
  // previews and local search work at all once the server can no longer
  // see message text.

  String _plaintextKey(String messageId) => 'plain/$messageId';

  /// The decrypted body of [messageId], or null if never opened here.
  String? readPlaintext(String messageId) => _box.get(_plaintextKey(messageId));

  /// Remembers [plaintext] for [messageId]. Also called at SEND time for
  /// our own outgoing messages — the ratchet cannot decrypt what it
  /// encrypted, so our own bubbles would otherwise be unreadable to us.
  Future<void> writePlaintext(String messageId, String plaintext) =>
      _box.put(_plaintextKey(messageId), plaintext);

  /// Drops one message's plaintext, for "delete for me".
  Future<void> deletePlaintext(String messageId) =>
      _box.delete(_plaintextKey(messageId));

  // ---------- inbox previews ----------
  //
  // Kept separately from message plaintext because the inbox needs the
  // newest line for a conversation WITHOUT knowing which message id that
  // is — `conversations.last_message` carries no id, and asking the
  // server for one would defeat the point of not storing the text there.

  String _previewKey(String conversationId) => 'preview/$conversationId';

  /// The newest readable line for an inbox row, or null if this device
  /// has never seen one (a fresh install).
  String? readPreview(String conversationId) =>
      _box.get(_previewKey(conversationId));

  Future<void> writePreview(String conversationId, String preview) =>
      _box.put(_previewKey(conversationId), preview);

  /// Forget every sender key for a group.
  ///
  /// Called when the membership changes. Whoever left must not be able to
  /// read what is said next, so every remaining member starts a new chain
  /// on their next message — this rotation is what makes "removed from
  /// the group" mean anything cryptographically.
  Future<void> clearGroupSenderKeys(String groupId) async {
    final doomed = <String>[
      for (final key in _box.keys)
        if (key is String && key.startsWith('senderkey/$groupId/')) key,
    ];
    await _box.deleteAll(doomed);
  }
}
