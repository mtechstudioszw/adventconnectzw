// Tapping Reply under a reply answered the TOP comment instead, so two
// people could never go back and forth and the person replied to was never
// notified. Reply now answers the comment you tapped.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/theme/app_theme.dart';
import 'package:advent_connect_zw/widgets/home/comments_sheet.dart';

import 'helpers/fake_supabase.dart';

Map<String, Object?> _c(
  String id,
  String author,
  String body, {
  String? parent,
  String time = '10:00',
}) => {
  'id': id,
  'post_id': 'p1',
  'author_id': author,
  'body': body,
  'parent_comment_id': parent,
  'created_at': '2026-10-28T$time:00Z',
  'profiles': {'full_name': author},
  'post_comment_reactions': [],
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
  Map<String, dynamic>? sent;

  setUpAll(() async {
    await initFakeSupabase();
    await signInFake('Chipo');
    setFakeSupabaseHandler((req) {
      if (!req.url.path.endsWith('/post_comments')) return null;
      if (req.method == 'POST') {
        sent = jsonDecode(req.body) as Map<String, dynamic>;
        return _c(
          'c3',
          'Chipo',
          sent!['body'] as String,
          parent: sent!['parent_comment_id'] as String?,
          time: '10:05',
        );
      }
      return [
        _c('c1', 'Tendai', 'Who is going to camp meeting?'),
        _c('c2', 'Rudo', 'We are!', parent: 'c1', time: '10:02'),
      ];
    });
  });

  testWidgets('Reply under a reply answers that reply and names it', (t) async {
    t.view.physicalSize = const Size(390, 900);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showCommentsSheet(
                context,
                postId: 'p1',
                onCommentCountChanged: (_) {},
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await _settle(t);

    // Second "Reply" link belongs to Rudo's reply.
    await t.tap(find.text('Reply').at(1));
    await t.pump();
    expect(find.text('Replying to Rudo'), findsOneWidget);

    await t.enterText(find.byType(TextField), 'See you there');
    await t.pump();
    await t.tap(find.byIcon(Icons.send));
    await _settle(t);

    expect(sent, isNotNull);
    expect(sent!['parent_comment_id'], 'c2');
    // The new reply shows who it answers.
    expect(find.text('Rudo'), findsWidgets);
    expect(find.text('See you there'), findsOneWidget);
  });
}
