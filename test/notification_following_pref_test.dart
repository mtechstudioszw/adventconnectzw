// "Posts from people & Pages you follow" (patch_283): a Settings switch
// stored in profiles.notif_categories.following, read by the database.

import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/services/notification_preferences_service.dart';

void main() {
  test('missing key means on — existing members keep alerts', () {
    final p = NotificationCategoryPrefs.fromJson({'social': true});
    expect(p.following, isTrue);
  });

  test('off survives a round trip under the key the database reads', () {
    final off = NotificationCategoryPrefs.defaults.copyWith(following: false);
    final json = off.toJson();
    expect(json['following'], isFalse);
    expect(NotificationCategoryPrefs.fromJson(json).following, isFalse);
    // Other switches untouched.
    expect(json['social'], isTrue);
  });
}
