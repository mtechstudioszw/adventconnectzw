import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../cache_service.dart';
import '../secure_storage_service.dart';
import 'e2ee_service.dart';

/// The backup file, sealed with a key only the member's password makes.
///
/// Layout: `ASB1` | iterations (u32 BE) | salt (16) | nonce (12) |
/// AES-256-GCM( gzip( JSON of readable history ) ) — tag at the end.
@immutable
class SealedBackup {
  const SealedBackup._();

  static const _magic = [0x41, 0x53, 0x42, 0x31]; // "ASB1"

  /// PBKDF2-HMAC-SHA256 rounds. Slow on purpose: a stolen backup file
  /// can only be attacked by guessing passwords, and each guess costs
  /// this much. ~0.5–1 s on a mid-range phone, done once per session.
  static const int iterations = 150000;

  static final Random _rng = Random.secure();
  static Uint8List random(int n) =>
      Uint8List.fromList(List<int>.generate(n, (_) => _rng.nextInt(256)));

  /// Derive the 32-byte key from a password. Run in an isolate (compute).
  static Uint8List deriveKey(String password, Uint8List salt, int rounds) {
    final kdf = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(salt, rounds, 32));
    return kdf.process(Uint8List.fromList(utf8.encode(password)));
  }

  static Uint8List seal(
    Map<String, String> entries,
    Uint8List key,
    Uint8List salt,
  ) {
    final nonce = random(12);
    final plain = Uint8List.fromList(
      gzip.encode(utf8.encode(jsonEncode(entries))),
    );
    final gcm = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)));
    final ct = gcm.process(plain);
    final header = ByteData(4)..setUint32(0, iterations);
    return Uint8List.fromList([
      ..._magic,
      ...header.buffer.asUint8List(),
      ...salt,
      ...nonce,
      ...ct,
    ]);
  }

  /// Salt and rounds from a file's header (needed to derive the key).
  static ({Uint8List salt, int rounds})? header(Uint8List file) {
    if (file.length < 4 + 4 + 16 + 12 + 16) return null;
    for (var i = 0; i < 4; i++) {
      if (file[i] != _magic[i]) return null;
    }
    final rounds = ByteData.sublistView(file, 4, 8).getUint32(0);
    return (salt: Uint8List.sublistView(file, 8, 24), rounds: rounds);
  }

  /// Opens a file with a derived key. Throws on a wrong password or a
  /// damaged file (GCM authentication fails).
  static Map<String, String> open(Uint8List file, Uint8List key) {
    final nonce = Uint8List.sublistView(file, 24, 36);
    final ct = Uint8List.sublistView(file, 36);
    final gcm = GCMBlockCipher(AESEngine())
      ..init(false, AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)));
    final plain = gcm.process(ct);
    final json = jsonDecode(utf8.decode(gzip.decode(plain))) as Map;
    return {for (final e in json.entries) '${e.key}': '${e.value}'};
  }
}

Uint8List _deriveInIsolate(Map<String, Object> a) => SealedBackup.deriveKey(
  a['p'] as String,
  a['s'] as Uint8List,
  a['r'] as int,
);

/// Wrong password, or a file that isn't a backup.
class BackupPasswordException implements Exception {
  const BackupPasswordException();
  @override
  String toString() => "That password doesn't open this backup.";
}

/// End-to-end encrypted chat backup (1 Nov 2026).
///
/// With encryption on, a new phone (or a reinstall) cannot read messages
/// from before — the keys that opened them lived on the old phone. This
/// backs up what the phone could READ (message text, photo/voice keys,
/// inbox lines), sealed with a key derived from a password the member
/// chooses. The server stores only the sealed file, in a private folder
/// only that member can read (patch_301). We never see the password: if
/// it is forgotten, the backup cannot be opened by anyone, including us.
class ChatBackupService {
  const ChatBackupService._();

  static SupabaseClient get _client => Supabase.instance.client;
  static const _bucket = 'chat_backups';

  static String? get _uid => _client.auth.currentUser?.id;
  static String _keyName(String uid) => 'chat_backup_key:$uid';
  static String _saltName(String uid) => 'chat_backup_salt:$uid';
  // User-scoped (no `pref:` prefix): sign-out clears it, as it should.
  static String _lastName(String uid) => 'chat_backup_last:$uid';
  static String _path(String uid) => '$uid/backup.bin';

