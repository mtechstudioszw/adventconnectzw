import 'package:flutter_test/flutter_test.dart';
import 'package:advent_connect_zw/models/cart_item_model.dart';
import 'package:advent_connect_zw/models/product_model.dart';
import 'package:advent_connect_zw/services/cart_service.dart';

/// CacheService's Hive box is never opened in tests, so its read/write
/// helpers no-op and the basket stays purely in-memory. That's exactly
/// what we want here — this exercises the grouping and quantity rules,
/// not persistence.
Product _product({
  required String id,
  required String sellerId,
  String sellerName = 'Test Store',
  double price = 10,
  String currency = 'USD',
}) => Product(
  id: id,
  sellerId: sellerId,
  sellerName: sellerName,
  title: 'Product $id',
  price: price,
  currency: currency,
  imageUrls: const [],
  createdAt: DateTime(2026, 1, 1),
);

void main() {
  setUp(CartService.resetForTest);

  group('CartService', () {
    test('adding the same product twice bumps quantity, not lines', () async {
      await CartService.add(_product(id: '1', sellerId: 'seller-a'));
      await CartService.add(_product(id: '1', sellerId: 'seller-a'));

      expect(CartService.items.length, 1);
      expect(CartService.items.first.qty, 2);
      expect(CartService.count, 2);
    });

    test('count is units, sellerCount is distinct shops', () async {
      await CartService.add(_product(id: '1', sellerId: 'seller-a'), qty: 3);
      await CartService.add(_product(id: '2', sellerId: 'seller-b'));

      expect(CartService.count, 4);
      expect(CartService.sellerCount, 2);
    });

    test('quantity is clamped to the DB check constraint', () async {
      await CartService.add(_product(id: '1', sellerId: 'seller-a'), qty: 500);
      expect(CartService.items.first.qty, CartItem.maxQty);

      await CartService.setQty('1', 1000);
      expect(CartService.items.first.qty, CartItem.maxQty);
    });

    test('setQty to zero removes the line', () async {
      await CartService.add(_product(id: '1', sellerId: 'seller-a'));
      await CartService.setQty('1', 0);
      expect(CartService.isEmpty, isTrue);
    });

    test('a basket spanning two sellers splits into two orders', () async {
      await CartService.add(_product(id: '1', sellerId: 'seller-a'));
      await CartService.add(_product(id: '2', sellerId: 'seller-a'));
      await CartService.add(_product(id: '3', sellerId: 'seller-b'));

      final baskets = CartService.baskets;
      expect(baskets.length, 2);
      expect(baskets.firstWhere((b) => b.sellerId == 'seller-a').items.length, 2);
      expect(baskets.firstWhere((b) => b.sellerId == 'seller-b').items.length, 1);
    });

    test('one seller listing in two currencies splits into two orders', () async {
      await CartService.add(
        _product(id: '1', sellerId: 'seller-a', currency: 'USD'),
      );
      await CartService.add(
        _product(id: '2', sellerId: 'seller-a', currency: 'ZWL'),
      );

      // place_order rejects a mixed-currency order, so the split has to
      // happen here rather than failing at checkout.
      final baskets = CartService.baskets;
      expect(baskets.length, 2);
      expect(baskets.map((b) => b.currency).toSet(), {'USD', 'ZWL'});
    });

    test('subtotal multiplies price by quantity', () async {
      await CartService.add(
        _product(id: '1', sellerId: 'seller-a', price: 12.5),
        qty: 2,
      );
      await CartService.add(
        _product(id: '2', sellerId: 'seller-a', price: 5),
      );

      final basket = CartService.baskets.single;
      expect(basket.subtotal, 30.0);
      expect(basket.itemCount, 3);
      expect(basket.formatSubtotal(), r'$30');
    });

    test('removeBasket clears one shop and leaves the others', () async {
      await CartService.add(_product(id: '1', sellerId: 'seller-a'));
      await CartService.add(_product(id: '2', sellerId: 'seller-b'));

      final basketA = CartService.baskets.firstWhere(
        (b) => b.sellerId == 'seller-a',
      );
      await CartService.removeBasket(basketA);

      expect(CartService.sellerCount, 1);
      expect(CartService.items.single.sellerId, 'seller-b');
    });

    test('rpc payload carries only ids and quantities, never prices', () async {
      await CartService.add(
        _product(id: '7', sellerId: 'seller-a', price: 99),
        qty: 2,
      );

      final payload = CartService.baskets.single.toRpcItems();
      expect(payload, [
        {'product_id': 7, 'qty': 2},
      ]);
    });

    test('revision bumps so badges rebuild', () async {
      final before = CartService.revision.value;
      await CartService.add(_product(id: '1', sellerId: 'seller-a'));
      expect(CartService.revision.value, greaterThan(before));
    });
  });
}
