import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/models/post_model.dart';
import 'package:advent_connect_zw/widgets/home/post_preview_sheet.dart';

import '../test/helpers/fake_supabase.dart';
import 'shot.dart';

class _Opener extends StatelessWidget {
  const _Opener();
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.transparent,
    body: Center(
      child: TextButton(
        onPressed: () => showPostPreview(
          context,
          body:
              'What a Sabbath! Our youth choir sang "It Is Well" and the '
              'whole church joined in. Thank you to everyone who came out '
              'to support them 🙏',
          photos: const [],
          visibility: PostVisibility.public,
          pageName: 'Harare City Youth Choir',
        ),
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
  });

  for (final dark in [false, true]) {
    testWidgets('preview ${dark ? 'dark' : 'light'}', (t) async {
      await pumpShot(t, const _Opener(), dark: dark);
      await t.tap(find.text('open'));
      await t.runAsync(() => Future<void>.delayed(Duration.zero));
      await t.pump(const Duration(milliseconds: 600));
      await saveShot(t, 'preview_${dark ? 'dark' : 'light'}');
    });
  }
}
