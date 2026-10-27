// Regression: the reader's day chips said "Mon" over Tuesday's reading.
//
// The strip indexed a Sabbath-first label list with `weekday % 7`, which
// shifted every chip back one day. The dates from the API were right all
// along — the fixture below is lesson 05 of quarter 2026-04 exactly as
// `sabbath-school.adventech.io` serves it, supplements included.

import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/models/sabbath_school_model.dart';

SsDay _day(String id, String date) => SsDay.fromJson({
      'id': id,
      'title': id,
      'read_path': 'en/quarterlies/2026-04/lessons/05/days/$id/read',
      'date': date,
    });

void main() {
  final week = [
    _day('01', '24/10/2026'),
    _day('02', '25/10/2026'),
    _day('03', '26/10/2026'),
    _day('04', '27/10/2026'),
    _day('05', '28/10/2026'),
    _day('06', '29/10/2026'),
    _day('07', '30/10/2026'),
  ];

  test('each of the seven chips names its own date\'s weekday', () {
    expect(
      [for (final d in week) d.chipLabel],
      ['Sab', 'Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri'],
    );
  });

  test('ssWeekdayShort covers every DateTime.weekday', () {
    // 26 Oct 2026 is a Monday; walk a full week from there.
    const expected = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sab', 'Sun'];
    for (var i = 0; i < 7; i++) {
      final date = DateTime(2026, 10, 26 + i);
      expect(ssWeekdayShort(date), expected[i], reason: '$date');
    }
  });

  test('dates are calendar dates — no timezone shift', () {
    final d = parseSsDate('27/10/2026')!;
    expect([d.year, d.month, d.day, d.hour], [2026, 10, 27, 0]);
    expect(d.isUtc, isFalse);
    expect(formatSsDate(d), '27/10/2026');
  });

  test('a lesson spanning a month boundary keeps its weekdays', () {
    // Sabbath 31 Oct → Friday 6 Nov 2026.
    final labels = [
      for (var i = 0; i < 7; i++)
        _day('0${i + 1}', formatSsDate(DateTime(2026, 10, 31 + i))!)
            .chipLabel,
    ];
    expect(labels, ['Sab', 'Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri']);
  });

  group('supplements', () {
    final extras = [
      _day('hope-ss', '30/10/2026'),
      _day('inside-story', '30/10/2026'),
      _day('teacher-comments', '30/10/2026'),
    ];

    test('are not daily readings and are not labelled as a weekday', () {
      expect(extras.map((d) => d.isDailyReading), everyElement(isFalse));
      expect(extras.map((d) => d.chipLabel), ['Hope', 'Story', 'Teacher']);
    });

    test('are never "today", even on their own Friday', () {
      final friday = DateTime.now();
      final s = formatSsDate(friday)!;
      expect(_day('inside-story', s).isToday, isFalse);
      expect(_day('07', s).isToday, isTrue);
    });
  });

  test('an undated daily reading falls back to its number', () {
    final d = SsDay.fromJson({'id': '03', 'title': 't', 'read_path': 'p'});
    expect(d.chipLabel, '3');
  });
}
