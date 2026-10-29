// Christ in Song across languages + links to the SDA Hymnal (patch_285).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:advent_connect_zw/models/hymn_model.dart';
import 'package:advent_connect_zw/services/cache_service.dart';
import 'package:advent_connect_zw/services/hymn_link_service.dart';
import 'package:advent_connect_zw/services/sabbath_service.dart';

Hymn _h(String collection, int number) => Hymn(
  id: '$collection-$number',
  title: '$collection $number',
  lyrics: 'L',
  language: HymnCollection.fromKey(collection).subtitle,
  number: number,
  collection: collection,
);

void main() {
  final hymns = [
    _h('sda_hymnal', 100),
    _h('sda_hymnal', 1),
    _h('kristu_munzwiyo', 1),
    _h('kristu_munzwiyo', 2),
    _h('cis_ndebele', 1),
  ];

  test('Christ in Song hymn → same number in other languages + SDA link', () {
    final out = HymnLinkService.counterparts(
      hymns[2],
      hymns,
      linkMap: {1: 100},
    );
    expect(out.map((h) => h.id), ['sda_hymnal-100', 'cis_ndebele-1']);
  });

  test('no link → only the other languages, never a guess', () {
    final out = HymnLinkService.counterparts(hymns[3], hymns, linkMap: {});
    expect(out, isEmpty);
  });

  test('SDA Hymnal hymn → every Christ in Song edition that links to it', () {
    final out = HymnLinkService.counterparts(
      hymns[0],
      hymns,
      linkMap: {1: 100},
    );
    expect(out.map((h) => h.id), ['kristu_munzwiyo-1', 'cis_ndebele-1']);
    // SDA Hymnal 1 is not linked from anywhere.
    expect(
      HymnLinkService.counterparts(hymns[1], hymns, linkMap: {1: 100}),
      isEmpty,
    );
  });

  test('a language shows in the switcher only once it has hymns', () {
    final keys = HymnCollection.availableIn(hymns).map((c) => c.key);
    expect(keys, ['sda_hymnal', 'kristu_munzwiyo', 'cis_ndebele']);
    final only = HymnCollection.availableIn([hymns[0], hymns[2]]);
    expect(only.map((c) => c.key), ['sda_hymnal', 'kristu_munzwiyo']);
  });

  test('planned languages share the Christ in Song numbering', () {
    final keys = HymnCollection.known.map((c) => c.key).toList();
    expect(keys.toSet().length, keys.length, reason: 'unique keys');
    for (final c in HymnCollection.planned) {
      expect(c.family, HymnCollection.christInSong, reason: c.key);
    }
    expect(HymnCollection.kristuMunzwiyo.family, HymnCollection.christInSong);
    expect(HymnCollection.sdaHymnal.family, isNull);
  });

  test('cached links decode safely', () {
    expect(HymnLinkService.decode('{"1":100,"2":214}'), {1: 100, 2: 214});
    expect(HymnLinkService.decode('{"x":1,"3":"no"}'), isEmpty);
    expect(HymnLinkService.decode('not json'), isEmpty);
  });

  test('the database table exists only as an admin-written link list', () {
    final sql = File('database/patch_285_hymn_links.sql').readAsStringSync();
    expect(sql.contains('is_super_admin()'), isTrue);
    expect(sql.contains('GRANT SELECT ON public.hymn_links TO anon'), isTrue);
  });

  group('Sabbath place', () {
    late Directory dir;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('sabbath_place');
      Hive.init(dir.path);
      await CacheService.debugUseBox(await Hive.openBox<String>('s'));
    });
    tearDown(() async {
      await CacheService.debugUseBox(null);
      await dir.delete(recursive: true);
    });

    test('a phone far from the sundown place is noticed', () async {
      await SabbathService.setGps(-17.83, 31.05); // Harare
      expect(SabbathService.usingGps(), isTrue);
      expect(
        SabbathService.timeZoneMismatchHours(
          deviceOffset: const Duration(hours: 2),
        ),
        lessThan(1),
      );
      expect(
        SabbathService.timeZoneMismatchHours(deviceOffset: Duration.zero),
        greaterThan(2),
      );
    });

    test('the location is rounded before it is stored', () async {
      await SabbathService.setGps(-17.834567, 31.051234);
      expect(CacheService.readPref('pref:sabbath_gps'), '-17.83,31.05');
    });
  });
}
