// "EGW read of the day" must open the BOOK, not the shelf.
//
// The Today card names a specific book and hands its id to
// LibraryLaunchIntent. The EGW tab is supposed to pick that up once its
// catalogue loads and open the reader. It never did, because the guard read:
//
//     if (widget.kind != 'egw') return;
//
// while the widget's own default kind is 'egw_book'. The condition was
// therefore true on every build, the intent was dropped, and the member
// landed on the shelf — exactly what the feature existed to stop.
//
// Nothing threw. A wrong `kind` returns an empty list or falls out of an
// `if`, which is why this string has now caused three separate bugs.
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/screens/library/egw_tab.dart';
import 'package:advent_connect_zw/services/library_launch_intent.dart';

void main() {
  group('the EGW kind string', () {
    test('is egw_book, never egw', () {
      expect(EgwTab.egwKind, 'egw_book');
      expect(EgwTab.egwKind, isNot('egw'));
    });

    test('the default constructor kind matches the constant', () {
      // The guard compares widget.kind against egwKind. If the default ever
      // drifts from the constant, the intent is silently dropped again and
      // no test that merely builds the tab would notice.
      expect(const EgwTab().kind, EgwTab.egwKind);
    });
  });

  group('launch intent handoff', () {
    setUp(LibraryLaunchIntent.clear);
    tearDown(LibraryLaunchIntent.clear);

    test('take returns the id once, then clears it', () {
      LibraryLaunchIntent.egwItemId = 'book-42';
      expect(LibraryLaunchIntent.takeEgw(), 'book-42');
      // Second read must be null, or returning to the Library later
      // re-opens a book the member did not ask for.
      expect(LibraryLaunchIntent.takeEgw(), isNull);
    });

    test('each kind is taken independently', () {
      // Library tabs are mounted together in a TabBarView, so a tab
      // consuming the wrong intent would steal another tab's target.
      LibraryLaunchIntent.egwItemId = 'book-1';
      LibraryLaunchIntent.musicItemId = 'track-1';
      LibraryLaunchIntent.hymnId = 'hymn-1';
      LibraryLaunchIntent.quarterlyId = 'q-1';

      expect(LibraryLaunchIntent.takeEgw(), 'book-1');
      expect(LibraryLaunchIntent.musicItemId, 'track-1');
      expect(LibraryLaunchIntent.hymnId, 'hymn-1');
      expect(LibraryLaunchIntent.quarterlyId, 'q-1');
    });

    test('clear() drops every pending target', () {
      LibraryLaunchIntent.egwItemId = 'book-1';
      LibraryLaunchIntent.musicItemId = 'track-1';
      LibraryLaunchIntent.clear();
      expect(LibraryLaunchIntent.takeEgw(), isNull);
      expect(LibraryLaunchIntent.takeMusic(), isNull);
    });
  });
}