  static final ValueNotifier<bool> busy = ValueNotifier(false);

  /// When this account was last backed up from this phone, if ever.
  static DateTime? get lastBackup {
    final uid = _uid;
    if (uid == null) return null;
    final raw = CacheService.readString(_lastName(uid));
    return raw == null ? null : DateTime.tryParse(raw);
  }

  /// Whether a backup password is set on this phone.
  static Future<bool> isEnabled() async {
    final uid = _uid;
    if (uid == null) return false;
    return (await SecureStorageService.read(_keyName(uid))) != null;
  }

  /// Is there a backup on the server for this account?
  static Future<bool> hasRemoteBackup() async {
    final uid = _uid;
    if (uid == null) return false;
    try {
      final files = await _client.storage.from(_bucket).list(path: uid);
      return files.any((f) => f.name == 'backup.bin');
    } catch (_) {
      return false;
    }
  }

  /// Turns backup on with [password] and backs up straight away.
  static Future<void> enable(String password) async {
    final uid = _uid;
    if (uid == null) throw const AuthException('Sign in first.');
    final salt = SealedBackup.random(16);
    final key = await compute(_deriveInIsolate, {
      'p': password,
      's': salt,
      'r': SealedBackup.iterations,
    });
    await SecureStorageService.write(_keyName(uid), base64Encode(key));
    await SecureStorageService.write(_saltName(uid), base64Encode(salt));
    await backupNow();
  }

  /// Stops backing up from this phone and deletes the server copy.
  static Future<void> disable() async {
    final uid = _uid;
    if (uid == null) return;
    await SecureStorageService.delete(_keyName(uid));
    await SecureStorageService.delete(_saltName(uid));
    try {
      await _client.storage.from(_bucket).remove([_path(uid)]);
    } catch (_) {}
  }

  /// Seals and uploads now. Returns how many entries were saved.
  static Future<int> backupNow() async {
    final uid = _uid;
    if (uid == null) return 0;
    final keyB64 = await SecureStorageService.read(_keyName(uid));
    final saltB64 = await SecureStorageService.read(_saltName(uid));
    if (keyB64 == null || saltB64 == null) return 0;
    busy.value = true;
    try {
      final entries = E2eeService.exportReadable();
      final file = SealedBackup.seal(
        entries,
        base64Decode(keyB64),
        base64Decode(saltB64),
      );
      await _client.storage.from(_bucket).uploadBinary(
        _path(uid),
        file,
        fileOptions: const FileOptions(
          upsert: true,
          contentType: 'application/octet-stream',
        ),
      );
      await CacheService.writeString(
        _lastName(uid),
        DateTime.now().toUtc().toIso8601String(),
      );
      return entries.length;
    } finally {
      busy.value = false;
    }
  }

  /// Backs up if it's been more than a day. Called on app start; never
  /// throws.
  static Future<void> autoBackup() async {
    try {
      if (!await isEnabled()) return;
      final last = lastBackup;
      if (last != null &&
          DateTime.now().toUtc().difference(last) < const Duration(hours: 24)) {
        return;
      }
      await backupNow();
    } catch (e) {
      debugPrint('ChatBackupService.autoBackup: $e');
    }
  }

  /// Restores from the server copy with [password]. Returns how many
  /// messages came back. Also keeps backing up with the same password.
  static Future<int> restore(String password) async {
    final uid = _uid;
    if (uid == null) throw const AuthException('Sign in first.');
    busy.value = true;
    try {
      final file = await _client.storage.from(_bucket).download(_path(uid));
      final head = SealedBackup.header(file);
      if (head == null) throw const BackupPasswordException();
      final key = await compute(_deriveInIsolate, {
        'p': password,
        's': head.salt,
        'r': head.rounds,
      });
      final Map<String, String> entries;
      try {
        entries = SealedBackup.open(file, key);
      } catch (_) {
        throw const BackupPasswordException();
      }
      final n = await E2eeService.importReadable(entries);
      await SecureStorageService.write(_keyName(uid), base64Encode(key));
      await SecureStorageService.write(
        _saltName(uid),
        base64Encode(head.salt),
      );
      return n;
    } finally {
      busy.value = false;
    }
  }
}
