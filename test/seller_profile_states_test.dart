// The seller page loaded any shop and its products, whatever the shop's
// approval state (patch_031 says a non-approved shop never reaches buyers).
// Opened from the rail while offline it said the shop had no products, and
// every failure was titled "Seller not found".

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/models/seller_model.dart';
import 'package:advent_connect_zw/screens/seller/seller_profile_screen.dart';
import 'package:advent_connect_zw/theme/app_theme.dart';

import 'helpers/fake_supabase.dart';

Map<String, Object?> _seller(String status, {bool active = true}) => {
  'id': 11,
  'auth_user_id': 'shop-owner',
  'business_name': 'Dorcas Sewing',
  'status': status,
  'is_active': active,
};

final _product = <String, Object?>{
  'id': 5,
  'seller_id': 'shop-owner',
  'title': 'Choir robe',
  'price': 30,
  'category': 'clothing',
  'status': 'available',
};

Future<void> _pump(WidgetTester t, {Seller? initial}) async {
  t.view.physicalSize = const Size(390, 1400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: SellerProfileScreen(
        authUserId: 'shop-owner',
        initialSeller: initial,
      ),
    ),
  );
  for (var i = 0; i < 6; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(() => initFakeSupabase());

  for (final status in ['pending', 'rejected', 'rejected_final']) {
    testWidgets('a $status shop is closed to buyers', (t) async {
      setFakeSupabaseHandler((req) {
        if (req.url.path.endsWith('/sellers')) return [_seller(status)];
        if (req.url.path.endsWith('/products')) return [_product];
        return null;
      });
      await _pump(t);
      expect(find.text("This shop isn't open"), findsOneWidget);
      expect(find.text('Choir robe'), findsNothing);
      await t.pump(const Duration(seconds: 2));
    });
  }

  testWidgets('a deactivated shop is closed to buyers', (t) async {
    setFakeSupabaseHandler((req) {
      if (req.url.path.endsWith('/sellers')) {
        return [_seller('approved', active: false)];
      }
      if (req.url.path.endsWith('/products')) return [_product];
      return null;
    });
    await _pump(t);
    expect(find.text("This shop isn't open"), findsOneWidget);
    expect(find.text('Choir robe'), findsNothing);
    await t.pump(const Duration(seconds: 2));
  });

  testWidgets('an approved shop shows its products', (t) async {
    setFakeSupabaseHandler((req) {
      if (req.url.path.endsWith('/sellers')) return [_seller('approved')];
      if (req.url.path.endsWith('/products')) return [_product];
      return null;
    });
    await _pump(t);
    expect(find.text("This shop isn't open"), findsNothing);
    expect(find.text('Choir robe'), findsOneWidget);
    await t.pump(const Duration(seconds: 2));
  });

  testWidgets('a failed load from the rail does not claim "no products"', (
    t,
  ) async {
    setFakeSupabaseHandler((_) => throw Exception('network down'));
    await _pump(t, initial: Seller.fromJson(_seller('approved')));
    // postgrest retries a failed request with back-off before giving up.
    for (var i = 0; i < 20; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await t.pump(const Duration(seconds: 1));
    }
    expect(find.text("Couldn't load products"), findsOneWidget);
    await t.pump(const Duration(seconds: 30));
  });
}
