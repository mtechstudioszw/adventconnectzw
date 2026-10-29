// Sabbath times for any country and state (owner, 29 Oct 2026).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'package:advent_connect_zw/services/cache_service.dart';
import 'package:advent_connect_zw/services/sabbath_places.dart';
import 'package:advent_connect_zw/services/sabbath_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final countries = SabbathPlaces.parse(
    File('assets/geo/sabbath_places.json').readAsStringSync(),
  );

  test('the world is covered', () {
    expect(countries.length, greaterThan(200));
    final us = countries.firstWhere((c) => c.code == 'US');
    expect(us.regions.length, 51, reason: '50 states + DC');
    expect(us.spansTimeZones, isTrue);
    final ca = us.regions.firstWhere((r) => r.name == 'California');
    expect(ca.timeZone, 'America/Los_Angeles');
    final zw = countries.firstWhere((c) => c.code == 'ZW');
    expect(zw.regions.length, 10);
    expect(zw.spansTimeZones, isFalse);
    for (final code in ['BR', 'AU', 'CA', 'MX', 'RU', 'ID', 'KE', 'GB']) {
      expect(countries.any((c) => c.code == code), isTrue, reason: code);
    }
  });

  test('every place is a real coordinate in a real time zone', () {
    tzdata.initializeTimeZones();
    final bad = <String>[];
    for (final c in countries) {
      expect(c.regions, isNotEmpty, reason: c.name);
      for (final r in c.regions) {
        if (r.lat.abs() > 90 || r.lon.abs() > 180) {
          bad.add('${c.code} ${r.name}');
        }
        try {
          tz.getLocation(r.timeZone);
        } catch (_) {
          bad.add('${c.code} ${r.name} ${r.timeZone}');
        }
      }
    }
    expect(bad, isEmpty);
  });

  group('chosen place', () {
    late Directory dir;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('sabbath_places');
      Hive.init(dir.path);
      await CacheService.debugUseBox(await Hive.openBox<String>('p'));
    });
    tearDown(() async {
      await CacheService.debugUseBox(null);
      await dir.delete(recursive: true);
    });

    Future<void> choose(String cc, String region) async {
      final c = countries.firstWhere((c) => c.code == cc);
      final r = c.regions.firstWhere((r) => r.name == region);
      await SabbathService.setPlace(
        country: c.code,
        countryName: c.name,
        region: r.name,
        city: r.city,
        lat: r.lat,
        lon: r.lon,
        timeZone: r.timeZone,
      );
    }

    test(
      'California and New York each get their own sundown, in local time',
      () async {
        final friday = DateTime(2026, 10, 30);
        await choose('US', 'California');
        expect(SabbathService.locationLabel(), 'California, United States');
        final la = SabbathService.placeTime(SabbathService.sunsetOn(friday));
        // Los Angeles, 30 Oct 2026: sunset ≈ 18:00 PDT (NOAA, ±3 min).
        expect(
          la.hour * 60 + la.minute,
          inInclusiveRange(17 * 60 + 56, 18 * 60 + 5),
        );

        await choose('US', 'New York');
        final ny = SabbathService.placeTime(SabbathService.sunsetOn(friday));
        // New York City, 30 Oct 2026: sunset ≈ 17:52 EDT (NOAA, ±3 min).
        expect(
          ny.hour * 60 + ny.minute,
          inInclusiveRange(17 * 60 + 48, 17 * 60 + 58),
        );
      },
    );

    test('the place decides the day and the clock, not the phone', () async {
      await choose('US', 'California');
      // 05:00 UTC Saturday is still Friday evening in Los Angeles.
      final t = DateTime.utc(2026, 10, 31, 5);
      expect(SabbathService.placeCalendarNow(t).weekday, DateTime.friday);
      expect(SabbathService.placeCalendarNow(t).hour, 22);
      // ...and past Friday sundown there, so the Sabbath has begun.
      expect(SabbathService.isSabbathNow(from: t), isTrue);
      // 23:00 UTC Friday is 16:00 in LA: not yet.
      expect(
        SabbathService.isSabbathNow(from: DateTime.utc(2026, 10, 30, 23)),
        isFalse,
      );
    });

    test('changing the place tells the app', () async {
      var heard = 0;
      void listener() => heard++;
      SabbathService.changes.addListener(listener);
      await choose('ZW', 'Harare');
      await SabbathService.setGps(-20.15, 28.58);
      await SabbathService.clearGps();
      SabbathService.changes.removeListener(listener);
      expect(heard, 3);
    });

    test(
      'a place replaces GPS and province, and the other way round',
      () async {
        await SabbathService.setGps(-17.83, 31.05);
        await choose('KE', 'Nairobi County');
        expect(SabbathService.usingGps(), isFalse);
        expect(SabbathService.place()!.country, 'KE');
        await SabbathService.setProvince('Bulawayo');
        expect(SabbathService.place(), isNull);
      },
    );
  });
}
