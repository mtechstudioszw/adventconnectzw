// Renders the real storefront against stand-in logos/covers (test_screens/
// fixtures — generated, NOT real shops). Not part of the test suite.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/marketplace/product_image_source.dart';
import 'package:advent_connect_zw/screens/seller/seller_profile_screen.dart';

import '../test/helpers/fake_supabase.dart';
import 'shot.dart';

const _fx = 'test_screens/fixtures';

Map<String, Object?> _shop(
  String id,
  String name,
  String category, {
  String? logo,
  String? cover,
  int ratings = 0,
  bool delivery = true,
  String? desc,
}) => {
  'id': id.hashCode.abs(),
  'auth_user_id': id,
  'business_name': name,
  'category': category,
  'description':
      desc ??
      'Family business in Harare. Orders by WhatsApp; collection in the '
          'CBD or delivery around town.',
  'city': 'Harare',
  'province': 'Harare',
  'country': 'ZW',
  'status': 'approved',
  'is_active': true,
  'phone': '+263771234567',
  'whatsapp': '+263771234567',
  'offers_delivery': delivery,
  'delivery_area': 'Harare CBD and suburbs',
  'payment_methods': 'EcoCash, cash',
  'observes_sabbath': true,
  'rating': ratings > 0 ? 4.6 : 0,
  'rating_count': ratings,
  'profile_photo_url': logo == null ? null : 'fixture://$logo',
  'cover_photo_url': cover == null ? null : 'fixture://$cover',
  'created_at': '2025-06-01T00:00:00Z',
};

final _shops = {
  'herbal': _shop(
    'herbal',
    'Theopath Healthcare',
    'other',
    logo: 'logo_herbal.jpg',
    ratings: 5,
  ),
  'suits': _shop('suits', 'TheSuitKings', 'clothing', logo: 'logo_suits.jpg'),
  'crafts': _shop(
    'crafts',
    'Nations Crafts & Art',
    'crafts',
    logo: 'logo_crafts.jpg',
    ratings: 2,
    delivery: false,
  ),
  'bakery': _shop(
    'bakery',
    'Grace Bakery',
    'food',
    logo: 'logo_crafts.jpg',
    cover: 'cover_bakery.jpg',
    ratings: 12,
  ),
  'plain': _shop('plain', 'Ammiel Uniforms', 'clothing'),
};

Map<String, Object?> _p(int id, String seller, String title, num price) => {
  'id': id,
  'seller_id': seller,
  'title': title,
  'price': price,
  'status': 'available',
  'image_urls': [],
  'created_at': '2026-10-20T00:00:00Z',
};

void main() {
  setUpAll(() async {
    await loadShotFonts();
    ProductImageSource.debugOverride = (url) =>
        FileImage(File('$_fx/${url.replaceFirst('fixture://', '')}'));
    await initFakeSupabase((req) {
      final path = req.url.path;
      final q = req.url.queryParameters;
      final single = (req.headers['Accept'] ?? '').contains('vnd.pgrst.object');
      if (path.endsWith('/sellers')) {
        final id = (q['auth_user_id'] ?? 'eq.herbal').substring(3);
        final row = _shops[id];
        if (row == null) return single ? null : [];
        return single ? row : [row];
      }
      if (path.endsWith('/products')) {
        final id = (q['seller_id'] ?? 'eq.herbal').substring(3);
        return [
          _p(1, id, 'Featured item one', 10),
          _p(2, id, 'Second item with a longer name', 24),
          _p(3, id, 'Third item', 8),
          _p(4, id, 'Fourth item', 15),
        ];
      }
      if (path.endsWith('/seller_ratings')) return [];
      return null;
    });
  });

  for (final id in _shops.keys) {
    testWidgets('store $id', (t) async {
      await pumpShot(t, SellerProfileScreen(authUserId: id), dark: false);
      await saveShot(t, 'sf_${id}_light', rounds: 14);
    });
  }
  for (final id in ['herbal', 'suits']) {
    testWidgets('store $id dark', (t) async {
      await pumpShot(t, SellerProfileScreen(authUserId: id));
      await saveShot(t, 'sf_${id}_dark', rounds: 14);
    });
  }
  testWidgets('store herbal narrow', (t) async {
    await pumpShot(
      t,
      const SellerProfileScreen(authUserId: 'herbal'),
      size: const Size(360, 740),
      dark: false,
    );
    await saveShot(t, 'sf_herbal_narrow', rounds: 14);
  });
  testWidgets('store herbal scrolled', (t) async {
    await pumpShot(
      t,
      const SellerProfileScreen(authUserId: 'herbal'),
      dark: false,
    );
    await saveShot(t, 'sf_pre', rounds: 10);
    await t.drag(find.byType(Scrollable).first, const Offset(0, -700));
    await saveShot(t, 'sf_herbal_scrolled', rounds: 8);
  });
}
