// Founder, 28 Oct 2026: a member whose listing or post is hidden must be
// told why and be able to appeal by email or WhatsApp; admins can hide a
// single post.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/models/post_model.dart';
import 'package:advent_connect_zw/theme/app_theme.dart';
import 'package:advent_connect_zw/widgets/home/post_card.dart';
import 'package:advent_connect_zw/widgets/moderation_appeal_sheet.dart';

Post _post({DateTime? hiddenAt, String author = 'author-1'}) => Post(
  id: 'p1',
  authorId: author,
  authorName: 'Tanatswa',
  createdAt: DateTime(2026, 10, 28),
  body: 'Good morning',
  moderationHiddenAt: hiddenAt,
  moderationReason: hiddenAt == null ? null : 'Spam.',
);

Future<void> _pumpCard(
  WidgetTester t,
  Post post, {
  required String viewer,
  VoidCallback? onAdminModerate,
}) async {
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
            viewerId: viewer,
            onLikeToggled: () {},
            onCommentsTapped: () {},
            onImageTapped: (_) {},
            onReport: () {},
            onAdminModerate: onAdminModerate,
          ),
        ),
      ),
    ),
  );
  await t.pump(const Duration(seconds: 1));
}

void main() {
  test('the appeal names the item, links it and quotes the reason', () {
    final msg = appealMessage(
      kind: ModeratedKind.listing,
      itemId: '43',
      title: 'SUGAR DIABETES KIT',
      reason: 'It claims to treat a medical condition.',
    );
    expect(msg, contains('my listing was hidden'));
    expect(msg, contains('Listing: SUGAR DIABETES KIT'));
    expect(msg, contains('product-share?id=43'));
    expect(msg, contains('Reason given: It claims to treat'));
  });

  test('the notice text written by patch_272 parses back', () {
    final listing = parseModerationNotice(
      '"SUGAR DIABETES KIT" was hidden by the moderators. It claims to treat '
      'a medical condition. If you believe this is a mistake, tap to appeal.',
    );
    expect(listing.title, 'SUGAR DIABETES KIT');
    expect(listing.reason, 'It claims to treat a medical condition.');

    final post = parseModerationNotice(
      'Your post "Buy my coins" was hidden by the moderators. Spam. '
      'If you believe this is a mistake, tap to appeal.',
    );
    expect(post.title, 'Buy my coins');
    expect(post.reason, 'Spam.');

    final odd = parseModerationNotice('Something else entirely');
    expect(odd.title, isNull);
    expect(odd.reason, isNull);
  });

  testWidgets('the author of a hidden post sees why, with Appeal', (t) async {
    await _pumpCard(
      t,
      _post(hiddenAt: DateTime(2026, 10, 28)),
      viewer: 'author-1',
    );
    expect(find.textContaining('Only you can see this post'), findsOneWidget);
    expect(find.text('Appeal'), findsOneWidget);
  });

  testWidgets('a visible post has no banner', (t) async {
    await _pumpCard(t, _post(), viewer: 'someone-else');
    expect(find.textContaining('Hidden by the moderators'), findsNothing);
  });

  testWidgets('admins get Hide in the menu; others do not', (t) async {
    var moderated = 0;
    await _pumpCard(
      t,
      _post(),
      viewer: 'admin-1',
      onAdminModerate: () => moderated++,
    );
    await t.tap(find.byIcon(Icons.more_horiz));
    await t.pumpAndSettle();
    await t.tap(find.text('Hide post (admin)'));
    await t.pumpAndSettle();
    expect(moderated, 1);

    await _pumpCard(t, _post(), viewer: 'member-1');
    await t.tap(find.byIcon(Icons.more_horiz));
    await t.pumpAndSettle();
    expect(find.text('Hide post (admin)'), findsNothing);
    expect(find.text('Report post'), findsOneWidget);
  });

  testWidgets('an admin sees a hidden post as hidden, with Restore', (t) async {
    await _pumpCard(
      t,
      _post(hiddenAt: DateTime(2026, 10, 28)),
      viewer: 'admin-1',
      onAdminModerate: () {},
    );
    expect(find.textContaining('Members cannot see this post'), findsOneWidget);
    expect(find.text('Appeal'), findsNothing);
    await t.tap(find.byIcon(Icons.more_horiz));
    await t.pumpAndSettle();
    expect(find.text('Restore post (admin)'), findsOneWidget);
  });
}
