// Stage 6: the product page shows real store details (availability,
// rating, delivery, payment), records a view for buyers only, keeps the
// purchase action on one row, and the basket can save an item for later.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/models/product_model.dart';
import 'package:advent_connect_zw/screens/marketplace/cart_screen.dart';
import 'package:advent_connect_zw/screens/marketplace/product_details_screen.dart';
import 'package:advent_connect_zw/services/cart_service.dart';
import 'package:advent_connect_zw/theme/app_theme.dart';

import 'helpers/fake_supabase.dart';

final _seller = {
  'id': 25,
  'auth_user_id': 's1',
  'business_name': 'Theopath Healthcare',
  'status': 'approved',
  'is_active': true,
  'city': 'Harare',
  'offers_delivery': true,
  'delivery_area': 'Harare CBD',
  'delivery_fee': 'USD 3',
  'payment_methods': 'EcoCash',
  'rating': 4.6,
  'rating_count': 5,
};

Map<String, Object?> _p(int id, String title) => {
  'id': id,
  'seller_id': 's1',
  'title': title,
  'price': 10,
  'status': 'available',
  'image_urls': [],
  'created_at': '2026-10-20T00:00:00Z',
};

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 8; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(() async {
    await initFakeSupabase();
    await signInFake('buyer');
  });

  testWidgets('product page: store details, view recorded, one-row bar', (
    t,
  ) async {
    final rpcs = <String>[];
    setFakeSupabaseHandler((req) {
      final path = req.url.path;
      if (path.contains('/rpc/')) {
        rpcs.add('${path.split('/').last} ${req.body}');
        return null;
      }
      if (path.endsWith('/sellers')) return [_seller];
      if (path.endsWith('/products')) {
        final id = req.url.queryParameters['id'];
        final rows = [_p(21, 'Neem Capsules'), _p(22, 'Moringa Powder')];
        if (id != null) {
          return rows.where((r) => 'eq.${r['id']}' == id).toList();
        }
        return rows;
      }
      return null;
    });
    t.view.physicalSize = const Size(412, 2400);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const ProductDetailsScreen(productId: '21'),
      ),
    );
    await _settle(t);

    expect(find.text('Available'), findsOneWidget);
    expect(find.text('Delivery & pickup'), findsOneWidget);
    expect(find.textContaining('Harare CBD'), findsOneWidget);
    expect(find.text('EcoCash'), findsOneWidget);
    expect(find.textContaining('4.6'), findsWidgets);
    expect(find.text('More from this shop'), findsOneWidget);
    expect(find.text('Moringa Powder'), findsOneWidget);
    expect(find.text('Add to basket'), findsOneWidget);
    expect(find.text('Chat'), findsOneWidget);
    // Adding morphs the primary action instead of a toast.
    await t.tap(find.text('Add to basket'));
    await _settle(t);
    expect(find.text('In basket'), findsOneWidget);
    expect(find.text('View'), findsOneWidget);
    // Both contact routes sit behind Contact.
    await t.tap(find.text('Chat'));
    await _settle(t);
    expect(find.text('Message in the app'), findsOneWidget);
    expect(find.text('WhatsApp'), findsNothing); // no phone on this shop row
    await t.tapAt(const Offset(10, 10));
    await _settle(t);
    expect(
      rpcs.where((r) => r.startsWith('record_product_view')),
      hasLength(1),
    );
    expect(jsonDecode(rpcs.first.split(' ').skip(1).join(' ')), {
      'p_product': 21,
    });
    await t.pump(const Duration(seconds: 30));
  });

  testWidgets('basket: Save for later moves the item to Saved', (t) async {
    final writes = <String>[];
    setFakeSupabaseHandler((req) {
      if (req.method == 'POST') writes.add(req.url.path.split('/').last);
      if (req.url.path.endsWith('/sellers')) return [_seller];
      return null;
    });
    await t.runAsync(() async {
      await CartService.clear();
      await CartService.add(
        Product.fromJson({..._p(21, 'Neem Capsules'), 'seller_name': 'T'}),
      );
    });
    t.view.physicalSize = const Size(412, 1000);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const CartScreen()),
    );
    await _settle(t);
    expect(find.textContaining('Delivers to Harare CBD'), findsOneWidget);
    await t.tap(find.text('Save for later'));
    await _settle(t);
    expect(writes, contains('saved_listings'));
    expect(CartService.isEmpty, isTrue);
    await t.pump(const Duration(seconds: 30));
  });
}
