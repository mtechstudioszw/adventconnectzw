// E2EE for photos and voice notes (1 Nov 2026).

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/services/e2ee/e2ee_envelope.dart';
import 'package:advent_connect_zw/services/e2ee/media_crypto.dart';

void main() {
  final photo = Uint8List.fromList(List<int>.generate(5000, (i) => i % 251));

  test('a sealed file opens with its key and looks nothing like the photo',
      () {
    final sealed = MediaCrypto.encrypt(photo);
    expect(sealed.bytes.length, photo.length + 16); // + GCM tag
    expect(sealed.bytes.sublist(0, 64), isNot(photo.sublist(0, 64)));
    expect(MediaCrypto.decrypt(sealed.bytes, sealed.key), photo);
  });

  test('every file gets its own key', () {
    final a = MediaCrypto.encrypt(photo).key;
    final b = MediaCrypto.encrypt(photo).key;
    expect(a.key, isNot(b.key));
  });

  test('a wrong key or a changed byte is refused, not shown as garbage', () {
    final sealed = MediaCrypto.encrypt(photo);
    final other = MediaCrypto.encrypt(photo).key;
    expect(() => MediaCrypto.decrypt(sealed.bytes, other), throwsA(anything));
    final tampered = Uint8List.fromList(sealed.bytes)..[10] ^= 1;
    expect(() => MediaCrypto.decrypt(tampered, sealed.key), throwsA(anything));
  });

  test('the envelope becomes the caption plus a local key', () {
    final key = MediaCrypto.encrypt(photo).key;
    final env = key.envelope(kind: 'image', caption: 'Camp meeting');
    final row = E2eeEnvelope.withPlaintext({'id': '1', 'content': 'x'}, env);
    expect(row['content'], 'Camp meeting');
    final back = MediaKey.fromMeta(row['meta']);
    expect(back?.key, key.key);
    expect(back?.nonce, key.nonce);
  });

  test('labels for a bare photo and a voice note', () {
    final key = MediaCrypto.encrypt(photo).key;
    expect(
      E2eeEnvelope.withPlaintext({}, key.envelope(kind: 'image'))['content'],
      '📷 Photo',
    );
    expect(
      E2eeEnvelope.withPlaintext({}, key.envelope(kind: 'voice'))['content'],
      '🎙️ Voice note',
    );
  });

  test('ordinary text, even JSON a member typed, stays text', () {
    for (final t in ['hello', '{"a":1}', jsonEncode({'e2m': 2, 'k': 'x'})]) {
      final row = E2eeEnvelope.withPlaintext({'content': ''}, t);
      expect(row['content'], t);
      expect(row['meta'], isNull);
    }
  });

  test('existing meta (a product share) is kept alongside the key', () {
    final key = MediaCrypto.encrypt(photo).key;
    final row = E2eeEnvelope.withPlaintext(
      {'meta': {'product_id': '9'}},
      key.envelope(kind: 'image'),
    );
    expect((row['meta'] as Map)['product_id'], '9');
    expect(MediaKey.fromMeta(row['meta']), isNotNull);
  });
}
