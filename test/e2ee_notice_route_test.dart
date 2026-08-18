import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/config/router_config.dart';

/// The "Learn more" link on the encryption notice.
///
/// A route name is just a string until somebody taps it — GoRouter throws
/// on an unknown name, so a typo here is a crash, not an empty screen,
/// and neither the analyzer nor any widget test that never navigates will
/// catch it. This has already bitten twice in this project
/// (`help_center`, `advent_news_details`), so the name gets pinned.
void main() {
  test('the privacy policy route the encryption notice links to exists', () {
    expect(
      () => appRouter.configuration.namedLocation('privacy'),
      returnsNormally,
    );
  });

  test('it resolves to the path the legal site and Play listing use', () {
    expect(appRouter.configuration.namedLocation('privacy'), '/privacy');
  });
}
