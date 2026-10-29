// EGW page turn (29 Oct 2026): the old "book" turn overlapped two pages of
// text mid-swipe. Slide is now the default; Turn is the fixed alternative.

import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/services/egw_reader_prefs.dart';

void main() {
  setUp(EgwReaderPrefs.resetForTest);

  test('Slide is the default page turn', () {
    expect(EgwReaderPrefs.pageTurn(), EgwPageTurn.slide);
  });

  test('choosing Turn applies at once and rebuilds open readers', () {
    final before = EgwReaderPrefs.revision.value;
    EgwReaderPrefs.setPageTurn(EgwPageTurn.turn);
    expect(EgwReaderPrefs.pageTurn(), EgwPageTurn.turn);
    expect(EgwReaderPrefs.revision.value, greaterThan(before));
  });
}
