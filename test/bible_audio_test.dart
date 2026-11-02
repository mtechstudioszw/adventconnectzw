import 'dart:convert';
import 'dart:io';

import 'package:advent_connect_zw/models/bible_translation.dart';
import 'package:advent_connect_zw/services/bible_audio_service.dart';
import 'package:advent_connect_zw/services/read_aloud_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BibleAudio', () {
    const hays = BibleNarrator('hays', 'Barry Hays');

    test('builds the narrated chapter URL (1-based chapter)', () {
      expect(
        BibleAudio.url(42, 2, voice: hays),
        'https://audio.bible.helloao.org/api/BSB/JHN/3/audio/hays.mp3',
      );
      expect(
        BibleAudio.url(0, 0, voice: hays),
        'https://audio.bible.helloao.org/api/BSB/GEN/1/audio/hays.mp3',
      );
      expect(
        BibleAudio.url(65, 21, voice: hays),
        'https://audio.bible.helloao.org/api/BSB/REV/22/audio/hays.mp3',
      );
    });

    test('track ids are file-name safe and differ per voice', () {
      final a = BibleAudio.trackId(42, 2, voice: hays);
      final b = BibleAudio.trackId(
        42,
        2,
        voice: const BibleNarrator('souer', 'Bob Souer'),
      );
      expect(a, 'bibleaudio-bsb-42-2-hays');
      expect(a, isNot(b));
      expect(RegExp(r'^[a-z0-9-]+$').hasMatch(a), isTrue);
    });

    test('only English translations offer narration', () {
      expect(BibleAudio.availableFor(BibleTranslations.kjv), isTrue);
      expect(BibleAudio.availableFor(BibleTranslations.bsb), isTrue);
      expect(BibleAudio.availableFor(BibleTranslations.shona), isFalse);
      expect(BibleAudio.wordingDiffers(BibleTranslations.kjv), isTrue);
      expect(BibleAudio.wordingDiffers(BibleTranslations.bsb), isFalse);
    });
  });

  group('Shona Bible is bundled', () {
    final data =
        jsonDecode(File('assets/bible/sna_bib.json').readAsStringSync())
            as Map<String, dynamic>;
    final books = data['books'] as Map<String, dynamic>;

    test('has all 66 books and ~31k verses', () {
      expect(books.length, 66);
      var verses = 0;
      for (final b in books.values) {
        for (final c in b as List) {
          verses += ((c as Map)['v'] as List).length;
        }
      }
      expect(verses, greaterThan(31000));
    });

    test('John 3:16 is present', () {
      final v = ((books['JHN'] as List)[2] as Map)['v'] as List;
      expect(v[15] as String, contains('Mwari akada nyika'));
    });

    test('translation is offline and credits the licence', () {
      expect(BibleTranslations.shona.isOffline, isTrue);
      expect(BibleTranslations.shona.assetPath, 'assets/bible/sna_bib.json');
      expect(BibleTranslations.shona.attribution, isNotNull);
    });
  });

  group('ReadAloud chunks', () {
    test('short text is one chunk', () {
      expect(ReadAloud.chunksForTest('Hello there.', 100), ['Hello there.']);
    });

    test('long text splits at sentence ends and loses nothing', () {
      final text = List.generate(200, (i) => 'Sentence number $i.').join(' ');
      final chunks = ReadAloud.chunksForTest(text, 300);
      expect(chunks.length, greaterThan(1));
      for (final c in chunks) {
        expect(c.length, lessThanOrEqualTo(300));
      }
      expect(chunks.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim(), text);
    });
  });
}
