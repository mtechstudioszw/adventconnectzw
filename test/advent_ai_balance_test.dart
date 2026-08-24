// `AiBalance` decides whether the composer is usable, so its parsing has
// to fail in the safe direction. The server is authoritative either way —
// a member who gets past this still cannot send, because `ai_spend_unit`
// refuses independently — but a client that unlocks itself on a malformed
// or unrecognised payload is a bug that looks like a security hole, and
// would be reported as one.

import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/services/ai/ai_balance_service.dart';
import 'package:advent_connect_zw/services/ai/ai_tiers.dart';

/// A well-formed row as `ai_my_balance()` returns it.
Map<String, dynamic> row({
  String reason = 'ok',
  int total = 5,
  int free = 5,
  int allowance = 0,
  bool premium = false,
  String? resets,
}) =>
    {
      'reason': reason,
      'total_remaining': total,
      'free_remaining': free,
      'allowance_units': allowance,
      'is_premium': premium,
      'resets_on': resets,
    };

void main() {
  group('reason parsing', () {
    test('maps every code the server can emit', () {
      // These six strings are the contract with ai_my_balance(). If the
      // SQL grows a seventh, this test is where the mismatch surfaces.
      const expected = {
        'ok': AiGateReason.ok,
        'out_of_free': AiGateReason.outOfFree,
        'out_of_allowance': AiGateReason.outOfAllowance,
        'free_pool_closed': AiGateReason.freePoolClosed,
        'blocked': AiGateReason.blocked,
        'service_suspended': AiGateReason.serviceSuspended,
      };
      expected.forEach((code, want) {
        expect(AiBalance.fromJson(row(reason: code)).reason, want,
            reason: code);
      });
    });

    test('an UNKNOWN reason fails closed', () {
      // A server that grows a new reason this build has never heard of
      // must not be able to unlock the composer. serviceSuspended is the
      // right landing spot: it sells nothing and blames nobody.
      for (final unknown in ['', 'sabbath_mode', 'OK', 'ok ', 'null']) {
        final b = AiBalance.fromJson(row(reason: unknown));
        expect(b.reason, AiGateReason.serviceSuspended, reason: '"$unknown"');
        expect(b.canUse, isFalse, reason: '"$unknown" unlocked the composer');
      }
    });

    test('a missing reason fails closed', () {
      final b = AiBalance.fromJson({'total_remaining': 99});
      expect(b.reason, AiGateReason.serviceSuspended);
      expect(b.canUse, isFalse);
    });

    test('an entirely empty payload fails closed', () {
      final b = AiBalance.fromJson({});
      expect(b.canUse, isFalse);
      expect(b.remaining, 0);
    });
  });

  group('canUse', () {
    test('needs BOTH an ok reason and something remaining', () {
      expect(AiBalance.fromJson(row(total: 5)).canUse, isTrue);

      // ok but empty — the server says fine, the counter says no.
      expect(AiBalance.fromJson(row(total: 0)).canUse, isFalse);

      // remaining but not ok — e.g. blocked with units left.
      expect(
        AiBalance.fromJson(row(reason: 'blocked', total: 5)).canUse,
        isFalse,
      );
    });
  });

  group('numbers', () {
    test('negatives are clamped, never rendered', () {
      // A bad migration returning -4 must not put "-4 questions left" in
      // front of a member.
      final b = AiBalance.fromJson(row(total: -4, free: -9, allowance: -1));
      expect(b.remaining, 0);
      expect(b.freeRemaining, 0);
      expect(b.grant, 0);
    });

    test('doubles from JSON survive as ints', () {
      final b = AiBalance.fromJson({
        'reason': 'ok',
        'total_remaining': 5.0,
        'free_remaining': 5.0,
        'allowance_units': 500.0,
      });
      expect(b.remaining, 5);
      expect(b.grant, 500);
    });

    test('a null reset date is not a crash', () {
      expect(AiBalance.fromJson(row(resets: null)).resetsOn, isNull);
      expect(AiBalance.fromJson(row(resets: 'not-a-date')).resetsOn, isNull);
    });

    test('a real reset date parses', () {
      final b = AiBalance.fromJson(row(resets: '2026-09-01'));
      expect(b.resetsOn?.year, 2026);
      expect(b.resetsOn?.month, 9);
    });
  });

  group('the low-balance warning', () {
    test('fires at the configured threshold, not a magic number', () {
      final at = AiBalance.fromJson(row(total: AiTiers.warnAtRemaining));
      expect(at.isRunningLow, isTrue);

      final above = AiBalance.fromJson(
          row(total: AiTiers.warnAtRemaining + 1));
      expect(above.isRunningLow, isFalse);
    });

    test('never fires for a subscriber with hundreds left', () {
      final b = AiBalance.fromJson(
          row(total: 480, allowance: 500, premium: true));
      expect(b.isRunningLow, isFalse);
    });

    test('does not fire at zero — that is the wall, not a warning', () {
      // At zero the member gets the gate sheet. A "running low" strip
      // underneath it would be saying the same thing twice.
      expect(AiBalance.fromJson(row(total: 0)).isRunningLow, isFalse);
    });
  });

  group('the unknown starting state', () {
    test('cannot be spent against', () {
      // Deliberately usable-looking so no paywall flashes before the
      // first fetch, but zero-length so nothing can be sent on it.
      expect(AiBalance.unknown.remaining, 0);
      expect(AiBalance.unknown.canUse, isFalse);
      expect(AiBalance.unknown.isPremium, isFalse);
    });
  });
}
