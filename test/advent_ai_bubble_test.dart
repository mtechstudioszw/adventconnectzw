// Founder rule, 23 Aug 2026: **the Advent AI bubble never appears inside
// a conversation.**
//
// The founder's words when they asked for it: a bubble everywhere,
// "except inside conversations people will feel we spying on them".
// That is a judgement about how it FEELS, and it is right — a member
// cannot inspect an architecture, they can only see what is floating on
// top of their private chat.
//
// The architecture backs it up (the bubble sends no screen content, and
// Advent AI has no tool that can read a message), but the visible rule
// is the one that earns trust, so it is pinned here rather than left to
// whoever next edits the blocklist.
//
// This is the same shape of test as `ads_never_in_chat_test.dart`, which
// guards the matching rule for advertising.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/widgets/advent_ai_bubble.dart';

/// Everything under here is Advent Chat: the inbox, conversations,
/// groups, message requests, starred messages, chat privacy and the
/// image preview.
const _messagingDir = 'lib/screens/messaging';

/// The inbox is exempt, and only the inbox.
///
/// On 25 Aug 2026 the founder asked for an Advent AI button in the chat
/// tab, above the compose button. That is not the thing this file
/// forbids: the rule is about a control floating over an open
/// conversation, and the inbox is a list of who you talk to. The button
/// there is stationary, it is part of the screen rather than on a layer
/// above it, and it is gone the moment a chat opens.
///
/// The floating bubble is still refused on every `/messages` route —
/// that is asserted below and does not move.
const _inboxFile = 'conversations_screen.dart';

