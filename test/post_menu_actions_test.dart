// The redesign brief asks for Save (a real private collection, not a local
// icon flip), Copy link and Hide post on every post's ⋯ menu.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/models/post_model.dart';
import 'package:advent_connect_zw/services/feed_service.dart';
import 'package:advent_connect_zw/theme/app_theme.dart';
import 'package:advent_connect_zw/widgets/home/post_card.dart';

import 'helpers/fake_supabase.dart';

Post _post(String author) => Post(
  id: 'p9',
  authorId: author,
  authorName: 'Someone',
  createdAt: DateTime(2026, 10, 28),
  body: 'Sabbath greetings',
);

Future<void> _pump(WidgetTester t, Post post) async {
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
            onReport: () {},
          ),
        ),
      ),
    ),
  );
  await t.pump();
}

Future<void> _choose(WidgetTester t, String label) async {
  await t.tap(find.byIcon(Icons.more_horiz));
  await t.pumpAndSettle();
  await t.tap(find.text(label));
  for (var i = 0; i < 4; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  final writes = <String>[];

  setUpAll(() async {
    await initFakeSupabase();
    await signInFake('me');
  });

  setUp(() {
    writes.clear();
    FeedService.savedPostIds.value = {};
    FeedService.hiddenPostIds.value = {};
    setFakeSupabaseHandler((req) {
      if (req.method == 'POST' || req.method == 'DELETE') {
        final table = req.url.pathSegments.last;
        final body = req.body.isEmpty ? '' : jsonDecode(req.body).toString();
        writes.add('${req.method} $table $body');
      }
      return null;
    });
  });

  testWidgets('Save writes to the private collection, then Unsave removes', (
    t,
  ) async {
    await _pump(t, _post('someone'));
    await _choose(t, 'Save post');
    expect(writes.single, startsWith('POST saved_posts'));
    expect(FeedService.savedPostIds.value, contains('p9'));
    expect(find.textContaining('Saved.'), findsOneWidget);

    await _choose(t, 'Remove from Saved');
    expect(writes.last, startsWith('DELETE saved_posts'));
    expect(FeedService.savedPostIds.value, isNot(contains('p9')));
  });

  testWidgets("Hide is on other people's posts and records it", (t) async {
    await _pump(t, _post('someone'));
    await _choose(t, 'Hide post');
    expect(writes.single, startsWith('POST hidden_posts'));
    expect(FeedService.hiddenPostIds.value, contains('p9'));
    expect(find.text('Undo'), findsOneWidget);
  });

  testWidgets('your own post has no Hide, but has Save and Copy link', (
    t,
  ) async {
    await _pump(t, _post('me'));
    await t.tap(find.byIcon(Icons.more_horiz));
    await t.pumpAndSettle();
    expect(find.text('Hide post'), findsNothing);
    expect(find.text('Report post'), findsNothing);
    expect(find.text('Save post'), findsOneWidget);
    expect(find.text('Copy link'), findsOneWidget);
  });

  testWidgets('Copy link puts the post link on the clipboard', (t) async {
    String? copied;
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    await _pump(t, _post('someone'));
    await _choose(t, 'Copy link');
    expect(copied, contains('p9'));
    expect(find.text('Link copied.'), findsOneWidget);
  });
}
