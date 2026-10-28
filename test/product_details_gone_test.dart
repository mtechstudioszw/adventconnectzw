// Opening a shared link to a listing that no longer exists crashed the
// details screen: fetchProductById returned null, nothing had been passed
// in, and the body did `_product!`. A listing opened from a stale grid kept
// offering "Add to basket" for something nobody can buy.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/models/product_model.dart';
import 'package:advent_connect_zw/screens/marketplace/product_details_screen.dart';
import 'package:advent_connect_zw/theme/app_theme.dart';

import 'helpers/fake_supabase.dart';

Future<void> _pump(WidgetTester t, Widget screen) async {
  t.view.physicalSize = const Size(390, 844);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(theme: AppTheme.light, home: screen));
  // Let the fake HTTP round trip resolve.
  for (var i = 0; i < 5; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await t.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUpAll(() => initFakeSupabase());

  testWidgets('deleted listing via shared link shows a notice, not a crash', (
    t,
  ) async {
    setFakeSupabaseHandler((_) => const <Object>[]); // no such product
    await _pump(t, const ProductDetailsScreen(productId: '404'));

    expect(t.takeException(), isNull);
    expect(find.text('This listing is no longer available'), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);
  });

  testWidgets('a stale grid item that is gone loses its buy actions', (
    t,
  ) async {
    setFakeSupabaseHandler((_) => const <Object>[]);
    final stale = Product.fromJson({
      'id': '7',
      'seller_id': 'seller-1',
      'title': 'Church shoes',
      'price': 20,
      'category': 'clothing',
      'status': 'available',
    });
    await _pump(t, ProductDetailsScreen(productId: '7', initialProduct: stale));

    expect(t.takeException(), isNull);
    expect(find.text('This listing is no longer available'), findsOneWidget);
    expect(find.text('Church shoes'), findsNothing);
    // The listing painted briefly before the server answered; let its
    // entrance animations finish.
    await t.pump(const Duration(seconds: 2));
  });

  testWidgets('a listing the seller removed is gone for buyers', (t) async {
    setFakeSupabaseHandler((req) {
      if (req.url.path.endsWith('/products')) {
        return [
          {
            'id': 8,
            'seller_id': 'someone-else',
            'title': 'Old hymnal',
            'price': 5,
            'category': 'books',
            'status': 'removed',
          },
        ];
      }
      return null;
    });
    await _pump(t, const ProductDetailsScreen(productId: '8'));

    expect(t.takeException(), isNull);
    expect(find.text('This listing is no longer available'), findsOneWidget);
    expect(find.text('RESERVED'), findsNothing);
  });
}
