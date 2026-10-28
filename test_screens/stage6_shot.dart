// Render harness, not shipped: seeds PhotoTint like a test does.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/screens/marketplace/cart_screen.dart';
import 'package:advent_connect_zw/screens/marketplace/product_details_screen.dart';
import 'package:advent_connect_zw/screens/seller/seller_profile_screen.dart';

import '../test/helpers/fake_supabase.dart';
import 'package:advent_connect_zw/models/product_model.dart';
import 'package:advent_connect_zw/services/cart_service.dart';
import 'package:advent_connect_zw/utils/photo_tint.dart';
import 'shot.dart';

final _seller = {
  'id': 25,
  'auth_user_id': 's1',
  'business_name': 'Theopath Healthcare',
  'description': 'Natural remedies and health products, Harare.',
  'category': 'health',
  'country': 'ZW',
  'city': 'Harare',
  'province': 'Harare',
  'status': 'approved',
  'is_active': true,
  'phone': '+263771234567',
  'whatsapp': '+263771234567',
  'offers_delivery': true,
  'delivery_area': 'Harare CBD and suburbs',
  'delivery_fee': 'USD 3',
  'payment_methods': 'EcoCash, cash on collection',
  'observes_sabbath': true,
  'rating': 4.6,
  'rating_count': 5,
  'approved_at': '2026-10-01T00:00:00Z',
};

Map<String, Object?> _p(int id, String title, num price) => {
  'id': id,
  'seller_id': 's1',
  'title': title,
  'description':
      'Locally sourced. 60 capsules per bottle. Store in a cool dry place.',
  'price': price,
  'price_currency': 'USD',
  'category': 'health',
  'condition': 'new',
  'status': 'available',
  'country': 'ZW',
  'location': 'Harare',
  'province': 'Harare',
  'image_urls': [
    'https://example.com/$id.jpg',
    'https://example.com/$id-b.jpg',
  ],
  'created_at': '2026-10-20T00:00:00Z',
};

void main() {
  setUpAll(() async {
    await loadShotFonts();
    // What a warm-coloured product photo would give.
    PhotoTint.debugSeed('https://example.com/21.jpg', const Color(0xFFD08A3A));
    await initFakeSupabase((req) {
      final path = req.url.path;
      final single = (req.headers['Accept'] ?? '').contains('vnd.pgrst.object');
      if (path.endsWith('/sellers')) return single ? _seller : [_seller];
      if (path.endsWith('/seller_ratings')) return [];
      if (path.endsWith('/products')) {
        final rows = [
          _p(21, 'Vernonia Amygdalina Capsules', 10),
          _p(22, 'Harpagophytum Capsules', 12),
          _p(35, 'Neem Capsules', 9),
        ];
        final id = req.url.queryParameters['id'];
        if (id != null) {
          return rows.where((r) => 'eq.${r['id']}' == id).toList();
        }
        return single ? rows.first : rows;
      }
      return null;
    });
  });

  testWidgets('product', (t) async {
    await pumpShot(t, const ProductDetailsScreen(productId: '21'));
    await saveShot(t, 'product');
  });

  testWidgets('product full', (t) async {
    await pumpShot(
      t,
      const ProductDetailsScreen(productId: '21'),
      size: const Size(412, 2000),
    );
    await saveShot(t, 'product_full');
  });

  testWidgets('product scrolled', (t) async {
    await pumpShot(t, const ProductDetailsScreen(productId: '21'));
    await saveShot(t, 'product_top');
    await t.drag(find.byType(Scrollable).first, const Offset(0, -560));
    await saveShot(t, 'product_scrolled');
  });

  testWidgets('product contact + in basket', (t) async {
    await pumpShot(t, const ProductDetailsScreen(productId: '21'));
    await saveShot(t, 'product_pre');
    await t.tap(find.text('Add to basket'));
    await saveShot(t, 'product_in_basket');
    await t.tap(find.text('Chat'));
    await saveShot(t, 'product_contact');
  });

  testWidgets('product light', (t) async {
    await pumpShot(
      t,
      const ProductDetailsScreen(productId: '21'),
      size: const Size(412, 2000),
      dark: false,
    );
    await saveShot(t, 'product_full_light');
  });

  testWidgets('product narrow', (t) async {
    await pumpShot(
      t,
      const ProductDetailsScreen(productId: '21'),
      size: const Size(360, 760),
    );
    await saveShot(t, 'product_narrow');
  });

  testWidgets('storefront', (t) async {
    await pumpShot(t, const SellerProfileScreen(authUserId: 's1'));
    await saveShot(t, 'storefront');
  });

  testWidgets('cart', (t) async {
    await pumpShot(t, const CartScreen());
    await saveShot(t, 'cart_empty');
  });

  testWidgets('cart with items', (t) async {
    await t.runAsync(() async {
      await CartService.add(
        Product.fromJson({
          ..._p(21, 'Vernonia Amygdalina Capsules', 10),
          'seller_name': 'Theopath Healthcare',
        }),
        qty: 2,
      );
      await CartService.add(
        Product.fromJson({
          ..._p(41, 'Pathfinder Uniform — full set', 45),
          'seller_id': 's2',
          'seller_name': 'Ammiel Uniforms',
        }),
      );
    });
    await pumpShot(t, const CartScreen());
    await saveShot(t, 'cart');
  });
}
