import 'package:advent_connect_zw/config/router_config.dart';
import 'package:advent_connect_zw/services/phone_verification_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('normalise', () {
    test('Zimbabwe local number', () {
      expect(PhoneVerificationService.normalise('077 123 4567'), '+263771234567');
    });
    test('international forms', () {
      expect(PhoneVerificationService.normalise('+27 82 123 4567'), '+27821234567');
      expect(PhoneVerificationService.normalise('0027821234567'), '+27821234567');
    });
    test('rejects junk', () {
      expect(PhoneVerificationService.normalise('hello'), isNull);
      expect(PhoneVerificationService.normalise('12345'), isNull);
      expect(PhoneVerificationService.normalise('+0123456789'), isNull);
    });
  });
  test('number already on another account', () {
    expect(PhoneVerificationService.friendlyError(const AuthException(
            'A user with this phone number has already been registered')),
        contains('already used by another account'));
  });
  test('rate limited', () {
    expect(PhoneVerificationService.friendlyError(const AuthException(
            'For security purposes, you can only request this after 52 seconds.',
            statusCode: '429')),
        contains('Too many codes'));
  });
  test('status is ok when the server cannot be asked', () async {
    expect(await PhoneVerificationService.status(), 'ok');
  });

  group('phone block (owner: unverified account no longer works)', () {
    test('every app screen goes to the verify screen', () {
      for (final p in ['/home', '/chat/1', '/quiz', '/settings', '/premium',
          '/group-info/9', '/biometric-lock']) {
        expect(phoneRedirectFor(p, required: true), '/verify-phone', reason: p);
      }
    });
    test('verify screen and sign-in flow stay reachable', () {
      for (final p in ['/verify-phone', '/login', '/splash', '/maintenance']) {
        expect(phoneRedirectFor(p, required: true), isNull, reason: p);
      }
    });
    test('verified: nothing redirected; verify screen bounces away', () {
      expect(phoneRedirectFor('/home', required: false), isNull);
      expect(phoneRedirectFor('/verify-phone', required: false), '/splash');
    });
    test('no server answer keeps the current block', () async {
      PhoneVerificationService.required.value = true;
      expect(await PhoneVerificationService.refresh(), isTrue);
      PhoneVerificationService.required.value = false;
    });
  });
}
