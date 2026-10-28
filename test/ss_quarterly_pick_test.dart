// The Library tab and Home's Today card each chose "this quarter" their own
// way and could disagree (Easy Reading vs Standard Adult), and "More
// quarters" listed same-titled editions with nothing to tell them apart.

import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/models/sabbath_school_model.dart';

Quarterly _q(String id, String? group, {bool current = true}) {
  final now = DateTime.now();
  final start = current
      ? now.subtract(const Duration(days: 10))
      : now.subtract(const Duration(days: 200));
  final end = current
      ? now.add(const Duration(days: 60))
      : now.subtract(const Duration(days: 110));
  String d(DateTime x) =>
      '${x.day.toString().padLeft(2, '0')}/${x.month.toString().padLeft(2, '0')}/${x.year}';
  return Quarterly.fromJson({
    'id': id,
    'title': 'The Gift of Prophecy',
    'start_date': d(start),
    'end_date': d(end),
    if (group != null) 'quarterly_group': {'name': group},
  });
}

void main() {
  test('Standard Adult wins even when Easy Reading comes first', () {
    final picked = pickCurrentQuarterly([
      _q('2026-04-er', 'Easy Reading'),
      _q('2026-04', 'Standard Adult'),
    ]);
    expect(picked!.id, '2026-04');
  });

  test('falls back to any current edition, then the newest', () {
    expect(
      pickCurrentQuarterly([
        _q('2026-03', 'Standard Adult', current: false),
        _q('2026-04-er', 'Easy Reading'),
      ])!.id,
      '2026-04-er',
    );
    expect(
      pickCurrentQuarterly([_q('2026-03', null, current: false)])!.id,
      '2026-03',
    );
    expect(pickCurrentQuarterly(const []), isNull);
  });

  test('only non-standard editions get a label', () {
    expect(_q('a', 'Easy Reading').editionLabel, 'Easy Reading');
    expect(_q('b', 'Standard Adult').editionLabel, isNull);
    expect(_q('c', null).editionLabel, isNull);
  });
}
