// patch_280: sizes/colours, stock and specifications.
// - Every combination of up to two option groups, labelled "M / Black".
// - The basket keeps an M and an L of one shirt as two lines, caps a line
//   at the stock the seller counted, and sends the option to checkout.
// - Checkout's own words (only 2 left, choose a size) reach the buyer.
// - The product page won't add a product with options until one is
//   chosen, uses that option's own price, and won't offer a sold-out size.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:advent_connect_zw/models/cart_item_model.dart';
import 'package:advent_connect_zw/models/product_model.dart';
import 'package:advent_connect_zw/screens/marketplace/product_details_screen.dart';
import 'package:advent_connect_zw/services/cart_service.dart';
import 'package:advent_connect_zw/services/order_service.dart';
import 'package:advent_connect_zw/theme/app_theme.dart';
import 'package:advent_connect_zw/widgets/marketplace/product_options_editor.dart';

import 'helpers/fake_supabase.dart';

Product _shirt({int? stock}) => Product.fromJson({
  'id': 7,
  'seller_id': 's1',
  'title': 'Pathfinder shirt',
  'price': 20,
  'status': 'available',
  'image_urls': [],
  'stock_quantity': stock,
  'option_groups': [
    {
      'name': 'Size',
      'values': ['M', 'L'],
    },
  ],
  'specs': [
    {'label': 'Material', 'value': 'Cotton'},
  ],
  'created_at': '2026-10-20T00:00:00Z',
});

const _m = ProductVariant(
  id: '71',
  label: 'M',
  options: {'Size': 'M'},
  stock: 2,
  price: 25,
);
const _l = ProductVariant(
  id: '72',
  label: 'L',
  options: {'Size': 'L'},
  stock: 0,
);

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

  setUp(CartService.resetForTest);

  test('combinations of two groups, in order', () {
    final combos = ProductVariant.combinations(const [
      ProductOptionGroup(name: 'Size', values: ['S', 'M']),
      ProductOptionGroup(name: 'Colour', values: ['Black', 'Navy']),
    ]);
    expect(combos.map((c) => c.label), [
      'S / Black',
      'S / Navy',
      'M / Black',
      'M / Navy',
    ]);
    expect(combos[3].options, {'Size': 'M', 'Colour': 'Navy'});
  });

  test('product reads options, specs and stock', () {
    final p = _shirt(stock: 3);
    expect(p.hasOptions, isTrue);
    expect(p.optionGroups.single.values, ['M', 'L']);
    expect(p.specs.single.label, 'Material');
    expect(p.isLowStock, isTrue);
    expect(_shirt(stock: 0).isSoldOut, isTrue);
    expect(_shirt().stockQuantity, isNull);
    // Survives the offline cache.
    expect(Product.fromJson(p.toJson()).optionGroups.single.name, 'Size');
  });

  test(
    'two sizes are two lines; stock caps the line; option goes to checkout',
    () async {
      final shirt = _shirt(stock: 2);
      await CartService.add(shirt, variant: _m, qty: 5);
      await CartService.add(shirt, variant: _l.copyWith(stock: 4));
      expect(CartService.items, hasLength(2));
      final m = CartService.lineFor('7#71')!;
      expect(m.qty, 2, reason: 'only 2 M in stock');
      expect(m.price, 25, reason: 'M has its own price');
      expect(m.variantLabel, 'M');
      await CartService.setQty('7#71', 9);
      expect(CartService.lineFor('7#71')!.qty, 2);
      final rpc = CartService.baskets.single.toRpcItems();
      expect(rpc.first, {'product_id': 7, 'qty': 2, 'variant_id': 71});
      // The basket survives restart with the option.
      expect(CartItem.fromJson(m.toJson()).variantId, '71');
    },
  );

  test("checkout's reasons reach the buyer", () {
    expect(
      OrderService.reasonFor(
        const PostgrestException(
          message: 'OUT_OF_STOCK: only 2 left of Pathfinder shirt (M)',
        ),
      ),
      'Only 2 left of Pathfinder shirt (M)',
    );
    expect(
      OrderService.reasonFor(
        const PostgrestException(
          message:
              'CHOOSE_OPTION: choose a size or option for Pathfinder shirt',
        ),
      ),
      'Choose a size or option for Pathfinder shirt',
    );
    expect(OrderService.reasonFor(Exception('network')), isNull);
  });

  test('the seller form refuses missing stock and too many combinations', () {
    final c = ProductOptionsController()
      ..setCountStock(true)
      ..addGroup('Size', ['S', 'M']);
    expect(c.validate(), contains('stock for S'));
    final big = ProductOptionsController()
      ..addGroup('Size', [for (var i = 0; i < 12; i++) 'S$i'])
      ..addGroup('Colour', ['A', 'B', 'C', 'D', 'E']);
    expect(big.validate(), contains('60 combinations'));
    c.dispose();
    big.dispose();
  });

  testWidgets('product page: choose a size, its price, sold-out size refused', (
    t,
  ) async {
    setFakeSupabaseHandler((req) {
      final path = req.url.path;
      if (path.endsWith('/product_variants')) {
        return [
          {
            'id': 71,
            'product_id': 7,
            'label': 'M',
            'options': {'Size': 'M'},
            'stock': 2,
            'price': 25,
            'sort': 0,
            'is_active': true,
          },
          {
            'id': 72,
            'product_id': 7,
            'label': 'L',
            'options': {'Size': 'L'},
            'stock': 0,
            'sort': 1,
            'is_active': true,
          },
        ];
      }
      if (path.endsWith('/products')) {
        final row = _shirt(stock: 2).toJson()..['price_currency'] = 'USD';
        return [row];
      }
      return const <Object>[];
    });
    t.view.physicalSize = const Size(412, 2600);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const ProductDetailsScreen(productId: '7'),
      ),
    );
    await _settle(t);
    expect(t.takeException(), isNull);

    expect(find.text('Choose a size'), findsOneWidget);
    expect(find.text('Specifications'), findsOneWidget);
    expect(find.text('Cotton'), findsOneWidget);

    // L is sold out: tapping it picks nothing.
    await t.tap(find.text('L'));
    await _settle(t);
    expect(find.text('Choose a size'), findsOneWidget);

    await t.tap(find.text('M'));
    await _settle(t);
    expect(find.text('Only 2 left'), findsOneWidget);
    expect(find.text('Add to basket'), findsOneWidget);
    await t.tap(find.text('Add to basket'));
    await _settle(t);
    final line = CartService.lineFor('7#71');
    expect(line, isNotNull);
    expect(line!.price, 25);
    await t.pump(const Duration(seconds: 2));
  });
}
