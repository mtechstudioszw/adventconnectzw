import 'package:advent_connect_zw/config/router_config.dart';
import 'package:advent_connect_zw/services/two_step_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('two-step router guard', () {
    test('owed code sends every app screen to the code screen', () {
      for (final p in ['/home', '/chat/abc', '/settings', '/profile-setup',
          '/group-info/1', '/premium']) {
        expect(twoStepRedirectFor(p, pending: true), '/two-step-code', reason: p);
      }
    });
    test('sign-in flow stays reachable while code is owed', () {
      for (final p in ['/splash', '/login', '/two-step-code',
          '/forgot-password', '/maintenance', '/account-banned']) {
        expect(twoStepRedirectFor(p, pending: true), isNull, reason: p);
      }
    });
    test('no code owed: nothing redirected, code screen bounces to splash', () {
      expect(twoStepRedirectFor('/home', pending: false), isNull);
      expect(twoStepRedirectFor('/two-step-code', pending: false), '/splash');
    });
  });

  group('friendly errors', () {
    test('rate limit', () {
      expect(TwoStepService.friendlyError(
              const AuthException('too many requests', statusCode: '429')),
          contains('Too many'));
    });
    test('wrong code', () {
      expect(TwoStepService.friendlyError(
              const AuthException('Invalid TOTP code entered')),
          contains('wrong or has expired'));
    });
    test('unknown', () {
      expect(TwoStepService.friendlyError(Exception('boom')),
          'Something went wrong. Please try again.');
    });
    test('pending is false without Supabase initialised', () {
      expect(TwoStepService.challengePending, isFalse);
    });
  });
}
