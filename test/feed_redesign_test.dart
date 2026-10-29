// Feed redesign, part 2 (29 Oct 2026): post card summary, calm offline
// pill, people cache, QR on any profile.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/models/member_directory_model.dart';
import 'package:advent_connect_zw/models/post_model.dart';
import 'package:advent_connect_zw/services/connectivity_service.dart';
import 'package:advent_connect_zw/theme/app_theme.dart';
import 'package:advent_connect_zw/widgets/friend_qr_sheet.dart';
import 'package:advent_connect_zw/widgets/home/post_card.dart';
import 'package:advent_connect_zw/widgets/offline_banner.dart';

import 'helpers/fake_supabase.dart';

Future<void> _pumpPost(WidgetTester t, Post post) async {
  t.view.physicalSize = const Size(390, 900);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
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
  await t.pump();
}

void main() {
  setUpAll(() async {
    await initFakeSupabase();
    await signInFake('me', metadata: {'full_name': 'Tanatswa Mikuwa'});
  });

  group('post card', () {
    testWidgets('"You and N others" once you have reacted', (t) async {
      await _pumpPost(
        t,
        Post(
          id: 'p1',
          authorId: 'u2',
          authorName: 'Someone',
          createdAt: DateTime(2026, 10, 28),
          body: 'Sabbath greetings',
          likeCount: 12,
          viewerReaction: PostReaction.amen,
        ),
      );
      expect(find.text('You and 11 others'), findsOneWidget);
    });

    testWidgets('just the count when you have not', (t) async {
      await _pumpPost(
        t,
        Post(
          id: 'p2',
          authorId: 'u2',
          authorName: 'Someone',
          createdAt: DateTime(2026, 10, 28),
          body: 'Hello',
          likeCount: 5,
        ),
      );
      expect(find.text('5'), findsOneWidget);
    });

    test('reaction kinds survive the offline cache', () {
      final p = Post.fromJson({
        'id': 'p3',
        'author_id': 'u2',
        'created_at': '2026-10-28T06:00:00Z',
        'body': 'x',
        'post_likes': [
          {'user_id': 'a', 'reaction': 'amen'},
          {'user_id': 'b', 'reaction': 'praying'},
          {'user_id': 'me', 'reaction': 'like'},
        ],
        'post_comments': [],
      }, viewerId: 'me');
      expect(p.reactionKinds, {
        PostReaction.like,
        PostReaction.amen,
        PostReaction.praying,
      });
      final back = Post.fromJson(p.toJson(), viewerId: 'me');
      expect(back.reactionKinds, p.reactionKinds);
      expect(back.likeCount, 3);
      expect(back.viewerReaction, PostReaction.like);
    });
  });

  group('offline pill', () {
    testWidgets('shows briefly when going offline, never a green bar', (
      t,
    ) async {
      await t.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: const OfflineBanner(child: SizedBox.expand()),
        ),
      );
      ConnectivityService.debugEmit(false);
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text("Offline · showing what's saved"), findsOneWidget);
      // Gets out of the way.
      await t.pump(const Duration(seconds: 5));
      final opacity = t.widget<AnimatedOpacity>(find.byType(AnimatedOpacity));
      expect(opacity.opacity, 0);
      // Back online: nothing to announce.
      ConnectivityService.debugEmit(true);
      await t.pump(const Duration(seconds: 1));
      expect(find.text('Back online'), findsNothing);
      final src = File('lib/widgets/offline_banner.dart').readAsStringSync();
      expect(src.contains('successGreen'), isFalse);
    });
  });

  test('suggested people round-trip through the offline cache', () {
    const e = MemberDirectoryEntry(
      id: 'u1',
      userId: 'u1',
      isVisible: true,
      fullName: 'Member One',
      city: 'Harare',
      isVerified: true,
      suggestionReason: '3 mutual friends',
    );
    final back = MemberDirectoryEntry.fromCacheJson(e.toCacheJson());
    expect(back.userId, 'u1');
    expect(back.fullName, 'Member One');
    expect(back.suggestionReason, '3 mutual friends');
    expect(back.isVerified, isTrue);
  });

  testWidgets("another member's QR: their name, share, no scanner", (t) async {
    t.view.physicalSize = const Size(400, 900);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showFriendQrSheet(
                context,
                userId: 'someone-else',
                name: 'Rutendo Moyo',
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(find.text("Rutendo's code"), findsOneWidget);
    expect(find.text('Share code'), findsOneWidget);
    expect(find.text('Scan'), findsNothing);
  });

  test('patch_286 returns counts only, never friend lists', () {
    final sql = File(
      'database/patch_286_mutual_friend_counts.sql',
    ).readAsStringSync();
    expect(
      sql.contains('RETURNS TABLE (user_id UUID, mutual INTEGER)'),
      isTrue,
    );
    expect(sql.contains('blocked_users'), isTrue);
    expect(sql.contains('is_discoverable = TRUE'), isTrue);
  });
}
