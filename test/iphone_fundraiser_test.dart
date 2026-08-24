// The iPhone fundraiser card and its arithmetic.
//
// The thing worth protecting here is the progress bar. Everything a member
// sees on it is server-computed from CONFIRMED contributions only (see
// database/patch_253_iphone_fundraiser.sql), so these tests cover the two
// halves the client owns: parsing that answer without ever inflating it,
// and rendering the states that must NOT ask anyone for money — dismissed,
// paused, completed, and running on an iPhone.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/models/fundraiser_model.dart';
import 'package:advent_connect_zw/services/fundraiser_service.dart';
import 'package:advent_connect_zw/theme/app_theme.dart';
import 'package:advent_connect_zw/widgets/home/iphone_fundraiser_card.dart';

/// One server row, with overrides. Mirrors the column names and the TEXT
/// shapes `fundraiser_status()` actually returns.
Map<String, dynamic> _row({
  String status = 'active',
  int goal = 9900,
  int raised = 0,
  Object? amounts = '100,300,500,1000',
  bool dismissed = false,
  int supporters = 0,
  int pending = 0,
}) =>
    {
      'campaign_key': 'ios_launch_2026',
      'status': status,
      'goal_cents': goal,
      'raised_cents': raised,
      'remaining_cents': (goal - raised).clamp(0, goal),
      'currency': 'USD',
      'amounts_cents': amounts,
      'supporters': supporters,
      'dismissed': dismissed,
      'my_pending': pending,
      // patch_255/256: the copy is data now, and for a completed campaign
      // the server has ALREADY swapped in the thank-you before it reaches
      // the client. These rows mirror that.
      'title': status == 'completed' ? 'We did it' : 'Help us reach iPhone',
      'body': status == 'completed'
          ? 'Thank you to everyone who helped bring Adventist Super App '
              'closer to iPhone. You made the publishing fee.'
          : 'Adventist Super App is on Android today. We are raising \$99 '
              'for the Apple Developer fee so we can publish it for iPhone '
              'users too.',
    };

FundraiserCampaign _campaign({
  String status = 'active',
  int goal = 9900,
  int raised = 0,
  bool dismissed = false,
  int supporters = 0,
  int pending = 0,
}) =>
    FundraiserCampaign.fromJson(_row(
      status: status,
      goal: goal,
      raised: raised,
      dismissed: dismissed,
      supporters: supporters,
      pending: pending,
    ));

Widget _host(Widget child, {TargetPlatform? platform}) {
  final theme = platform == null
      ? AppTheme.light
      : AppTheme.light.copyWith(platform: platform);
  return MaterialApp(
    theme: theme,
    // A scroll view, because that is what the home feed is: the card
    // is laid out with unbounded height there.
    home: Scaffold(body: SafeArea(child: SingleChildScrollView(child: child))),
  );
}

