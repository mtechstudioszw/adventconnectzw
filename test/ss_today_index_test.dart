// The Home "Sabbath School" Today card opens today's reading, not the
// quarter's 13-week list. These pin the lookup that decides which day.

import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/models/sabbath_school_model.dart';
import 'package:advent_connect_zw/services/library_launch_intent.dart';

SsDay _day(String id, String date) => SsDay.fromJson({
      'id': id,
      'title': id,
      'read_path': 'en/quarterlies/2026-04/lessons/05/days/$id/read',
      'date': date,
    });

void main() {
  // Lesson 05 of 2026-04 as Adventech serves it, supplements dated Friday.
  final week = [
    _day('01', '24/10/2026'),
    _day('02', '25/10/2026'),
    _day('03', '26/10/2026'),
    _day('04', '27/10/2026'),
    _day('05', '28/10/2026'),
    _day('06', '29/10/2026'),
    _day('07', '30/10/2026'),
    _day('hope-ss', '30/10/2026'),
    _day('inside-story', '30/10/2026'),
    _day('teacher-comments', '30/10/2026'),
  ];

  test('Wednesday opens Wednesday\'s reading', () {
    expect(ssTodayIndex(week, now: DateTime(2026, 10, 28, 21, 30)), 4);
  });

  test('Sabbath opens the Sabbath afternoon reading', () {
    expect(ssTodayIndex(week, now: DateTime(2026, 10, 24, 0, 5)), 0);
  });

  test('Friday opens the daily reading, never a supplement', () {
    expect(ssTodayIndex(week, now: DateTime(2026, 10, 30)), 6);
  });

  test('a day outside the week is -1, so the caller stays on the list', () {
    expect(ssTodayIndex(week, now: DateTime(2026, 10, 31)), -1);
    expect(ssTodayIndex(const [], now: DateTime(2026, 10, 28)), -1);
  });

  test('the open-today flag is one-shot and cleared with the rest', () {
    LibraryLaunchIntent.openToday = true;
    expect(LibraryLaunchIntent.takeOpenToday(), isTrue);
    expect(LibraryLaunchIntent.takeOpenToday(), isFalse);

    LibraryLaunchIntent.quarterlyId = '2026-04';
    LibraryLaunchIntent.openToday = true;
    LibraryLaunchIntent.clear();
    expect(LibraryLaunchIntent.takeQuarterly(), isNull);
    expect(LibraryLaunchIntent.takeOpenToday(), isFalse);
  });
}
