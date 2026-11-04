import 'package:advent_connect_zw/services/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Owner, 4 Nov 2026: the official account's name kept flipping back to
/// the Google name. The profile name wins over login metadata.
void main() {
  tearDown(() => AuthService.profileName.value = null);

  test('profile name is what the app shows', () {
    AuthService.profileName.value = 'Adventist Super App Team';
    expect(AuthService.myFullName, 'Adventist Super App Team');
  });

  test('no profile name and no session: empty, not a crash', () {
    AuthService.profileName.value = null;
    expect(() => AuthService.myFullName, returnsNormally);
  });
}
