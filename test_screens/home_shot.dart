import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/screens/home/home_screen.dart';

import '../test/helpers/fake_supabase.dart';
import 'shot.dart';

void main() {
  setUpAll(() async {
    await loadShotFonts();
    await initFakeSupabase();
    await signInFake('me', metadata: {'full_name': 'Tanatswa Michael Mikuwa'});
    setFakeSupabaseHandler((req) {
      final path = req.url.path;
      if (path.endsWith('/rpc/todays_devotion')) {
        return {
          'id': 1,
          'bible_ref': 'Hebrews 10:36',
          'bible_text':
              'For ye have need of patience, that, after ye have '
              'done the will of God, ye might receive the promise.',
          'egw_quote': 'Patience is faith holding on when it cannot see.',
          'egw_source': 'Testimonies for the Church',
          'devotion_date': '2026-10-28',
        };
      }
      if (path.endsWith('/posts')) {
        return [
          {
            'id': 'p1',
            'author_id': 'u2',
            'body': 'Good Morning',
            'created_at': '2026-10-27T06:00:00Z',
            'visibility': 'public',
            'profiles': {'full_name': 'The Word Unveiled'},
            'post_likes': [],
            'post_comments': [],
          },
        ];
      }
      return null;
    });
  });

  testWidgets('home', (t) async {
    await pumpShot(t, const HomeScreen());
    await saveShot(t, 'home', rounds: 12);
    await t.drag(find.byType(Scrollable).first, const Offset(0, -700));
    await saveShot(t, 'home_scrolled');
  });
}
