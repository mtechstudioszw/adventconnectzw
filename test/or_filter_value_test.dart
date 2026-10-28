// Search pasted the raw term into PostgREST or() filters, so a
// comma or bracket ("Bible, KJV", "Hymnal (Shona)") was parsed as filter
// syntax, the request failed and no products came back.

import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/utils/postgrest_filter.dart';

void main() {
  test('commas and brackets stay inside one quoted value', () {
    expect(orFilterValue('%Bible, KJV%'), '"%Bible, KJV%"');
    expect(orFilterValue('%Hymnal (Shona)%'), '"%Hymnal (Shona)%"');
  });

  test('quotes and backslashes are escaped, not left to close the value', () {
    expect(orFilterValue('12" frame'), r'"12\" frame"');
    expect(orFilterValue(r'a\b'), r'"a\\b"');
  });
}
