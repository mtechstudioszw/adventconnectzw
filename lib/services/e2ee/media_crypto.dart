import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// The per-file key for one encrypted photo or voice note.
///
/// How WhatsApp does media, and how this does it: every file gets its own
/// random AES-256 key. The file is encrypted with it and uploaded as
/// opaque bytes; the KEY travels inside the Signal-encrypted message body,
/// so only the people who can open the message can open the file. The
/// storage bucket ends up holding noise.
class MediaKey {
  const MediaKey(this.key, this.nonce);

  final Uint8List key; // 32 bytes
  final Uint8List nonce; // 12 bytes

  /// Marker key in the envelope JSON. Short on purpose: it is inside a
  /// ciphertext that is padded per message anyway.
  static const String _marker = 'e2m';

  /// The body a media message's ciphertext carries, as JSON text:
  /// `{"e2m":1,"t":"image","k":"…","n":"…","c":"caption"}`.
  String envelope({required String kind, String? caption}) => jsonEncode({
    _marker: 1,
    't': kind,
    'k': base64Encode(key),
    'n': base64Encode(nonce),
    if ((caption ?? '').trim().isNotEmpty) 'c': caption!.trim(),
  });

  /// What a decrypted row stores in `meta` so the bubble can open the
  /// file. Kept on the phone only — never written back to the server.
  Map<String, String> toMeta() => {
    'k': base64Encode(key),
    'n': base64Encode(nonce),
  };

  static MediaKey? fromMeta(Object? meta) {
    if (meta is! Map) return null;
    final m = meta[MediaCrypto.metaKey];
    if (m is! Map) return null;
    try {
      final k = base64Decode(m['k'].toString());
      final n = base64Decode(m['n'].toString());
      if (k.length != 32 || n.length != 12) return null;
      return MediaKey(k, n);
    } catch (_) {
      return null;
    }
  }
}

/// A decoded media envelope.
class MediaEnvelope {
  const MediaEnvelope({required this.kind, required this.key, this.caption});
  final String kind;
  final MediaKey key;
  final String? caption;

  /// What the bubble and inbox show in place of the JSON.
  String get label {
    if (kind == 'voice') return '🎙️ Voice note';
    final c = (caption ?? '').trim();
    return c.isEmpty ? '📷 Photo' : c;
  }

  /// Parses decrypted text. Null when it is an ordinary text message —
  /// including one a member typed that merely looks like JSON.
  static MediaEnvelope? tryParse(String plaintext) {
    final t = plaintext.trimLeft();
    if (!t.startsWith('{"${MediaKey._marker}"')) return null;
    try {
      final j = jsonDecode(t);
      if (j is! Map || j[MediaKey._marker] != 1) return null;
      final k = base64Decode(j['k'].toString());
      final n = base64Decode(j['n'].toString());
      if (k.length != 32 || n.length != 12) return null;
      return MediaEnvelope(
        kind: (j['t'] ?? 'image').toString(),
        key: MediaKey(k, n),
        caption: j['c']?.toString(),
      );
    } catch (_) {
      return null;
    }
  }
}

/// AES-256-GCM over whole files. Photos here are compressed before
/// upload and voice notes are seconds of AAC, so one-shot is fine.
class MediaCrypto {
  const MediaCrypto._();

  /// Where a decrypted row keeps the file key inside `meta`.
  static const String metaKey = 'e2ee_media';

  static final Random _rng = Random.secure();

  static Uint8List _random(int n) =>
      Uint8List.fromList(List<int>.generate(n, (_) => _rng.nextInt(256)));

  static GCMBlockCipher _cipher(bool encrypt, MediaKey k) =>
      GCMBlockCipher(AESEngine())..init(
        encrypt,
        AEADParameters(KeyParameter(k.key), 128, k.nonce, Uint8List(0)),
      );

  /// Encrypts [plain] under a fresh key. The output carries the 16-byte
  /// GCM tag at its end, so tampering is detected on the way back.
  static ({Uint8List bytes, MediaKey key}) encrypt(Uint8List plain) {
    final key = MediaKey(_random(32), _random(12));
    return (bytes: _cipher(true, key).process(plain), key: key);
  }

  /// Opens bytes from [encrypt]. Throws if the key is wrong or a single
  /// byte was changed — the caller shows the "couldn't load" state.
  static Uint8List decrypt(Uint8List cipher, MediaKey key) =>
      _cipher(false, key).process(cipher);
}
