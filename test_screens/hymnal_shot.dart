import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/screens/library/hymnal_tab.dart';
import 'package:advent_connect_zw/services/hymn_link_service.dart';
import 'package:advent_connect_zw/services/hymn_service.dart';

import '../test/helpers/fake_supabase.dart';
import 'shot.dart';

void main() {
  setUpAll(() async {
    await loadShotFonts();
    await initFakeSupabase();
  });

  testWidgets('hymnal', (t) async {
    await pumpShot(
      t,
      const Scaffold(body: SafeArea(child: HymnalTab())),
      dark: false,
    );
    await t.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
    await saveShot(t, 'hymnal_shona');
    await t.tap(find.text('English'));
    await saveShot(t, 'hymnal_english');
  });

  testWidgets('hymn_also_in', (t) async {
    // SAMPLE link for the screenshot only — not real data.
    // ignore: invalid_use_of_visible_for_testing_member
    HymnLinkService.debugSet({1: 619});
    final all = await t.runAsync(HymnService.all);
    final h = all!.firstWhere(
      (h) => h.collection == 'kristu_munzwiyo' && h.number == 1,
    );
    await pumpShot(
      t,
      HymnReaderScreen(hymns: [h], initialIndex: 0),
      dark: false,
    );
    await saveShot(t, 'hymn_also_in');
  });
}
