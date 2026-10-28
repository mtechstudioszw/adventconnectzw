import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/screens/profile/profile_screen.dart';

import '../test/helpers/fake_supabase.dart';
import 'shot.dart';

void main() {
  setUpAll(() async {
    await loadShotFonts();
    await initFakeSupabase();
    await signInFake('me', metadata: {
      'full_name': 'Tanatswa Michael Mikuwa',
      'date_of_birth': '2008-03-01',
    });
    setFakeSupabaseHandler((req) {
      final path = req.url.path;
      if (path.endsWith('/posts')) {
        return [
          {
            'id': 'p1',
            'author_id': 'me',
            'body': '#one voice 27\n\nAdventist Super App',
            'created_at': '2026-09-28T10:00:00Z',
            'visibility': 'public',
            'profiles': {'full_name': 'Adventist Super App Team'},
            'post_likes': [],
            'post_comments': [],
          },
        ];
      }
      if (path.endsWith('/profiles')) {
        return [
          {'is_super_admin': true, 'is_verified_admin': true},
        ];
      }
      return null;
    });
  });

  testWidgets('profile', (t) async {
    await pumpShot(t, const ProfileScreen());
    await saveShot(t, 'profile');
    await t.drag(find.byType(Scrollable).first, const Offset(0, -600));
    await saveShot(t, 'profile_scrolled');
  });
}
