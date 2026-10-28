import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/screens/pages/page_details_screen.dart';
import 'package:advent_connect_zw/screens/pages/pages_screen.dart';

import '../test/helpers/fake_supabase.dart';
import 'shot.dart';

final _rows = [
  {
    'id': 'pg1',
    'name': 'Harare Pathfinder Club',
    'category': 'ministry',
    'description':
        'Youth ministry for ages 10–15. Camping, honours and service every '
        'Sunday at Glen View.',
    'city': 'Harare',
    'country': 'ZW',
    'service_area': 'Harare North district',
    'contact_phone': '+263 77 123 4567',
    'website': 'https://pathfinders.example.org',
    'is_verified': true,
    'status': 'active',
    'created_at': '2026-10-01T00:00:00Z',
  },
  {
    'id': 'pg2',
    'name': 'Solusi Adventist High School',
    'category': 'school',
    'city': 'Bulawayo',
    'country': 'ZW',
    'is_verified': false,
    'status': 'active',
  },
  {
    'id': 'pg3',
    'name': 'Grace Health Foods',
    'category': 'business',
    'city': 'Gweru',
    'country': 'ZW',
    'is_verified': false,
    'status': 'active',
  },
];

void main() {
  setUpAll(() async {
    await loadShotFonts();
    await initFakeSupabase();
    final tmp = Directory.systemTemp.createTempSync('shots');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => tmp.path,
        );
    await signInFake('me', metadata: {'full_name': 'Tanatswa Mikuwa'});
    setFakeSupabaseHandler((req) {
      final path = req.url.path;
      if (path.endsWith('/page_admins')) {
        return [
          {'role': 'owner', 'pages': _rows[2]},
        ];
      }
      if (path.endsWith('/pages')) {
        final id = req.url.queryParameters['id'];
        if (id != null) return [_rows.firstWhere((r) => 'eq.${r['id']}' == id)];
        return _rows;
      }
      if (path.endsWith('/rpc/page_stats')) {
        return [
          {'followers': 186, 'i_follow': false, 'my_role': null},
        ];
      }
      if (path.endsWith('/posts')) {
        return [
          {
            'id': 'p1',
            'author_id': 'admin',
            'page_id': 'pg1',
            'body':
                'Camporee registration is open until 15 November. '
                'Bring your honour sashes!',
            'created_at': '2026-10-27T10:00:00Z',
            'visibility': 'public',
            'pages': {
              'id': 'pg1',
              'name': 'Harare Pathfinder Club',
              'is_verified': true,
            },
            'post_likes': [],
            'post_comments': [],
          },
        ];
      }
      return null;
    });
  });

  testWidgets('pages directory', (t) async {
    await pumpShot(t, const PagesScreen());
    await saveShot(t, 'pages');
    await t.pump(const Duration(seconds: 30));
  });

  testWidgets('page details', (t) async {
    await pumpShot(t, const PageDetailsScreen(pageId: 'pg1'));
    await t.pump(const Duration(seconds: 1));
    await saveShot(t, 'page_details');
    await t.pump(const Duration(seconds: 30));
  });

  testWidgets('page details light', (t) async {
    await pumpShot(t, const PageDetailsScreen(pageId: 'pg1'), dark: false);
    await t.pump(const Duration(seconds: 1));
    await saveShot(t, 'page_details_light');
    await t.pump(const Duration(seconds: 30));
  });
}
