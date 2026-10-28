import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/models/devotion_model.dart';
import 'package:advent_connect_zw/services/devotion_service.dart';
import 'package:advent_connect_zw/widgets/home/create_sheet.dart';

import '../test/helpers/fake_supabase.dart';
import 'shot.dart';

class _Opener extends StatelessWidget {
  const _Opener();
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.transparent,
    body: Center(
      child: TextButton(
        onPressed: () => showCreateSheet(context),
        child: const Text('open'),
      ),
    ),
  );
}

void main() {
  setUpAll(() async {
    await loadShotFonts();
    await initFakeSupabase((_) => const <Object>[]);
    await signInFake('me');
    // So the "Today's verse" tool shows, as it does once Home has loaded.
    DevotionService.current.value = const Devotion(
      bibleRef: 'Psalm 46:10',
      bibleText: 'Be still, and know that I am God.',
      egwQuote: '',
      egwSource: '',
    );
  });

  for (final dark in [false, true]) {
    testWidgets('create ${dark ? 'dark' : 'light'}', (t) async {
      await pumpShot(t, const _Opener(), dark: dark);
      await t.tap(find.text('open'));
      await saveShot(t, 'create_${dark ? 'dark' : 'light'}');
    });
  }
}
