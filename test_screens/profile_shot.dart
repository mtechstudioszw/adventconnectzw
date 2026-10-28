// Render harness, not shipped: seeds PhotoTint like a test does.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:advent_connect_zw/utils/photo_tint.dart';
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
  'profile_photo_url': 'https://x.test/$id.jpg',
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

/// Sample photo URLs can't load in the renderer; don't fail the shot on it.
void _ignoreImageErrors() {
  final orig = FlutterError.onError;
  FlutterError.onError = (d) {
    if (d.library == 'image resource service') return;
    orig?.call(d);
  };
  addTearDown(() => FlutterError.onError = orig);
}

void main() {
  setUpAll(() async {
    await loadShotFonts();
    await initFakeSupabase();
    // The image cache wants a folder; photos still fail to load (no
    // network), which is what the seeded tints stand in for.
    final tmp = Directory.systemTemp.createTempSync('shots');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => tmp.path,
        );
    await signInFake(
      'me',
      metadata: {
        'full_name': 'Tanatswa Michael Mikuwa',
        'date_of_birth': '2008-03-01',
        'bio': 'Building the Adventist Super App for our church family.',
        'profile_photo_url': 'https://x.test/me.jpg',
      },
    );
    // Photos can't load in the renderer; seed what the glow would derive.
    PhotoTint.debugSeed('https://x.test/me.jpg', const Color(0xFF3F7FD6));
    PhotoTint.debugSeed('https://x.test/them.jpg', const Color(0xFFD08A3A));
    setFakeSupabaseHandler((req) {
      final path = req.url.path;
      final single = (req.headers['Accept'] ?? '').contains('vnd.pgrst.object');
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
    _ignoreImageErrors();
    await pumpShot(t, const ProfileScreen());
    await t.pump(const Duration(seconds: 1));
    await saveShot(t, 'profile');
    await t.drag(find.byType(Scrollable).first, const Offset(0, -600));
    await saveShot(t, 'profile_scrolled');
    await t.pump(const Duration(seconds: 30));
  });

  testWidgets('user profile', (t) async {
    _ignoreImageErrors();
    await pumpShot(t, const UserProfileScreen(userId: 'them'));
    await t.pump(const Duration(seconds: 1));
    await saveShot(t, 'user_profile');
  });

  testWidgets('user profile light', (t) async {
    _ignoreImageErrors();
    await pumpShot(t, const UserProfileScreen(userId: 'them'), dark: false);
    await t.pump(const Duration(seconds: 1));
    await saveShot(t, 'user_profile_light');
  });
}