void main() {
  group('progress arithmetic', () {
    test('nothing raised is 0%', () {
      final c = _campaign(raised: 0);
      expect(c.progress, 0.0);
      expect(c.percent, 0);
      expect(c.raisedLabel, r'$0');
      expect(c.goalLabel, r'$99');
    });

    test('half the goal is about half the bar', () {
      // $50 of $99 — the brief's own worked example.
      final c = _campaign(raised: 5000);
      expect(c.percent, 51);
      expect(c.progress, closeTo(0.505, 0.001));
    });

    test('the full goal is 100%', () {
      final c = _campaign(raised: 9900);
      expect(c.progress, 1.0);
      expect(c.percent, 100);
      expect(c.remainingCents, 0);
    });

    test('overshooting the goal does not paint past the end of the track',
        () {
      // Generosity must not produce a 130%-wide bar overflowing its own
      // ClipRRect.
      final c = _campaign(raised: 12900);
      expect(c.progress, 1.0);
      expect(c.percent, 100);
    });

    test('a goal of zero cannot divide by zero or auto-complete', () {
      // A config typo (fundraiser_goal_cents = 0) reaches the client as
      // goal 0. The server floors it too; this is the second line.
      final c = FundraiserCampaign.fromJson(_row(goal: 0));
      expect(c.goalCents, 9900);
      expect(c.progress, 0.0);
    });

    test('a negative raised total is read as zero, never as a debt', () {
      final c = FundraiserCampaign.fromJson(_row(raised: -500));
      expect(c.raisedCents, 0);
      expect(c.progress, 0.0);
    });
  });

  group('money formatting', () {
    test('whole amounts drop the cents', () {
      final c = _campaign();
      expect(c.formatCents(9900), r'$99');
      expect(c.formatCents(100), r'$1');
      expect(c.formatCents(4200), r'$42');
    });

    test('part-dollar amounts keep two places', () {
      final c = _campaign();
      expect(c.formatCents(250), r'$2.50');
      expect(c.formatCents(105), r'$1.05');
    });

    test('an unknown currency shows the code rather than the wrong symbol',
        () {
      final c = FundraiserCampaign.fromJson(
        {..._row(), 'currency': 'ZWG'},
      );
      expect(c.formatCents(500), 'ZWG 5');
    });
  });

  group('configured amounts', () {
    test('the chips come from the server, in order', () {
      final c = FundraiserCampaign.fromJson(_row());
      expect(c.amountsCents, [100, 300, 500, 1000]);
    });

    test('a different campaign gets different chips with no release', () {
      final c = FundraiserCampaign.fromJson(
        _row(amounts: '200, 1000,5000'),
      );
      expect(c.amountsCents, [200, 1000, 5000]);
    });

    test('a malformed config row still produces usable chips', () {
      // Trailing comma, a word, a negative — none of which may leave the
      // contribution screen with an empty chip row.
      final c = FundraiserCampaign.fromJson(_row(amounts: 'abc,,300,-5,'));
      expect(c.amountsCents, [300]);

      final empty = FundraiserCampaign.fromJson(_row(amounts: ''));
      expect(empty.amountsCents, [100, 300, 500, 1000]);
    });
  });

  group('typed custom amounts', () {
    test('plain dollars', () {
      expect(FundraiserCampaign.parseAmountToCents('5'), 500);
      expect(FundraiserCampaign.parseAmountToCents(' 12 '), 1200);
    });

    test('either decimal separator, because both get typed', () {
      expect(FundraiserCampaign.parseAmountToCents('5.50'), 550);
      expect(FundraiserCampaign.parseAmountToCents('5,50'), 550);
    });

    test('nothing usable returns null rather than zero', () {
      expect(FundraiserCampaign.parseAmountToCents(''), isNull);
      expect(FundraiserCampaign.parseAmountToCents('   '), isNull);
      expect(FundraiserCampaign.parseAmountToCents('abc'), isNull);
      expect(FundraiserCampaign.parseAmountToCents('0'), isNull);
      expect(FundraiserCampaign.parseAmountToCents('0.00'), isNull);
      expect(FundraiserCampaign.parseAmountToCents('..'), isNull);
    });
  });

  group('campaign copy comes from the server', () {
    // The bug this group exists to prevent: patch_255 made the wording
    // data, but the card kept rendering Dart literals. Nothing broke,
    // because the literals happened to match the iPhone campaign — so
    // the mismatch would only have surfaced on campaign #2, in front of
    // members, with the right number and the wrong story.

    test('the heading is whatever the campaign says', () {
      final c = FundraiserCampaign.fromJson({
        ..._row(),
        'title': 'Keep the app running',
        'body': 'We are raising \$50 for next year of hosting.',
      });
      expect(c.title, 'Keep the app running');
      expect(c.body, 'We are raising \$50 for next year of hosting.');
    });

    test('a completed campaign arrives already carrying its thank-you', () {
      // patch_256 swaps the pair server-side, so the client never holds
      // two sets of copy and never decides which one applies.
      final c = _campaign(status: 'completed', raised: 9900);
      expect(c.title, 'We did it');
      expect(c.body, contains('Thank you'));
      expect(c.body, isNot(contains('Apple Developer fee')));
    });

    test('missing copy falls back rather than rendering an empty card', () {
      // An app newer than the database: pre-255 rows have no title/body.
      final row = _row()..remove('title')..remove('body');
      final c = FundraiserCampaign.fromJson(row);
      expect(c.title, 'Help us reach iPhone');
      expect(c.body, contains('Apple Developer fee'));
      expect(c.body, contains(r'$99'));
    });

    test('blank copy is treated as missing, not shown as blank', () {
      final c = FundraiserCampaign.fromJson({
        ..._row(),
        'title': '   ',
        'body': '',
      });
      expect(c.title, 'Help us reach iPhone');
      expect(c.body, isNotEmpty);
    });

    test('the fallback body names the campaign currency, not always USD', () {
      final row = _row()..remove('body');
      row['currency'] = 'ZAR';
      row['goal_cents'] = 15000;
      final c = FundraiserCampaign.fromJson(row);
      expect(c.body, contains('R150'));
    });

    test('copy survives a cache round trip', () {
      // The card paints from the Hive copy on a warm start, so title and
      // body have to be in toJson or the first frame loses them.
      final original = FundraiserCampaign.fromJson({
        ..._row(),
        'title': 'Keep the app running',
        'body': 'Hosting for another year.',
      });
      final restored = FundraiserCampaign.fromJson(original.toJson());
      expect(restored.title, 'Keep the app running');
      expect(restored.body, 'Hosting for another year.');
    });

    test('dismissing does not wipe the copy', () {
      final c = _campaign().copyWith(dismissed: true);
      expect(c.title, isNotEmpty);
      expect(c.body, isNotEmpty);
    });
  });

  group('campaign copy comes from the server', () {
    test('title and body are whatever the campaign row says', () {
      // The point of patch_255: a second campaign must not inherit the
      // iPhone story. Nothing in the Dart may pin this text.
      final c = FundraiserCampaign.fromJson({
        ..._row(),
        'title': 'Keep the app running',
        'body': 'We are raising \$50 for next year of hosting.',
      });
      expect(c.title, 'Keep the app running');
      expect(c.body, 'We are raising \$50 for next year of hosting.');
    });

    test('a completed campaign carries its own thank-you', () {
      // patch_256 swaps the pair server-side, so the client sees the
      // thank-you in the SAME two fields and branches on nothing.
      final c = FundraiserCampaign.fromJson({
        ..._row(status: 'completed', raised: 9900),
        'title': 'Hosting is paid',
        'body': 'Thank you — the server is funded for a year.',
      });
      expect(c.isCompleted, isTrue);
      expect(c.title, 'Hosting is paid');
      expect(c.body, contains('Thank you'));
    });

    test('a database older than the app still renders a complete card', () {
      // Pre-255 fundraiser_status() returns no title/body at all. The card
      // must not show an empty heading.
      final row = _row()
        ..remove('title')
        ..remove('body');
      final c = FundraiserCampaign.fromJson(row);
      expect(c.title, FundraiserCampaign.fallbackTitle);
      expect(c.body, contains('Apple Developer fee'));
      // And the fallback names the real goal, not a baked-in one.
      expect(c.body, contains(r'$99'));
    });

    test('the fallback body follows a changed goal', () {
      final row = _row(goal: 25000)
        ..remove('title')
        ..remove('body');
      final c = FundraiserCampaign.fromJson(row);
      expect(c.body, contains(r'$250'));
      expect(c.body, isNot(contains(r'$99')));
    });

    test('blank server copy falls back rather than rendering nothing', () {
      final c = FundraiserCampaign.fromJson({
        ..._row(),
        'title': '   ',
        'body': '',
      });
      expect(c.title, FundraiserCampaign.fallbackTitle);
      expect(c.body, isNotEmpty);
    });
  });

  group('when the card may appear at all', () {
    test('active shows', () {
      expect(_campaign().canShowCard, isTrue);
    });

    test('dismissed never shows again', () {
      expect(_campaign(dismissed: true).canShowCard, isFalse);
      // Not even once the campaign finishes — a closed card stays closed.
      expect(
        _campaign(status: 'completed', raised: 9900, dismissed: true)
            .canShowCard,
        isFalse,
      );
    });

    test('paused hides the card entirely', () {
      expect(_campaign(status: 'paused').canShowCard, isFalse);
    });

    test('completed still shows — it is the thank-you', () {
      expect(_campaign(status: 'completed', raised: 9900).canShowCard, isTrue);
    });

    test('an unrecognised status falls back to active, not to a crash', () {
      final c = FundraiserCampaign.fromJson({..._row(), 'status': 'wibble'});
      expect(c.state, FundraiserState.active);
      expect(c.canShowCard, isTrue);
    });
  });

  group('the card', () {
    testWidgets('asks in the campaign currency and shows real progress',
        (t) async {
      await t.pumpWidget(_host(FundraiserCardBody(
        campaign: _campaign(raised: 4200, supporters: 6),
        onDismiss: () {},
        onSupport: () {},
      )));
      await t.pumpAndSettle();

      expect(t.takeException(), isNull);
      expect(find.text('Help us reach iPhone'), findsOneWidget);
      // "$42 raised of $99" is one RichText, so match its rendered runs.
      expect(find.textContaining(r'$42', findRichText: true), findsOneWidget);
      expect(find.text('42%'), findsOneWidget);
      expect(find.text('Support the project'), findsOneWidget);
      expect(find.byType(FundraiserProgressBar), findsOneWidget);
    });

    testWidgets('the goal shown is whatever the server said, not a constant',
        (t) async {
      // A $250 campaign must render as $250 with no code change.
      await t.pumpWidget(_host(FundraiserCardBody(
        campaign: _campaign(goal: 25000, raised: 5000),
        onDismiss: () {},
        onSupport: () {},
      )));
      await t.pumpAndSettle();

      expect(find.textContaining(r'$250', findRichText: true), findsWidgets);
      expect(find.text('20%'), findsOneWidget);
    });

    testWidgets('it never covers the screen', (t) async {
      await t.pumpWidget(_host(FundraiserCardBody(
        campaign: _campaign(raised: 4200),
        onDismiss: () {},
        onSupport: () {},
      )));
      await t.pumpAndSettle();

      final card = t.getSize(find.byType(FundraiserCardBody));
      final screen = t.view.physicalSize / t.view.devicePixelRatio;
      // A card, not a takeover. Comfortably under half the viewport.
      expect(card.height, lessThan(screen.height / 2));
    });

    testWidgets('the close control is present and reports the dismissal',
        (t) async {
      var dismissed = 0;
      await t.pumpWidget(_host(FundraiserCardBody(
        campaign: _campaign(raised: 4200),
        onDismiss: () => dismissed++,
        onSupport: () {},
      )));
      await t.pumpAndSettle();

      await t.tap(find.byIcon(Icons.close_rounded));
      await t.pumpAndSettle();
      expect(dismissed, 1);
    });

    testWidgets('Support the project opens the contribution flow', (t) async {
      var supported = 0;
      await t.pumpWidget(_host(FundraiserCardBody(
        campaign: _campaign(raised: 4200),
        onDismiss: () {},
        onSupport: () => supported++,
      )));
      await t.pumpAndSettle();

      await t.tap(find.text('Support the project'));
      await t.pumpAndSettle();
      expect(supported, 1);
    });

    testWidgets('a member with a pledge in review is told so', (t) async {
      await t.pumpWidget(_host(FundraiserCardBody(
        campaign: _campaign(raised: 4200, pending: 1),
        onDismiss: () {},
        onSupport: () {},
      )));
      await t.pumpAndSettle();

      expect(
        find.text('Your contribution is being checked. Thank you.'),
        findsOneWidget,
      );
    });

    testWidgets('a funded campaign stops asking for money', (t) async {
      await t.pumpWidget(_host(FundraiserCardBody(
        campaign: _campaign(status: 'completed', raised: 9900),
        onDismiss: () {},
        onSupport: () {},
      )));
      await t.pumpAndSettle();

      // Rendered from campaign.title, which the server already swapped
      // to the thank-you for a completed campaign.
      expect(find.text('We did it'), findsOneWidget);
      // The whole point of section 10 of the brief.
      expect(find.text('Support the project'), findsNothing);
      expect(find.text('100%'), findsOneWidget);
      // Still closeable.
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    });
  });

  group('the self-hiding wrapper', () {
    setUp(FundraiserService.debugReset);
    tearDown(FundraiserService.debugReset);

    testWidgets('renders nothing before the campaign has loaded', (t) async {
      FundraiserService.debugSet(null);
      await t.pumpWidget(_host(const IphoneFundraiserCard()));
      await t.pump();

      expect(t.takeException(), isNull);
      expect(find.byType(FundraiserCardBody), findsNothing);
      expect(t.getSize(find.byType(IphoneFundraiserCard)).height, 0);
    });

    testWidgets('renders nothing once dismissed', (t) async {
      FundraiserService.debugSet(_campaign(raised: 4200, dismissed: true));
      await t.pumpWidget(_host(const IphoneFundraiserCard()));
      await t.pump();

      expect(find.byType(FundraiserCardBody), findsNothing);
    });

    testWidgets('renders nothing while the campaign is paused', (t) async {
      FundraiserService.debugSet(_campaign(status: 'paused'));
      await t.pumpWidget(_host(const IphoneFundraiserCard()));
      await t.pump();

      expect(find.byType(FundraiserCardBody), findsNothing);
    });

    testWidgets('never asks an iPhone user to fund the iPhone build',
        (t) async {
      FundraiserService.debugSet(_campaign(raised: 4200));
      await t.pumpWidget(_host(
        const IphoneFundraiserCard(),
        platform: TargetPlatform.iOS,
      ));
      await t.pump();

      expect(find.byType(FundraiserCardBody), findsNothing);
    });

    testWidgets('shows on Android when there is a live campaign', (t) async {
      FundraiserService.debugSet(_campaign(raised: 4200));
      await t.pumpWidget(_host(
        const IphoneFundraiserCard(),
        platform: TargetPlatform.android,
      ));
      await t.pumpAndSettle();

      expect(find.byType(FundraiserCardBody), findsOneWidget);
    });
  });
}
