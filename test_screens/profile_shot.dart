import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/screens/profile/profile_screen.dart';
import 'package:advent_connect_zw/screens/users/user_profile_screen.dart';

import '../test/helpers/fake_supabase.dart';
import 'shot.dart';

Map<String, Object?> _row(String id) => {
  'id': id,
  'full_name': id == 'me' ? 'Tanatswa Michael Mikuwa' : 'Rudo Moyo',
  'username': id == 'me' ? 'tanatswa' : 'rudo.moyo',
  'bio': id == 'me'
      ? null
      : 'Pathfinder leader. Singing in the Glen View choir.',
  'city': 'Harare',
  'country': 'ZW',
  'website': id == 'me' ? 'https://adventconnect.app' : null,
  'is_private': false,
  'is_discoverable': true,
  'is_verified': id != 'me',
  'is_super_admin': true,
  'is_verified_admin': id == 'me',
  'created_at': '2025-02-01T00:00:00Z',
  'churches': {'name': 'Glen View SDA Church'},
};

void main() {
  setUpAll(() async {
    await loadShotFonts();
    await initFakeSupabase();
    await signInFake('me', metadata: {
      'full_name': 'Tanatswa Michael Mikuwa',
      'date_of_birth': '2008-03-01',
      'bio': 'Building the Adventist Super App for our church family.',
    });
    setFakeSupabaseHandler((req) {
      final path = req.url.path;
      final single =
          (req.headers['Accept'] ?? '').contains('vnd.pgrst.object');
      if (path.endsWith('/rpc/profile_follow_stats')) {
        return [
          {
            'followers': 248,
            'following': 31,
            'i_follow': null,
            'follows_me': true,
          },
        ];
      }
      if (path.endsWith('/posts')) {
        final author = req.url.queryParameters['author_id'] ?? 'eq.me';
        return [
          {
            'id': 'p1',
            'author_id': author.substring(3),
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
        final id = (req.url.queryParameters['id'] ?? 'eq.me').substring(3);
        return single ? _row(id) : [_row(id)];
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

  testWidgets('user profile', (t) async {
    await pumpShot(t, const UserProfileScreen(userId: 'them'));
    await saveShot(t, 'user_profile');
  });
}
