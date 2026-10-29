// Redesigned profile header (brief §7) + followers (§8): real numbers only,
// handle only when set, Follow/Unfollow from the post menu, and requests
// that can actually be approved.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/models/post_model.dart';
import 'package:advent_connect_zw/screens/profile/follow_list_screen.dart';
import 'package:advent_connect_zw/services/feed_service.dart';
import 'package:advent_connect_zw/services/follow_service.dart';
import 'package:advent_connect_zw/theme/app_theme.dart';
import 'package:advent_connect_zw/widgets/home/post_card.dart';
import 'package:advent_connect_zw/widgets/profile/profile_header.dart';

import 'helpers/fake_supabase.dart';

Future<void> _pump(WidgetTester t, Widget child) async {
  t.view.physicalSize = const Size(390, 1000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
  await t.pump();
}

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 5; i++) {
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

  group('ProfileHeader', () {
    testWidgets('leaves out unavailable stats instead of showing 0', (t) async {
      await _pump(
        t,
        ProfileHeader(
          name: 'Rudo Moyo',
          initials: 'RM',
          stats: const [
            ProfileStat('Posts', 4),
            ProfileStat('Followers', null),
            ProfileStat('Following', null),
            ProfileStat('Friends', 1200),
          ],
          actions: [ProfileActionButton(label: 'Edit profile', onTap: () {})],
        ),
      );
      expect(find.text('Posts'), findsOneWidget);
      expect(find.text('Followers'), findsNothing);
      expect(find.text('1.2K'), findsOneWidget);
      // No username set → no "@".
      expect(find.textContaining('@'), findsNothing);
      // No overflow or layout error at phone width.
      expect(t.takeException(), isNull);
    });

    testWidgets('shows handle, bio, facts and relation note', (t) async {
      var linkTapped = false;
      await _pump(
        t,
        ProfileHeader(
          name: 'Rudo Moyo',
          initials: 'RM',
          username: 'rudo',
          bio: 'Pathfinder leader',
          relationNote: 'Follows you',
          facts: [
            const ProfileFact(Icons.church_outlined, 'Glen View SDA'),
            ProfileFact(
              Icons.link_rounded,
              websiteLabel('https://www.rudo.org/'),
              onTap: () => linkTapped = true,
            ),
          ],
          stats: const [ProfileStat('Followers', 7)],
          actions: [
            ProfileActionButton(label: 'Follow', primary: true, onTap: () {}),
          ],
        ),
      );
      expect(find.text('@rudo'), findsOneWidget);
      expect(find.text('Pathfinder leader'), findsOneWidget);
      expect(find.text('Follows you'), findsOneWidget);
      expect(find.text('rudo.org'), findsOneWidget);
      await t.tap(find.text('rudo.org'));
      expect(linkTapped, isTrue);
    });
  });

  group('post menu', () {
    // Tendai turned followers on (patch_287): the menu only offers Follow
    // for authors who take followers.
    Post post({bool allowsFollowers = true}) => Post(
      id: 'p1',
      authorId: 'them',
      authorName: 'Tendai Moyo',
      createdAt: DateTime(2026, 10, 28),
      body: 'Hello',
      authorAllowsFollowers: allowsFollowers,
    );

    Widget card({bool allowsFollowers = true}) => PostCard(
      post: post(allowsFollowers: allowsFollowers),
      viewerId: 'me',
      onLikeToggled: () {},
      onCommentsTapped: () {},
      onImageTapped: (_) {},
      onReport: () {},
    );

    setUp(() {
      FeedService.savedPostIds.value = {};
      FollowService.available = true;
    });

    testWidgets('no Follow item until the follow list is known', (t) async {
      FollowService.followingIds.value = null;
      setFakeSupabaseHandler((_) => null);
      await _pump(t, card());
      await t.tap(find.byIcon(Icons.more_horiz));
      await t.pumpAndSettle();
      expect(find.textContaining('Follow'), findsNothing);
    });

    testWidgets('a personal account: no Follow in the menu', (t) async {
      FollowService.followingIds.value = <String>{};
      setFakeSupabaseHandler((_) => null);
      await _pump(t, card(allowsFollowers: false));
      await t.tap(find.byIcon(Icons.more_horiz));
      await t.pumpAndSettle();
      expect(find.textContaining('Follow'), findsNothing);
    });

    testWidgets('Unfollow from the post menu deletes the follow', (t) async {
      FollowService.followingIds.value = {'them'};
      setFakeSupabaseHandler((_) => null);
      await _pump(t, card());
      await t.tap(find.byIcon(Icons.more_horiz));
      await t.pumpAndSettle();
      await t.tap(find.text('Unfollow Tendai'));
      await _settle(t);
      expect(
        fakeSupabaseRequests.where(
          (r) => r.method == 'DELETE' && r.url.path.endsWith('/follows'),
        ),
        hasLength(1),
      );
      expect(FollowService.followingIds.value, isEmpty);
      expect(find.text('Unfollowed Tendai.'), findsOneWidget);
    });

    testWidgets('Follow on a private account says a request was sent', (
      t,
    ) async {
      FollowService.followingIds.value = <String>{};
      setFakeSupabaseHandler((req) {
        if (req.method == 'POST') return {'status': 'pending'};
        return null;
      });
      await _pump(t, card());
      await t.tap(find.byIcon(Icons.more_horiz));
      await t.pumpAndSettle();
      await t.tap(find.text('Follow Tendai'));
      await _settle(t);
      expect(find.text('Follow request sent to Tendai.'), findsOneWidget);
    });
  });

  testWidgets('Requests: Approve updates the row and removes it', (t) async {
    final updates = <String>[];
    setFakeSupabaseHandler((req) {
      if (req.url.path.endsWith('/rpc/my_follow_requests')) {
        return [
          {'user_id': 'u2', 'full_name': 'Chipo Dube', 'username': 'chipo'},
        ];
      }
      if (req.method == 'PATCH') {
        updates.add(req.url.query);
        return [
          {'follower_id': 'u2'},
        ];
      }
      return null;
    });
    t.view.physicalSize = const Size(390, 900);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const FollowListScreen.requests(),
      ),
    );
    await _settle(t);
    expect(find.text('Chipo Dube'), findsOneWidget);
    await t.tap(find.text('Approve'));
    await _settle(t);
    expect(updates.single, contains('follower_id=eq.u2'));
    expect(find.text('Chipo Dube'), findsNothing);
    expect(find.text('No requests'), findsOneWidget);
  });
}
