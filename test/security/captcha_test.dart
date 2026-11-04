import 'package:advent_connect_zw/services/captcha_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('off (no site key / no Supabase): no token, auth unchanged', () async {
    expect(await CaptchaService.token(), isNull);
  });

  test('the site key is embedded safely in the page', () {
    final page = CaptchaService.pageFor("0x4AAA'</script>");
    expect(page, contains('challenges.cloudflare.com/turnstile/v0/api.js'));
    expect(page, isNot(contains('</script>"')));
    expect(page, contains('Captcha.postMessage(t)'));
  });
}
