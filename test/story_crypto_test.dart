// End-to-end encrypted stories (patch_300).

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/models/story_model.dart';
import 'package:advent_connect_zw/services/e2ee/media_crypto.dart';
import 'package:advent_connect_zw/services/e2ee/story_crypto.dart';

Story _story({int? e2ee, bool locked = false}) => Story(
  id: 's1',
  authorId: 'a',
  authorName: 'Rudo',
  mediaUrl: 'https://x.test/blob.bin',
  createdAt: DateTime.utc(2026, 11, 1),
  expiresAt: DateTime.utc(2026, 11, 2),
  e2eeVersion: e2ee,
  locked: locked,
);

void main() {
  test('an envelope round-trips text, caption and the photo key', () {
    final key = MediaCrypto.encrypt(_bytes).key;
    final env = StoryEnvelope(text: 'Happy Sabbath', caption: 'Camp', key: key);
    final back = StoryEnvelope.decode(env.encode())!;
    expect(back.text, 'Happy Sabbath');
    expect(back.caption, 'Camp');
    expect(back.key!.key, key.key);
    expect(back.key!.nonce, key.nonce);
  });

  test('anything that is not a story envelope is refused', () {
    expect(StoryEnvelope.decode('hello'), isNull);
    expect(StoryEnvelope.decode('{"e2m":1}'), isNull);
  });

  test('an opened story carries the text and key; a locked one says so', () {
    final key = MediaCrypto.encrypt(_bytes).key;
    final s = _story(
      e2ee: 1,
    ).opened(textContent: 'Amen', caption: 'Choir', mediaKey: key);
    expect(s.isEncrypted, isTrue);
    expect(s.locked, isFalse);
    expect(s.textContent, 'Amen');
    expect(s.caption, 'Choir');
    expect(s.mediaKey, isNotNull);
    expect(_story(e2ee: 1).opened(locked: true).locked, isTrue);
  });

  test('the offline cache keeps the key, the lock and the version', () {
    final key = MediaCrypto.encrypt(_bytes).key;
    final s = _story(e2ee: 1).opened(mediaKey: key);
    final back = Story.fromJson(s.toJson());
    expect(back.isEncrypted, isTrue);
    expect(back.mediaKey?.key, key.key);
    expect(
      Story.fromJson(_story(e2ee: 1, locked: true).toJson()).locked,
      isTrue,
    );
  });

  test('plain stories are untouched', () {
    final s = _story();
    expect(s.isEncrypted, isFalse);
    expect(Story.fromJson(s.toJson()).mediaKey, isNull);
  });
}

final _bytes = Uint8List.fromList(List<int>.generate(64, (i) => i));
