import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:advent_connect_zw/screens/library/sabbath_hours_screen.dart';
import 'package:advent_connect_zw/screens/library/sabbath_place_picker.dart';
import 'package:advent_connect_zw/services/cache_service.dart';
import 'package:advent_connect_zw/services/sabbath_service.dart';

import '../test/helpers/fake_supabase.dart';
import 'shot.dart';

void main() {
  setUpAll(() async {
    await loadShotFonts();
    await initFakeSupabase();
    await signInFake('me', metadata: {'country': 'US'});
    final dir = await Directory.systemTemp.createTemp('sabbath_shot');
    Hive.init(dir.path);
    // ignore: invalid_use_of_visible_for_testing_member
    await CacheService.debugUseBox(await Hive.openBox<String>('s'));
  });

  testWidgets('picker', (t) async {
    await pumpShot(t, const SabbathPlacePicker(homeCountry: 'US'), dark: false);
    await t.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
    await saveShot(t, 'sabbath_picker');
    await t.tap(find.text('United States').first);
    await t.pumpAndSettle();
    await saveShot(t, 'sabbath_states');
  });

  testWidgets('us_no_state', (t) async {
    await pumpShot(
      t,
      SabbathHoursScreen(now: DateTime(2026, 10, 29, 18)),
      dark: false,
    );
    await t.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
    await saveShot(t, 'sabbath_us_no_state');
  });

  testWidgets('california', (t) async {
    await t.runAsync(
      () => SabbathService.setPlace(
        country: 'US',
        countryName: 'United States',
        region: 'California',
        city: 'Los Angeles',
        lat: 34.05,
        lon: -118.24,
        timeZone: 'America/Los_Angeles',
      ),
    );
    await pumpShot(
      t,
      SabbathHoursScreen(now: DateTime(2026, 10, 29, 18)),
      dark: false,
    );
    await saveShot(t, 'sabbath_california');
  });
}
