import 'package:advent_connect_zw/services/bible_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// #1, second half: tapping the verse of the day must open the Bible AT that
/// verse, not at the top of the Library.
///
/// The reference is free text written by whoever authored the devotion, so
/// the resolver has to cope with "John 3:16", "1 Cor. 13:4" and "I John 4:8"
/// meaning what they obviously mean. A miss here is silent — it just drops
/// the member somewhere plausible-looking and wrong.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a plain reference resolves, 1-based', () async {
    final ref = await BibleService.resolveReference('John 3:16');
    expect(ref, isNotNull);
    expect(ref!.book.name, 'John');
    expect(ref.chapter, 3);
    expect(ref.verse, 16);
  });

  test('"John" is never swallowed by "1 John"', () async {
    // Exact match has to beat prefix match, or every John reference lands
    // in an epistle.
    final ref = await BibleService.resolveReference('John 1:1');
    expect(ref!.book.name, 'John');

    final first = await BibleService.resolveReference('1 John 4:8');
    expect(first!.book.name, contains('John'));
    expect(first.book.name, isNot('John'));
  });

  test('abbreviations and Roman numerals resolve', () async {
    for (final raw in ['1 Cor 13:4', '1 Cor. 13:4', 'I Corinthians 13:4']) {
      final ref = await BibleService.resolveReference(raw);
      expect(ref, isNotNull, reason: '"$raw" should resolve');
      expect(ref!.book.name, contains('Corinthians'), reason: raw);
      expect(ref.chapter, 13);
      expect(ref.verse, 4);
    }
  });

  test('multi-word book names resolve', () async {
    final ref = await BibleService.resolveReference('Song of Solomon 2:1');
    expect(ref, isNotNull);
    expect(ref!.chapter, 2);
    expect(ref.verse, 1);
  });

  test('a chapter-only reference is fine and carries no verse', () async {
    final ref = await BibleService.resolveReference('Psalms 23');
    expect(ref, isNotNull);
    expect(ref!.chapter, 23);
    expect(ref.verse, isNull);
  });

  test('nonsense returns null so the caller can fall back', () async {
    // Null is the contract: the card opens the Bible tab instead of
    // guessing a chapter and landing somewhere wrong.
    expect(await BibleService.resolveReference(''), isNull);
    expect(await BibleService.resolveReference('Hesitations 3:16'), isNull);
    expect(await BibleService.resolveReference('no numbers here'), isNull);
  });

  test('a chapter past the end of the book is refused', () async {
    expect(await BibleService.resolveReference('Jude 5:1'), isNull);
  });
}
