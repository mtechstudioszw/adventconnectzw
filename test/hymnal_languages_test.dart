// Hymnal by language (owner, 29 Oct 2026): English = SDA Hymnal, Shona =
// Kristu MuNzwiyo. The two number independently, so a number is never
// shown without its book; other languages have a slot that says "not yet".

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:advent_connect_zw/models/hymn_model.dart';
import 'package:advent_connect_zw/screens/library/hymnal_tab.dart';
import 'package:advent_connect_zw/services/cache_service.dart';

Hymn _hymn(String collection, int? number) => Hymn(
  id: '$collection-$number',
  title: 'T',
  lyrics: 'L',
  language: collection == 'sda_hymnal' ? 'English' : 'Shona',
  number: number,
  collection: collection,
);

void main() {
  test('English first, then Shona', () {
    expect(HymnCollection.all.map((c) => c.subtitle), ['English', 'Shona']);
  });

  test('a number always carries its hymnal', () {
    expect(_hymn('sda_hymnal', 40).reference, 'SDA Hymnal 40');
    expect(_hymn('kristu_munzwiyo', 40).reference, 'Kristu MuNzwiyo 40');
    expect(_hymn('kristu_munzwiyo', null).reference, 'Kristu MuNzwiyo');
  });

  group('remembered hymnal', () {
    late Directory dir;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('hymnal_lang');
      Hive.init(dir.path);
      await CacheService.debugUseBox(await Hive.openBox<String>('h'));
    });
    tearDown(() async {
      await CacheService.debugUseBox(null);
      await dir.delete(recursive: true);
    });

    test('Kristu MuNzwiyo until the member picks', () {
      expect(HymnPrefs.collection(), 'kristu_munzwiyo');
    });

    test('the pick sticks, and survives sign-out (pref: key)', () async {
      HymnPrefs.setCollection('sda_hymnal');
      await Future<void>.delayed(Duration.zero);
      expect(HymnPrefs.collection(), 'sda_hymnal');
      final src = File(
        'lib/screens/library/hymnal_tab.dart',
      ).readAsStringSync();
      expect(src.contains("'pref:hymnal_collection'"), isTrue);
    });
  });

  test('other languages get an honest "not yet" slot', () {
    final src = File('lib/screens/library/hymnal_tab.dart').readAsStringSync();
    expect(src.contains("'Not yet'"), isTrue);
  });
}
