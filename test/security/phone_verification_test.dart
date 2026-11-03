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
}
