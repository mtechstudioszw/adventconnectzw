// The rate-limit copy must never quote a wait we were not given.
//
// 17 Aug 2026. The founder reported two things an hour apart: "codes are
// getting spammed" and "it's not sending the reset code". They are the same
// event. Supabase's `rate_limit_otp` is 30/hr and is shared PROJECT-WIDE
// between signup verification and password recovery, so ordinary signup
// traffic exhausts it and resets then fail for everybody.
//
// What made it a loop rather than a wait: `_friendlyAuthError` answered
// EVERY rate limit with "please wait a minute and try again" when the real
// window is an hour. People came back 60 seconds later, failed, and tried
// again — the attempts that squeaked through are most of the "spam", and
// the ones that didn't are the missing reset codes.
//
// The per-email throttles were never the problem and are not changed here:
// password reset is 3/hr per email (`check_and_consume_rate_limit`) and
// signup resend is 3/hr per email (patch_125) with exponential local
// backoff. This file pins only the COPY.
//
// NOTE: these assertions are about wording, which is the whole point — the
// bug was that the wording was confidently wrong.

import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/services/auth_service.dart';

String map(String raw) => AuthService.friendlyAuthErrorForTest(raw);

void main() {
  group('rate-limit copy', () {
    test('never tells anyone to wait "a minute" for a rate limit', () {
      // The exact regression. Any rate-limit shaped error that does not
      // carry its own number must not invent a one-minute wait.
      const raws = [
        'Email rate limit exceeded',
        'over_email_send_rate_limit',
        'Request rate limit reached',
        'Too many requests',
      ];
      for (final raw in raws) {
        final msg = map(raw).toLowerCase();
        expect(
          msg.contains('wait a minute'),
          isFalse,
          reason: '"$raw" still promises a one-minute wait',
        );
      }
    });

    test('the project-wide email budget is described as an hour', () {
      for (final raw in ['Email rate limit exceeded', 'over_email_send_rate_limit']) {
        final msg = map(raw).toLowerCase();
        expect(msg, contains('hour'), reason: 'wrong window for "$raw"');
      }
    });

    test('offers Google, which needs no emailed code at all', () {
      // The one route out of an exhausted email budget. If this ever
      // disappears the member is left with no action but to retry, which
      // is what deepens the hole.
      final msg = map('Email rate limit exceeded').toLowerCase();
      expect(msg, contains('google'));
    });

    test('uses GoTrue\'s own number for the per-email cooldown', () {
      // GoTrue: "For security purposes, you can only request this after
      // 54 seconds." That number is real — quote it rather than rounding
      // it to a minute.
      final msg = map(
        'For security purposes, you can only request this after 54 seconds.',
      );
      expect(msg, contains('54'));
      expect(msg.toLowerCase(), contains('wait'));
    });

    test('the exact-seconds branch wins over the generic email branch', () {
      // GoTrue sends the per-email cooldown WITH the
      // over_email_send_rate_limit code attached. Reporting that as the
      // hour-long project budget would be a new lie in the other
      // direction, so the specific number must take precedence.
      final msg = map(
        'AuthApiException(message: For security purposes, you can only '
        'request this after 47 seconds., statusCode: 429, '
        'code: over_email_send_rate_limit)',
      );
      expect(msg, contains('47'));
      expect(msg.toLowerCase(), isNot(contains('hour')));
    });
  });

  group('unrelated mappings still hold', () {
    test('offline still reads as offline', () {
      expect(map('SocketException: Failed host lookup').toLowerCase(),
          contains('offline'));
    });

    test('bad credentials are not mistaken for a rate limit', () {
      expect(map('Invalid login credentials'), contains('incorrect'));
    });

    test('unknown errors fall through untouched', () {
      expect(map('Something we have never seen'),
          'Something we have never seen');
    });
  });
}
