// Home's Today cards must open the exact thing they name.
//
// Founder report, 2 Aug 2026: "tapping a devotion card should open THAT
// exact thing — the Sabbath School lesson shown, the hymn of the day, the
// music of the day." Every slide pushed `library` with only a tab index,
// so the card named a hymn and then dropped the member into the whole
// hymnal to search for it. Music was the one exception; it already used
// this handoff, and the rest now do too.
//
// The intent is a static one-shot, which is exactly the kind of state
// that leaks between screens if a reader forgets to clear it — a stale
// id would re-open the reader every time the member returned to the
// Library. So what these tests pin is the take-once contract.

import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/services/library_launch_intent.dart';

void main() {
  setUp(LibraryLaunchIntent.clear);

  group('each target is read exactly once', () {
    test('music', () {
      LibraryLaunchIntent.musicItemId = 'track-1';

      expect(LibraryLaunchIntent.takeMusic(), 'track-1');
      // Returning to the Library later must not replay the jump.
      expect(LibraryLaunchIntent.takeMusic(), isNull);
    });

    test('egw', () {
      LibraryLaunchIntent.egwItemId = 'book-7';

      expect(LibraryLaunchIntent.takeEgw(), 'book-7');
      expect(LibraryLaunchIntent.takeEgw(), isNull);
    });

    test('hymn', () {
      LibraryLaunchIntent.hymnId = 'hymn-42';

      expect(LibraryLaunchIntent.takeHymn(), 'hymn-42');
      expect(LibraryLaunchIntent.takeHymn(), isNull);
    });

    test('quarterly', () {
      LibraryLaunchIntent.quarterlyId = 'en-2026-03';

      expect(LibraryLaunchIntent.takeQuarterly(), 'en-2026-03');
      expect(LibraryLaunchIntent.takeQuarterly(), isNull);
    });
  });

  test('an unset target reads as null rather than throwing', () {
    expect(LibraryLaunchIntent.takeMusic(), isNull);
    expect(LibraryLaunchIntent.takeEgw(), isNull);
    expect(LibraryLaunchIntent.takeHymn(), isNull);
    expect(LibraryLaunchIntent.takeQuarterly(), isNull);
  });

  test('the targets do not read each other', () {
    // Music and EGW are both `library_items` and both live in the
    // Library's TabBarView, so both tabs can be mounted at once. If they
    // shared one field, opening a book would start a track playing.
    LibraryLaunchIntent.egwItemId = 'book-7';

    expect(LibraryLaunchIntent.takeMusic(), isNull);
    expect(LibraryLaunchIntent.takeEgw(), 'book-7');
  });

  test('clear() drops every pending target', () {
    LibraryLaunchIntent.musicItemId = 'track-1';
    LibraryLaunchIntent.egwItemId = 'book-7';
    LibraryLaunchIntent.hymnId = 'hymn-42';
    LibraryLaunchIntent.quarterlyId = 'en-2026-03';

    LibraryLaunchIntent.clear();

    expect(LibraryLaunchIntent.takeMusic(), isNull);
    expect(LibraryLaunchIntent.takeEgw(), isNull);
    expect(LibraryLaunchIntent.takeHymn(), isNull);
    expect(LibraryLaunchIntent.takeQuarterly(), isNull);
  });
}
