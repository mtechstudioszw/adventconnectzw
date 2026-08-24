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

    test('no messaging screen imports the bubble', () {
      // The blocklist governs the app-wide layer. A messaging screen
      // that mounted the bubble itself would bypass it entirely, and
      // nothing else would catch that.
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
          reason: 'Advent Chat must carry no AI bubble — founder rule');
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
        '/quiz',
        '/prayer', // deliberately allowed — see below
        '/settings',
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
