// Guards the calling tunables against two quiet failure modes.
//
//   1. A HANDSET INHERITING THE PREVIOUS MEMBER'S CONFIG. Every value in
//      CallConfig is a mutable static, fetched per session. SessionReset
//      calls reset() on sign-out; if reset() ever misses a field, the
//      next member on that phone silently runs on somebody else's
//      ceilings — a bug that never reproduces on a developer's device
//      because it needs two accounts and a sign-out.
//
//   2. THE FALLBACKS DRIFTING FROM patch_260. These numbers are what a
//      first launch and an offline device run on, and they are supposed
//      to be byte-identical to the app_config rows the patch seeds. The
//      literals are asserted here so a "harmless" tweak to one side is
//      visible.
//
// Also pins maxDurationFor, because swapping the group and direct
// ceilings would cut group calls off half an hour early and nobody would
// connect the two facts.
//
// Pure Dart: reset(), debugOverride() and maxDurationFor() never touch
// Supabase. refresh() is deliberately NOT exercised — it needs a client.

import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/services/calls/call_config.dart';

void main() {
  // These are process-wide statics: leave them as we found them, or the
  // next test file in the same run inherits our overrides.
  setUp(CallConfig.reset);
  tearDown(CallConfig.reset);

  group('reset() restores every shipped fallback', () {
    test('the defaults are the values patch_260 seeds', () {
      CallConfig.reset();

      expect(CallConfig.enabled, isTrue);
      expect(CallConfig.ringTimeout, const Duration(seconds: 45));
      expect(CallConfig.connectTimeout, const Duration(seconds: 45));
      expect(CallConfig.maxGroupParticipants, 5);
      expect(CallConfig.maxDirectDuration, const Duration(minutes: 120));
      expect(CallConfig.maxGroupDuration, const Duration(minutes: 90));
      expect(CallConfig.heartbeat, const Duration(seconds: 15));
    });

    test('a signed-out handset does not keep the last member\'s config', () {
      CallConfig.debugOverride(
        enabled: false,
        ringTimeout: const Duration(seconds: 2),
        connectTimeout: const Duration(seconds: 3),
        maxGroupParticipants: 16,
        heartbeat: const Duration(seconds: 120),
        maxDirectDuration: const Duration(minutes: 1),
        maxGroupDuration: const Duration(minutes: 2),
      );

      CallConfig.reset();

      expect(CallConfig.enabled, isTrue);
      expect(CallConfig.ringTimeout, const Duration(seconds: 45));
      expect(CallConfig.connectTimeout, const Duration(seconds: 45));
      expect(CallConfig.maxGroupParticipants, 5);
      expect(CallConfig.maxDirectDuration, const Duration(minutes: 120));
      expect(CallConfig.maxGroupDuration, const Duration(minutes: 90));
      expect(CallConfig.heartbeat, const Duration(seconds: 15));
    });

    test('reset() marks the config unfetched again', () {
      // Otherwise the next member's session believes it has already read
      // the server's values and never refreshes.
      CallConfig.reset();
      expect(CallConfig.isLoaded, isFalse);
    });

    test('reset() is idempotent', () {
      CallConfig.reset();
      CallConfig.reset();
      expect(CallConfig.ringTimeout, const Duration(seconds: 45));
      expect(CallConfig.enabled, isTrue);
    });

    test('the master switch defaults to ON', () {
      // Fail-open: a config that never loaded must not disable calling.
      expect(CallConfig.enabled, isTrue);
    });
  });

  group('debugOverride changes only what it is given', () {
    test('one field at a time leaves the rest alone', () {
      CallConfig.debugOverride(ringTimeout: const Duration(seconds: 2));

      expect(CallConfig.ringTimeout, const Duration(seconds: 2));
      expect(CallConfig.connectTimeout, const Duration(seconds: 45));
      expect(CallConfig.maxGroupParticipants, 5);
      expect(CallConfig.heartbeat, const Duration(seconds: 15));
      expect(CallConfig.maxDirectDuration, const Duration(minutes: 120));
      expect(CallConfig.maxGroupDuration, const Duration(minutes: 90));
      expect(CallConfig.enabled, isTrue);
    });

    test('an empty call changes nothing at all', () {
      CallConfig.debugOverride();

      expect(CallConfig.enabled, isTrue);
      expect(CallConfig.ringTimeout, const Duration(seconds: 45));
      expect(CallConfig.connectTimeout, const Duration(seconds: 45));
      expect(CallConfig.maxGroupParticipants, 5);
      expect(CallConfig.maxDirectDuration, const Duration(minutes: 120));
      expect(CallConfig.maxGroupDuration, const Duration(minutes: 90));
      expect(CallConfig.heartbeat, const Duration(seconds: 15));
    });

    test('enabled: false actually takes the feature down', () {
      CallConfig.debugOverride(enabled: false);
      expect(CallConfig.enabled, isFalse);

      CallConfig.debugOverride(ringTimeout: const Duration(seconds: 1));
      expect(
        CallConfig.enabled,
        isFalse,
        reason: 'an unrelated override switched calling back on',
      );
    });

    test('every field can be overridden', () {
      CallConfig.debugOverride(
        enabled: false,
        ringTimeout: const Duration(seconds: 7),
        connectTimeout: const Duration(seconds: 8),
        maxGroupParticipants: 3,
        heartbeat: const Duration(seconds: 9),
        maxDirectDuration: const Duration(minutes: 10),
        maxGroupDuration: const Duration(minutes: 11),
      );

      expect(CallConfig.enabled, isFalse);
      expect(CallConfig.ringTimeout, const Duration(seconds: 7));
      expect(CallConfig.connectTimeout, const Duration(seconds: 8));
      expect(CallConfig.maxGroupParticipants, 3);
      expect(CallConfig.heartbeat, const Duration(seconds: 9));
      expect(CallConfig.maxDirectDuration, const Duration(minutes: 10));
      expect(CallConfig.maxGroupDuration, const Duration(minutes: 11));
    });

    test('ring and connect timeouts are separate settings', () {
      // They share a default, which is exactly how one could be wired to
      // the other without anybody noticing.
      CallConfig.debugOverride(connectTimeout: const Duration(seconds: 5));
      expect(CallConfig.connectTimeout, const Duration(seconds: 5));
      expect(CallConfig.ringTimeout, const Duration(seconds: 45));
    });

    test('overriding does not claim the server config was loaded', () {
      CallConfig.debugOverride(ringTimeout: const Duration(seconds: 2));
      expect(CallConfig.isLoaded, isFalse);
    });
  });

  group('maxDurationFor picks the ceiling for the shape of call', () {
    test('a group call gets the group ceiling', () {
      expect(
        CallConfig.maxDurationFor(isGroup: true),
        const Duration(minutes: 90),
      );
    });

    test('a 1:1 call gets the direct ceiling', () {
      expect(
        CallConfig.maxDurationFor(isGroup: false),
        const Duration(minutes: 120),
      );
    });

    test('the two are not the same value, so a swap would be visible', () {
      expect(
        CallConfig.maxDurationFor(isGroup: true),
        isNot(CallConfig.maxDurationFor(isGroup: false)),
      );
      expect(
        CallConfig.maxDurationFor(isGroup: true),
        lessThan(CallConfig.maxDurationFor(isGroup: false)),
        reason: 'a mesh group call is the more expensive one to leave open',
      );
    });

    test('it reads the live values, not a snapshot taken at startup', () {
      CallConfig.debugOverride(
        maxGroupDuration: const Duration(minutes: 5),
        maxDirectDuration: const Duration(minutes: 6),
      );
      expect(
        CallConfig.maxDurationFor(isGroup: true),
        const Duration(minutes: 5),
      );
      expect(
        CallConfig.maxDurationFor(isGroup: false),
        const Duration(minutes: 6),
      );
    });
  });
}
