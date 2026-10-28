// The order create and its read-back shared one try. A signal drop between
// them reported a placed order as failed and left its items in the basket,
// so tapping again sent the shop a duplicate order.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/models/product_model.dart';
import 'package:advent_connect_zw/screens/marketplace/cart_screen.dart';
import 'package:advent_connect_zw/services/cart_service.dart';
import 'package:advent_connect_zw/theme/app_theme.dart';

import 'helpers/fake_supabase.dart';

Future<void> _settle(WidgetTester t, {int rounds = 10}) async {
  for (var i = 0; i < rounds; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await t.pump(const Duration(milliseconds: 500));
  }
}

void main() {
  setUpAll(() async {
    await initFakeSupabase();
    await signInFake('buyer-1');
  });

  testWidgets('a placed order leaves the basket even if read-back fails', (
    t,
  ) async {
    var placeCalls = 0;
    setFakeSupabaseHandler((req) {
      if (req.url.path.endsWith('/rpc/place_order')) {
        placeCalls++;
        return 42;
      }
      if (req.url.path.endsWith('/orders')) {
        throw Exception('signal dropped');
      }
      return null;
    });

    CartService.resetForTest();
    await CartService.add(
      Product.fromJson({
        'id': '9',
        'seller_id': 'shop-owner',
        'seller_name': 'Dorcas Sewing',
        'title': 'Choir robe',
        'price': 30,
        'category': 'clothing',
        'status': 'available',
      }),
    );

    t.view.physicalSize = const Size(390, 1200);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const CartScreen()),
    );
    await t.pump(const Duration(seconds: 1));

    await t.tap(find.text('Send order request'));
    await t.pumpAndSettle(const Duration(milliseconds: 100));
    await t.tap(find.text('Create order request'));
    await _settle(t, rounds: 30);

    expect(placeCalls, 1);
    expect(CartService.isEmpty, isTrue, reason: 'placed shop must leave');
    expect(find.textContaining('Order request saved'), findsOneWidget);
    expect(find.textContaining('Could not place'), findsNothing);
    await t.pump(const Duration(seconds: 30));
  });
}