void main() {
  group('Advent AI bubble — messaging', () {
    test('/messages is on the blocklist', () {
      expect(AdventAiBubble.blockedPrefixes, contains('/messages'));
    });

    test('every messaging route is refused', () {
      // Prefix matching must cover the children, not just the tab root.
      // A conversation is `/messages/<id>`, and that is precisely the
      // screen the rule exists for.
      for (final route in const [
        '/messages',
        '/messages/42',
        '/messages/new-chat',
        '/messages/new-group',
        '/messages/requests',
        '/messages/starred',
        '/messages/privacy',
      ]) {
        expect(
          AdventAiBubble.allowedOn(route),
          isFalse,
          reason: 'the bubble must never float over $route — founder rule',
        );
      }
    });

    test('no messaging screen mounts the floating bubble', () {
      // The blocklist governs the app-wide layer. A messaging screen
      // that mounted the bubble itself would bypass it entirely, and
      // nothing else would catch that.
      //
      // This is about `AdventAiBubble` specifically — the draggable
      // thing on the overlay. The inbox's own stationary button uses
      // `AdventAiMark`, which is a different widget in a different
      // layer; see _inboxFile.
      final dir = Directory(_messagingDir);
      expect(dir.existsSync(), isTrue,
          reason: 'test must be run from the package root');

      final offenders = <String>[];
      for (final file in dir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final source = file.readAsStringSync();
        if (source.contains('AdventAiBubble') ||
            source.contains('advent_ai_bubble')) {
          offenders.add(file.path);
        }
      }

      expect(offenders, isEmpty,
          reason: 'Advent Chat must carry no floating AI bubble — '
              'founder rule');
    });

    test('no CONVERSATION screen carries an Advent AI entry point', () {
      // The inbox is allowed one (see _inboxFile). Everything else under
      // messaging is a conversation or something opened from inside one,
      // and the rule holds there without exception: the open chat is the
      // surface the founder was talking about.
      final dir = Directory(_messagingDir);
      final offenders = <String>[];
      for (final file in dir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        if (file.path.endsWith(_inboxFile)) continue;
        final source = file.readAsStringSync();
        if (source.contains('AdventAi') ||
            source.contains('advent_ai') ||
            source.contains('/advent-ai')) {
          offenders.add(file.path);
        }
      }

      expect(offenders, isEmpty,
          reason: 'only the inbox may offer Advent AI — a conversation '
              'must not');
    });

    test('the inbox offers Advent AI, and does it without the bubble', () {
      // The positive half. The founder asked for this button by name on
      // 25 Aug 2026; a later tidy-up that removed it would otherwise
      // look like a cleanup rather than a regression.
      final source = File('$_messagingDir/$_inboxFile').readAsStringSync();
      expect(source.contains('/advent-ai'), isTrue,
          reason: 'the chat tab must offer Advent AI above the compose '
              'button — founder request, 25 Aug 2026');
      expect(source.contains('AdventAiBubble'), isFalse,
          reason: 'it must be a stationary button, not the floating '
              'bubble');
    });
  });

  group('Advent AI bubble — other blocked surfaces', () {
    test('pre-auth screens are refused', () {
      // There is no member to bill, authenticate or answer here, so the
      // bubble would open a screen that immediately bounces.
      for (final route in const [
        '/splash',
        '/login',
        '/signup',
        '/onboarding',
        '/biometric-lock',
        '/profile-setup',
        '/forgot-password',
        '/reset-password',
        '/email-verification',
      ]) {
        expect(AdventAiBubble.allowedOn(route), isFalse, reason: route);
      }
    });

    test('app-replacement screens are refused', () {
      for (final route in const [
        '/maintenance',
        '/account-banned',
        '/update-required',
      ]) {
        expect(AdventAiBubble.allowedOn(route), isFalse, reason: route);
      }
    });

    test('it does not float over itself', () {
      expect(AdventAiBubble.allowedOn('/advent-ai'), isFalse);
    });

    test('settings and the quiz are refused', () {
      // Founder call, 25 Aug 2026. Settings is a long list of controls
      // the bubble lands on top of; the Quiz is timed, and a floating
      // button over a question someone is racing to answer is a mis-tap
      // waiting to happen.
      for (final route in const [
        '/settings',
        '/settings/notifications',
        '/quiz',
        '/quiz/play',
      ]) {
        expect(AdventAiBubble.allowedOn(route), isFalse, reason: route);
      }
    });
  });

  group('Advent AI bubble — suppression', () {
    // The route blocklist is a check on where the ROUTER says we are.
    // The AI screen also suppresses the bubble directly, because the
    // founder saw it there anyway on 25 Aug 2026 and a mounted screen is
    // a fact where a router location is an inference.
    setUp(() => AdventAiBubble.suppressed.value = 0);

    test('suppress/unsuppress balance out', () {
      AdventAiBubble.suppress();
      expect(AdventAiBubble.suppressed.value, 1);
      AdventAiBubble.unsuppress();
      expect(AdventAiBubble.suppressed.value, 0);
    });

    test('nests, so a screen over a screen stays suppressed', () {
      AdventAiBubble.suppress();
      AdventAiBubble.suppress();
      AdventAiBubble.unsuppress();
      expect(AdventAiBubble.suppressed.value, 1,
          reason: 'the outer screen is still up');
      AdventAiBubble.unsuppress();
      expect(AdventAiBubble.suppressed.value, 0);
    });

    test('never goes negative', () {
      // An unbalanced dispose must not leave the counter below zero,
      // where a later suppress() would not reach 1 and the bubble would
      // float over the AI screen again.
      AdventAiBubble.unsuppress();
      AdventAiBubble.unsuppress();
      expect(AdventAiBubble.suppressed.value, 0);
      AdventAiBubble.suppress();
      expect(AdventAiBubble.suppressed.value, 1);
    });
  });

  group('Advent AI bubble — where it SHOULD appear', () {
    // The blocklist is easy to over-extend one route at a time until the
    // feature has no entry point left. That is how the last floating
    // bubble died, so the positive case is pinned too.
    test('the ordinary surfaces of the app allow it', () {
      for (final route in const [
        '/home',
        '/watch',
        '/marketplace',
        '/profile',
        '/churches',
        '/events',
        '/library',
        // '/quiz' and '/settings' moved to the blocklist on 25 Aug 2026 —
        // see 'settings and the quiz are refused' above.
        '/prayer', // deliberately allowed — see below
        '/news',
        '/jobs',
      ]) {
        expect(
          AdventAiBubble.allowedOn(route),
          isTrue,
          reason: 'the bubble should be reachable from $route',
        );
      }
    });

    test('prayer allows it, unlike ads', () {
      // Deliberate divergence from ResumeAdManager.blockedPrefixes,
      // which blocks /prayer. An ADVERT on a prayer request is crass; an
      // assistant that can help someone find a passage to pray through
      // is the opposite. If this is ever reversed, reverse it knowingly.
      expect(AdventAiBubble.allowedOn('/prayer'), isTrue);
    });
  });
}
