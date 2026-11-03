import 'package:advent_connect_zw/config/router_config.dart';
import 'package:flutter_test/flutter_test.dart';

/// Group info must NOT be nested under the chat route. go_router builds
/// every page of a pushed nested route, so /messages/:id/info pushed a
/// second, empty chat screen under the info screen each time a group
/// header was tapped — church groups "not loading" (3 Nov 2026).
void main() {
  test('group info is its own top-level route', () {
    final loc = appRouter.namedLocation(
      'group_info',
      pathParameters: {'id': '151'},
    );
    expect(loc, '/group-info/151');
    expect(loc.startsWith('/messages/'), isFalse);
  });
}
