// Organization Pages (patch_275): the client sends only editable fields,
// feeds survive a database without Pages, and Page posts show as the Page.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/models/org_page_model.dart';
import 'package:advent_connect_zw/models/post_model.dart';
import 'package:advent_connect_zw/screens/pages/page_details_screen.dart';
import 'package:advent_connect_zw/services/feed_service.dart';
import 'package:advent_connect_zw/services/page_service.dart';
import 'package:advent_connect_zw/theme/app_theme.dart';
import 'package:advent_connect_zw/widgets/home/post_card.dart';

import 'helpers/fake_supabase.dart';

Map<String, Object?> _pageRow({bool verified = false}) => {
  'id': 'pg1',
  'name': 'Harare Pathfinder Club',
  'category': 'ministry',
  'description': 'Youth ministry meeting every Sunday.',
  'city': 'Harare',
  'country': 'ZW',
  'contact_phone': '+263 77 123 4567',
  'is_verified': verified,
  'status': 'active',
  'created_at': '2026-10-01T00:00:00Z',
};

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await t.pump(const Duration(milliseconds: 100));
  }
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

  test('create never sends verification, status or ownership', () async {
    Map<String, dynamic>? sent;
    setFakeSupabaseHandler((req) {
      if (req.method == 'POST' && req.url.path.endsWith('/pages')) {
        sent = jsonDecode(req.body) as Map<String, dynamic>;
        return _pageRow();
      }
      return null;
    });
    final page = await PageService.create(
      const OrgPage(
        id: '',
        name: ' Harare Pathfinder Club ',
        category: PageCategory.ministry,
        isVerified: true,
      ),
    );
    expect(page.id, 'pg1');
    expect(sent!['name'], 'Harare Pathfinder Club');
    expect(sent!['category'], 'ministry');
    expect(sent!.containsKey('is_verified'), isFalse);
    expect(sent!.containsKey('status'), isFalse);
    expect(sent!['created_by'], 'me');
  });

  test('update throws when nothing changed (not an editor)', () async {
    setFakeSupabaseHandler((_) => <Object>[]);
    expect(
      () => PageService.update(
        const OrgPage(id: 'pg1', name: 'X Y', category: PageCategory.school),
      ),
      throwsStateError,
    );
  });

  test('server refusals become plain sentences', () {
    expect(
      PageService.messageFor(Exception('PAGE_LIMIT')),
      'You can create up to 3 Pages.',
    );
    expect(
      PageService.messageFor(Exception('LAST_OWNER')),
      contains('at least one owner'),
    );
  });

  test(
    'feed keeps working before patch_275 (falls back without Pages)',
    () async {
      final selects = <String>[];
      setFakeSupabaseHandler((req) {
        if (!req.url.path.endsWith('/posts')) return null;
        final sel = req.url.queryParameters['select'] ?? '';
        selects.add(sel);
        if (sel.contains('pages(')) {
          return const FakeError(400, {
            'code': 'PGRST200',
            'message':
                "Could not find a relationship between 'posts' and 'pages' "
                'in the schema cache',
          });
        }
        return [
          {
            'id': 'p1',
            'author_id': 'u1',
            'body': 'Hello',
            'created_at': '2026-10-28T10:00:00Z',
            'visibility': 'public',
          },
        ];
      });
      final posts = await FeedService.fetchPostsByAuthor('u1');
      expect(posts.single.id, 'p1');
      expect(selects, hasLength(2));
      // Remembered for the session: the next read goes straight to the old
      // columns.
      await FeedService.fetchPostsByAuthor('u1');
      expect(selects, hasLength(3));
      expect(selects.last.contains('pages('), isFalse);
    },
  );

  testWidgets('a Page post shows the Page, not the admin who wrote it', (
    t,
  ) async {
    setFakeSupabaseHandler((_) => null);
    final post = Post.fromJson({
      'id': 'p2',
      'author_id': 'admin1',
      'body': 'Camp registration is open',
      'created_at': '2026-10-28T10:00:00Z',
      'page_id': 'pg1',
      'profiles': {'full_name': 'Admin Person', 'is_verified_admin': true},
      'pages': {'id': 'pg1', 'name': 'Harare Pathfinder Club'},
    });
    expect(post.isPagePost, isTrue);
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            child: PostCard(
              post: post,
              viewerId: 'me',
              onLikeToggled: () {},
              onCommentsTapped: () {},
              onImageTapped: (_) {},
            ),
          ),
        ),
      ),
    );
    expect(find.text('Harare Pathfinder Club'), findsOneWidget);
    expect(find.text('Admin Person'), findsNothing);
    // The admin's own tick doesn't carry over to an unverified Page.
    expect(find.byIcon(Icons.verified), findsNothing);
  });

  testWidgets('visitor sees Follow and Contact; Follow writes a follow', (
    t,
  ) async {
    final writes = <String>[];
    setFakeSupabaseHandler((req) {
      final path = req.url.path;
      if (path.endsWith('/pages')) return [_pageRow()];
      if (path.endsWith('/rpc/page_stats')) {
        return [
          {'followers': 4, 'i_follow': false, 'my_role': null},
        ];
      }
      if (req.method == 'POST' && path.endsWith('/page_follows')) {
        writes.add(req.body);
      }
      return null;
    });
    t.view.physicalSize = const Size(390, 1100);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const PageDetailsScreen(pageId: 'pg1'),
      ),
    );
    await _settle(t);
    expect(find.text('Harare Pathfinder Club'), findsWidgets);
    expect(find.text('Ministry'), findsWidgets);
    expect(find.text('Contact'), findsOneWidget);
    expect(find.text('Post update'), findsNothing);
    await t.tap(find.text('Follow'));
    await _settle(t);
    expect(writes, hasLength(1));
    expect(find.text('Following'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    await t.pump(const Duration(seconds: 30));
  });

  testWidgets('an admin sees Post update and Edit instead of Follow', (
    t,
  ) async {
    setFakeSupabaseHandler((req) {
      final path = req.url.path;
      if (path.endsWith('/pages')) return [_pageRow(verified: true)];
      if (path.endsWith('/rpc/page_stats')) {
        return [
          {'followers': 12, 'i_follow': false, 'my_role': 'owner'},
        ];
      }
      return null;
    });
    t.view.physicalSize = const Size(390, 1100);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const PageDetailsScreen(pageId: 'pg1'),
      ),
    );
    await _settle(t);
    expect(find.text('Post update'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Follow'), findsNothing);
    await t.pump(const Duration(seconds: 30));
  });
}
