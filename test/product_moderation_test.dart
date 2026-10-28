// Listings could not be reported (Apple 1.2 asks for it), and moderators
// could only reject a whole shop. Product details now has Report for
// everyone and Hide for super admins (patch_272).

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/screens/marketplace/product_details_screen.dart';
import 'package:advent_connect_zw/theme/app_theme.dart';

import 'helpers/fake_supabase.dart';

final _product = {
  'id': 21,
  'seller_id': 'shop-owner',
  'title': 'Diabetes kit',
  'price': 35,
  'category': 'other',
  'status': 'available',
};

Future<void> _settle(WidgetTester t, {int rounds = 6}) async {
  for (var i = 0; i < rounds; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pump(WidgetTester t) async {
  t.view.physicalSize = const Size(390, 3000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: const ProductDetailsScreen(productId: '21'),
    ),
  );
  await _settle(t);
}

void main() {
  setUpAll(() async {
    await initFakeSupabase();
    await signInFake('moderator-1');
  });

  testWidgets('members get Report but not Hide', (t) async {
    setFakeSupabaseHandler((req) {
      final path = req.url.path;
      if (path.endsWith('/products')) return [_product];
      if (path.endsWith('/sellers')) {
        return [
          {'status': 'approved', 'is_active': true, 'business_name': 'Shop'},
        ];
      }
      if (path.endsWith('/profiles')) {
        return [
          {'is_super_admin': false},
        ];
      }
      return null;
    });
    await _pump(t);
    expect(find.text('Report this listing'), findsOneWidget);
    expect(find.text('Hide listing (admin)'), findsNothing);
    await t.pump(const Duration(seconds: 2));
  });

  testWidgets('a super admin can hide it, with a reason for the seller', (
    t,
  ) async {
    Map<String, dynamic>? rpcBody;
    setFakeSupabaseHandler((req) {
      final path = req.url.path;
      if (path.endsWith('/rpc/admin_set_product_status')) {
        rpcBody = jsonDecode(req.body) as Map<String, dynamic>;
        return null;
      }
      if (path.endsWith('/products')) return [_product];
      if (path.endsWith('/sellers')) {
        return [
          {'status': 'approved', 'is_active': true, 'business_name': 'Shop'},
        ];
      }
      if (path.endsWith('/profiles')) {
        return [
          {'is_super_admin': true},
        ];
      }
      return null;
    });
    await _pump(t);

    await t.tap(find.text('Hide listing (admin)'));
    await t.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text('Hide this listing?'), findsOneWidget);
    await t.tap(find.widgetWithText(TextButton, 'Hide'));
    await _settle(t);

    expect(rpcBody, isNotNull);
    expect(rpcBody!['p_product_id'], 21);
    expect(rpcBody!['p_status'], 'removed');
    expect(rpcBody!['p_reason'], contains('medical condition'));
    await t.pump(const Duration(seconds: 5));
  });
}
