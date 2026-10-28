// When RLS refuses an update, PostgREST changes zero rows and returns no
// error. updateStatus treated that as success, so the order screen showed a
// new status for an order that never changed.

import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/services/order_service.dart';

import 'helpers/fake_supabase.dart';

void main() {
  setUpAll(() async {
    await initFakeSupabase();
    await signInFake('shop-owner');
  });

  test('zero rows updated is an error', () async {
    setFakeSupabaseHandler((_) => const <Object>[]);
    await expectLater(
      OrderService.updateStatus('17', 'confirmed'),
      throwsA(isA<StateError>()),
    );
  });

  test('a real update succeeds', () async {
    setFakeSupabaseHandler((req) {
      if (req.method == 'PATCH') {
        return [
          {'id': 17},
        ];
      }
      return null;
    });
    await OrderService.updateStatus('17', 'confirmed');
  });
}
