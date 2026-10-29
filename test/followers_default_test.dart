// Personal accounts by default (patch_287, 29 Oct 2026): followers are
// off until the member turns them on, and the app says so plainly.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/models/member_directory_model.dart';
import 'package:advent_connect_zw/models/post_model.dart';
import 'package:advent_connect_zw/services/feed_mixer.dart';
import 'package:advent_connect_zw/services/follow_service.dart';
import 'package:advent_connect_zw/theme/app_theme.dart';
import 'package:advent_connect_zw/widgets/profile/followers_status_card.dart';

Widget _host(Widget child) => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  group('the card', () {
    testWidgets('personal account: explains and offers the switch', (t) async {
      await t.pumpWidget(
        _host(
          FollowersStatusCard(
            current: WhoCanFollow.nobody,
            onChanged: (_) {},
            onDismiss: () {},
          ),
        ),
      );
      expect(find.text('Personal account'), findsOneWidget);
      expect(find.textContaining('adding you as a friend'), findsOneWidget);
      expect(find.text('Allow followers'), findsOneWidget);
      expect(find.text('Not now'), findsOneWidget);
    });

    testWidgets('Home announcement: NEW, Got it', (t) async {
      await t.pumpWidget(
        _host(
          FollowersStatusCard(
            current: WhoCanFollow.nobody,
            announcement: true,
            onChanged: (_) {},
            onDismiss: () {},
          ),
        ),
      );
      expect(find.text('NEW'), findsOneWidget);
      expect(find.text('Your account is personal'), findsOneWidget);
      expect(find.text('Got it'), findsOneWidget);
    });

    testWidgets('followers on: profile says so, Home says nothing', (t) async {
      await t.pumpWidget(
        _host(
          FollowersStatusCard(
            current: WhoCanFollow.everyone,
            onChanged: (_) {},
          ),
        ),
      );
      expect(find.text('Followers on'), findsOneWidget);
      await t.pumpWidget(
        _host(
          FollowersStatusCard(
            current: WhoCanFollow.everyone,
            announcement: true,
            onChanged: (_) {},
          ),
        ),
      );
      expect(find.text('Followers on'), findsNothing);
      expect(find.text('Allow followers'), findsNothing);
    });
  });

  test('a post knows whether its author takes followers', () {
    Post read(String? who) => Post.fromJson({
      'id': 'p',
      'author_id': 'u',
      'created_at': '2026-10-28T06:00:00Z',
      'body': 'x',
      'profiles': {'full_name': 'A', 'who_can_follow': who},
    });
    expect(read('nobody').authorAllowsFollowers, isFalse);
    expect(read(null).authorAllowsFollowers, isFalse);
    expect(read('everyone').authorAllowsFollowers, isTrue);
    // Survives the offline cache.
    final p = read('everyone');
    expect(Post.fromJson(p.toJson()).authorAllowsFollowers, isTrue);
  });

  test('suggestions remember who takes followers, offline too', () {
    const e = MemberDirectoryEntry(
      id: 'u',
      userId: 'u',
      isVisible: true,
      allowsFollowers: true,
    );
    expect(
      MemberDirectoryEntry.fromCacheJson(e.toCacheJson()).allowsFollowers,
      isTrue,
    );
  });

  test('Leaders to follow is its own kind of block', () {
    final out = FeedMixer.mix(
      posts: 0,
      available: {FeedBlockKind.leaders: 2, FeedBlockKind.people: 2},
      postsExhausted: true,
      extraModules: 10,
    );
    expect(out.where((b) => b.kind == FeedBlockKind.leaders).length, 2);
  });

  test('patch_287: default off, and nobody loses followers', () {
    final sql = File(
      'database/patch_287_followers_off_by_default.sql',
    ).readAsStringSync();
    expect(sql.contains("SET DEFAULT 'nobody'"), isTrue);
    expect(sql.contains("WHERE who_can_follow = 'everyone'"), isTrue);
    expect(
      sql.contains('DELETE'),
      isFalse,
      reason: 'turning the default off must not delete anything',
    );
  });
}
