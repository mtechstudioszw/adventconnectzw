import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/screens/library/hymnal_tab.dart';

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
}
