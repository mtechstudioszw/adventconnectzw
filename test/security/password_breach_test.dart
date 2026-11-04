import 'package:advent_connect_zw/services/password_breach_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  tearDown(() => PasswordBreachService.clientOverride = null);

  test('only the first 5 hash characters would be sent', () {
    // SHA-1("password") = 5BAA61E4C9B93F3F0682250B6CF8331B7EE68FD8
    final (prefix, suffix) = PasswordBreachService.hashParts('password');
    expect(prefix, '5BAA6');
    expect(suffix, '1E4C9B93F3F0682250B6CF8331B7EE68FD8');
  });

  test('a breached password is caught; the request carries only the prefix',
      () async {
    late Uri asked;
    PasswordBreachService.clientOverride = MockClient((req) async {
      asked = req.url;
      return http.Response(
          '0018A45C4D1DEF81644B54AB7F969B88D65:1\r\n'
          '1E4C9B93F3F0682250B6CF8331B7EE68FD8:9659365\r\n',
          200);
    });
    expect(await PasswordBreachService.isBreached('password'), isTrue);
    expect(asked.path, '/range/5BAA6');
    expect(asked.toString(), isNot(contains('1E4C9B93F3F0682250B6CF8331B7EE68FD8')));
  });

  test('padding rows (count 0) are not matches', () async {
    PasswordBreachService.clientOverride = MockClient((_) async =>
        http.Response('1E4C9B93F3F0682250B6CF8331B7EE68FD8:0\r\n', 200));
    expect(await PasswordBreachService.isBreached('password'), isFalse);
  });

  test('no network lets the password through (fail open)', () async {
    PasswordBreachService.clientOverride =
        MockClient((_) async => throw Exception('offline'));
    expect(await PasswordBreachService.isBreached('password'), isFalse);
  });
}
