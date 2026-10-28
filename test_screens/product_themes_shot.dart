// Renders the real product page against stand-in photos (test_screens/
// fixtures — generated, NOT real listings) so the adaptive theme engine
// runs on actual pixels. Not part of the test suite.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/marketplace/product_image_source.dart';
import 'package:advent_connect_zw/screens/marketplace/product_details_screen.dart';

import '../test/helpers/fake_supabase.dart';
import 'shot.dart';

const _fx = 'test_screens/fixtures';

final _seller = {
  'id': 25,
  'auth_user_id': 's1',
  'business_name': 'Theopath Healthcare',
  'status': 'approved',
  'is_active': true,
  'city': 'Harare',
  'phone': '+263771234567',
  'offers_delivery': true,
  'delivery_area': 'Harare CBD and suburbs',
  'delivery_fee': 'USD 3',
  'payment_methods': 'EcoCash, cash on collection',
  'observes_sabbath': true,
  'rating': 4.6,
  'rating_count': 5,
  'created_at': '2025-06-01T00:00:00Z',
};

Map<String, Object?> _p(
  int id,
  String title, {
  required String category,
  String? sub,
  num price = 10,
  String? image,
  String status = 'available',
  String? desc,
  String condition = 'new',
}) => {
  'id': id,
  'seller_id': 's1',
  'title': title,
  'description':
      desc ??
      'Carefully packed and ready to collect. Ask the shop about bulk '
          'orders and delivery to your area.',
  'price': price,
  'price_currency': 'USD',
  'category': category,
  'subcategory': sub,
  'condition': condition,
  'status': status,
  'country': 'ZW',
  'location': 'Harare',
  'image_urls': image == null ? [] : ['fixture://$image'],
  'created_at': '2026-10-20T00:00:00Z',
};

final _products = <Map<String, Object?>>[
  _p(
    1,
    'Vernonia Amygdalina Capsules',
    category: 'other',
    sub: 'Health and Wellness',
    image: 'herbal_white.jpg',
  ),
  _p(
    2,
    'The Last Generation Theology',
    category: 'books',
    price: 12.5,
    image: 'book_desk.jpg',
  ),
  _p(
    3,
    'Two-piece Navy Suit',
    category: 'clothing',
    price: 54,
    image: 'suit_dark.jpg',
  ),
  _p(
    4,
    'Trail Running Shoes',
    category: 'clothing',
    price: 65,
    image: 'shoe_red.jpg',
  ),
  _p(
    5,
    'Silver 14" Laptop',
    category: 'electronics',
    price: 420,
    image: 'laptop_silver.jpg',
    condition: 'like_new',
  ),
  _p(
    6,
    'Three-seater Fabric Sofa',
    category: 'furniture',
    price: 380,
    image: 'sofa_room.jpg',
    condition: 'good',
  ),
  _p(
    7,
    'Natural Remedies Offer',
    category: 'other',
    image: 'poster_orange.jpg',
  ),
  _p(8, 'Hand-made Church Bulletin Holder', category: 'other', price: 6),
  _p(9, 'Broken Photo Listing', category: 'other', image: 'does_not_exist.jpg'),
  _p(
    10,
    'Pathfinder Uniform Complete Set with Sash, Scarf, Woggle and Badges — Junior Sizes',
    category: 'clothing',
    price: 45,
    image: 'suit_dark.jpg',
    status: 'sold',
    desc: List.filled(
      8,
      'Complete uniform set in excellent condition, worn twice for investiture.',
    ).join(' '),
  ),
];

void main() {
  setUpAll(() async {
    await loadShotFonts();
    ProductImageSource.debugOverride = (url) =>
        FileImage(File('$_fx/${url.replaceFirst('fixture://', '')}'));
    await initFakeSupabase((req) {
      final path = req.url.path;
      if (path.endsWith('/sellers')) return [_seller];
      if (path.endsWith('/products')) {
        final id = req.url.queryParameters['id'];
        if (id != null) {
          return _products.where((r) => 'eq.${r['id']}' == id).toList();
        }
        return _products.take(3).toList();
      }
      return null;
    });
  });

  for (final row in _products) {
    final id = row['id'].toString();
    testWidgets('product $id', (t) async {
      await pumpShot(t, ProductDetailsScreen(productId: id), dark: false);
      await saveShot(t, 'pt_${id}_light', rounds: 14);
    });
  }

  for (final id in ['1', '3', '5']) {
    testWidgets('product $id dark', (t) async {
      await pumpShot(t, ProductDetailsScreen(productId: id));
      await saveShot(t, 'pt_${id}_dark', rounds: 14);
    });
  }

  testWidgets('product 1 narrow', (t) async {
    await pumpShot(
      t,
      const ProductDetailsScreen(productId: '1'),
      size: const Size(360, 740),
      dark: false,
    );
    await saveShot(t, 'pt_1_narrow', rounds: 14);
  });
}
