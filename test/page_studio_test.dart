// Page Studio (28 Oct 2026): one screen to manage a Page — numbers added
// up from real updates, a setup checklist, and locked for non-admins.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/screens/pages/page_studio_screen.dart';
import 'package:advent_connect_zw/services/feed_service.dart';
import 'package:advent_connect_zw/services/page_service.dart';
import 'package:advent_connect_zw/theme/app_theme.dart';

import 'helpers/fake_supabase.dart';

Map<String, Object?> _pageRow() => {
  'id': 'pg1',
  'name': 'Harare Pathfinder Club',
  'category': 'ministry',
  'description': 'Youth ministry meeting every Sunday.',
  'city': 'Harare',
  'country': 'ZW',
  'contact_phone': '+263 77 123 4567',
  'is_verified': false,
  'status': 'active',
  'created_at': '2026-10-01T00:00:00Z',
};

Map<String, Object?> _post(String id, String body, int likes, int comments) => {
  'id': id,
  'author_id': 'me',
  'page_id': 'pg1',
  'body': body,
  'created_at': '2026-10-20T10:00:00Z',
  'post_likes': {'count': likes},
  'post_comments': {'count': comments},
};

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pump(WidgetTester t) async {
  t.view.physicalSize = const Size(400, 2200);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: const PageStudioScreen(pageId: 'pg1'),
    ),
  );
  await _settle(t);
}

void main() {
  setUpAll(() async {
    await initFakeSupabase();
    await signInFake('me');
  });

  setUp(() {
    PageService.available = true;
    FeedService.debugResetPagesSchema();
  });

  testWidgets('an owner gets numbers, tools and the setup checklist', (
    t,
  ) async {
    setFakeSupabaseHandler((req) {
      final path = req.url.path;
      if (path.endsWith('/pages')) return [_pageRow()];
      if (path.endsWith('/rpc/page_stats')) {
        return [
          {'followers': 12, 'i_follow': false, 'my_role': 'owner'},
        ];
      }
      if (path.endsWith('/posts')) {
        return [
          _post('p1', 'Camporee this weekend!', 7, 3),
          _post('p2', 'Thank you parents', 2, 1),
        ];
      }
      if (path.endsWith('/rpc/list_page_admins')) {
        return [
          {'user_id': 'me', 'full_name': 'Me', 'role': 'owner'},
        ];
      }
      return null;
    });
    await _pump(t);

    expect(find.text('Page Studio'), findsOneWidget);
    expect(find.text('Owner'), findsOneWidget);
    // Followers from page_stats; reactions/comments summed from updates.
    expect(find.text('12'), findsOneWidget);
    expect(find.text('9'), findsOneWidget); // 7 + 2 reactions
    expect(find.text('4'), findsOneWidget); // 3 + 1 comments
    for (final tool in ['Post update', 'Edit Page', 'Admins', 'Share']) {
      expect(find.text(tool), findsOneWidget);
    }
    // Missing: logo, cover, second admin. Present: about, city, contact,
    // first update.
    expect(find.text('4 of 7 done'), findsOneWidget);
    expect(find.text('Add a logo'), findsOneWidget);
    expect(find.text('Add a second admin'), findsOneWidget);
    // The busiest update is singled out.
    expect(find.text('TOP UPDATE'), findsOneWidget);
    expect(find.text('Camporee this weekend!'), findsNWidgets(2));
    await t.pump(const Duration(seconds: 30));
  });

  testWidgets('a non-admin is told the studio is for admins', (t) async {
    setFakeSupabaseHandler((req) {
      final path = req.url.path;
      if (path.endsWith('/pages')) return [_pageRow()];
      if (path.endsWith('/rpc/page_stats')) {
        return [
          {'followers': 12, 'i_follow': true, 'my_role': null},
        ];
      }
      return null;
    });
    await _pump(t);
    expect(find.textContaining("owners and editors can open"), findsOneWidget);
    expect(find.text('Post update'), findsNothing);
    await t.pump(const Duration(seconds: 30));
  });
}
