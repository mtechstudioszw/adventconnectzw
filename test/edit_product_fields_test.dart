// Editing a listing never pre-filled subcategory, condition or location,
// and never saved them: a "Like new" item opened as "New", and whatever
// the seller changed in those fields was silently dropped.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/models/product_model.dart';
import 'package:advent_connect_zw/screens/marketplace/add_product_screen.dart';
import 'package:advent_connect_zw/services/post_limit_error.dart';
import 'package:advent_connect_zw/services/seller_service.dart';
import 'package:advent_connect_zw/theme/app_theme.dart';

import 'helpers/fake_supabase.dart';

final _row = <String, Object?>{
  'id': 7,
  'seller_id': 'seller-1',
  'title': 'Church shoes',
  'price': 20,
  'price_currency': 'USD',
  'category': 'clothing',
  'subcategory': 'Shoes',
  'condition': 'like_new',
  'location': 'Avondale',
  'country': 'ZW',
  'province': 'Harare',
  'status': 'available',
};

/// The form only shows for an approved seller.
Object? _approvedSeller(dynamic req) {
  if (req.url.path.endsWith('/sellers')) {
    return [
      {
        'id': 'shop-1',
        'auth_user_id': 'seller-1',
        'business_name': 'Shoe shop',
        'status': 'approved',
        'is_active': true,
      },
    ];
  }
  return null;
}

void main() {
  setUpAll(() async {
    await initFakeSupabase();
    await signInFake('seller-1');
  });

  testWidgets('edit form pre-fills subcategory, condition and location', (
    t,
  ) async {
    setFakeSupabaseHandler(_approvedSeller);
    t.view.physicalSize = const Size(390, 2400);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: AddProductScreen(initialProduct: Product.fromJson(_row)),
      ),
    );
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await t.pump(const Duration(seconds: 1));

    expect(find.widgetWithText(TextField, 'Shoes'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Avondale'), findsOneWidget);
    expect(find.text('Like new'), findsOneWidget);
    await t.pump(const Duration(seconds: 2));
  });

  testWidgets('an unknown stored condition does not crash the dropdown', (
    t,
  ) async {
    setFakeSupabaseHandler(_approvedSeller);
    t.view.physicalSize = const Size(390, 2400);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: AddProductScreen(
          initialProduct: Product.fromJson({..._row, 'condition': 'used'}),
        ),
      ),
    );
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await t.pump(const Duration(seconds: 1));
    expect(t.takeException(), isNull);
    await t.pump(const Duration(seconds: 2));
  });

  test(
    'updateProduct sends the three fields; null condition is left alone',
    () async {
      Map<String, dynamic>? sent;
      setFakeSupabaseHandler((req) {
        if (req.method == 'PATCH' && req.url.path.endsWith('/products')) {
          sent = jsonDecode(req.body) as Map<String, dynamic>;
          return _row; // .single() asks for an object, not a list
        }
        return null;
      });

      await SellerService.updateProduct(
        productId: '7',
        title: 'Church shoes',
        price: 20,
        currency: 'USD',
        category: 'clothing',
        subcategory: 'Boots',
        location: '',
        condition: null,
      );
      expect(sent, isNotNull);
      expect(sent!['subcategory'], 'Boots');
      expect(sent!.containsKey('location'), isTrue);
      expect(sent!['location'], isNull); // cleared
      expect(sent!.containsKey('condition'), isFalse); // untouched
    },
  );

  test(
    'a daily-limit failure surfaces its own message, not "try again"',
    () async {
      Object caught = 'nothing thrown';
      try {
        await PostLimitError.guard(
          PostSection.product,
          () async => throw Exception('ERROR: daily post limit reached'),
        );
      } catch (e) {
        caught = e;
      }
      expect(
        PostLimitError.messageFor(caught, fallback: 'Please try again.'),
        contains('Try again in 24 hours'),
      );
      expect(
        PostLimitError.messageFor(
          Exception('boom'),
          fallback: 'Please try again.',
        ),
        'Please try again.',
      );
    },
  );
}
