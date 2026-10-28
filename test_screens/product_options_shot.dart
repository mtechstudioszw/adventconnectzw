// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/marketplace/product_image_source.dart';
import 'package:advent_connect_zw/models/product_model.dart';
import 'package:advent_connect_zw/screens/marketplace/add_product_screen.dart';
import 'package:advent_connect_zw/screens/marketplace/product_details_screen.dart';

import '../test/helpers/fake_supabase.dart';
import 'shot.dart';

const _fx = 'test_screens/fixtures';

final _seller = {
  'id': 25,
  'auth_user_id': 's1',
  'business_name': 'Ammiel Uniforms',
  'status': 'approved',
  'is_active': true,
  'city': 'Harare',
  'offers_delivery': true,
  'delivery_area': 'Harare',
  'payment_methods': 'EcoCash, cash',
  'rating': 4.7,
  'rating_count': 12,
  'terms_accepted_at': '2026-01-01T00:00:00Z',
};

final _shoe = {
  'id': 7,
  'seller_id': 's1',
  'seller_name': 'Ammiel Uniforms',
  'title': 'Pathfinder drill shoes',
  'description': 'Black leather drill shoes for Pathfinder and AY parades.',
  'price': 35,
  'price_currency': 'USD',
  'category': 'clothing',
  'condition': 'new',
  'status': 'available',
  'image_urls': ['fixture://shoe_red.jpg'],
  'stock_quantity': 6,
  'option_groups': [
    {
      'name': 'Shoe size',
      'values': ['38', '39', '40', '41', '42', '43'],
    },
  ],
  'specs': [
    {'label': 'Material', 'value': 'Genuine leather'},
    {'label': 'Sole', 'value': 'Rubber, non-slip'},
    {'label': 'Care', 'value': 'Polish weekly'},
  ],
  'country': 'ZW',
  'province': 'Harare',
  'created_at': '2026-10-20T00:00:00Z',
};

final _variants = [
  for (final (i, size, stock) in [
    (0, '38', 0),
    (1, '39', 2),
    (2, '40', 3),
    (3, '41', 1),
    (4, '42', 0),
    (5, '43', 0),
  ])
    {
      'id': 70 + i,
      'product_id': 7,
      'label': size,
      'options': {'Shoe size': size},
      'stock': stock,
      'price': size == '43' ? 38 : null,
      'sort': i,
      'is_active': true,
    },
];

void main() {
  setUpAll(() async {
    await loadShotFonts();
    ProductImageSource.debugOverride = (url) =>
        FileImage(File('$_fx/${url.replaceFirst('fixture://', '')}'));
    await initFakeSupabase((req) {
      final path = req.url.path;
      if (path.endsWith('/product_variants')) return _variants;
      if (path.endsWith('/sellers')) return [_seller];
      if (path.endsWith('/products')) return [_shoe];
      return const <Object>[];
    });
    await signInFake('buyer');
  });

  testWidgets('product with sizes', (t) async {
    await pumpShot(
      t,
      const ProductDetailsScreen(productId: '7'),
      dark: false,
    );
    await saveShot(t, 'opt_product');
    await t.tap(find.text('40'));
    await t.drag(find.byType(Scrollable).first, const Offset(0, -420));
    await saveShot(t, 'opt_product_picked');
    await t.drag(find.byType(Scrollable).first, const Offset(0, -500));
    await saveShot(t, 'opt_product_specs');
  });

  testWidgets('seller form', (t) async {
    await signInFake('s1');
    await pumpShot(
      t,
      AddProductScreen(
        initialProduct: Product.fromJson({..._shoe, 'image_urls': []}),
      ),
      dark: false,
      size: const Size(412, 2600),
    );
    await saveShot(t, 'opt_form');
  });
}
