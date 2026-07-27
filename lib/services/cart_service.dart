import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/cart_item_model.dart';
import '../models/product_model.dart';
import 'cache_service.dart';

/// The basket. Device-local by design.
///
/// Nothing here touches the network: adding to the basket is instant,
/// works with no signal, and creates no server rows to secure or moderate.
/// Server rows appear only at checkout, when [OrderService] fans the
/// basket out into one order per seller.
///
/// Stored under a `pref:` key so it survives the 24h cache TTL — a basket
/// that silently emptied itself overnight would be worse than no basket.
class CartService {
  CartService._();

  static const _storageKey = 'pref:cart_v1';

  /// Bumped on every mutation so badges and the cart screen rebuild.
  /// Same static-ValueNotifier pattern the rest of the app uses.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static List<CartItem> _items = const [];
  static bool _loaded = false;

  /// Read the basket off disk. Cheap and synchronous after the Hive box
  /// is open, so screens can call it in `initState` without a spinner.
  static List<CartItem> get items {
    if (!_loaded) _load();
    return List.unmodifiable(_items);
  }

  static bool get isEmpty => items.isEmpty;

  /// Total units, not lines — a basket holding 3 of one product reads
  /// as "3" on the badge, which is what buyers expect.
  static int get count => items.fold(0, (sum, item) => sum + item.qty);

  static int get sellerCount => items.map((e) => e.sellerId).toSet().length;

  static void _load() {
    _loaded = true;
    try {
      final raw = CacheService.readPref(_storageKey);
      if (raw == null || raw.isEmpty) return;
      _items = (jsonDecode(raw) as List)
          .map((e) => CartItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      // A corrupt basket must never brick the marketplace tab.
      _items = const [];
    }
  }

  static Future<void> _persist() async {
    revision.value++;
    try {
      await CacheService.writePref(
        _storageKey,
        jsonEncode(_items.map((e) => e.toJson()).toList()),
      );
    } catch (_) {
      // Best-effort: the in-memory basket is still correct this session.
    }
  }

  /// Group the basket into checkout units — one per seller per currency.
  /// Insertion order is preserved so the list doesn't reshuffle as items
  /// are added.
  static List<SellerBasket> get baskets {
    final grouped = <String, List<CartItem>>{};
    for (final item in items) {
      grouped.putIfAbsent('${item.sellerId}|${item.currency}', () => []).add(item);
    }
    return grouped.values.map((lines) {
      final first = lines.first;
      return SellerBasket(
        sellerId: first.sellerId,
        sellerName: first.sellerName,
        sellerPhone: first.sellerPhone,
        currency: first.currency,
        items: lines,
      );
    }).toList();
  }

  static CartItem? lineFor(String productId) {
    for (final item in items) {
      if (item.productId == productId) return item;
    }
    return null;
  }

  static bool contains(String productId) => lineFor(productId) != null;

  /// Add a product, or bump its quantity if it's already in the basket.
  /// Returns the resulting quantity so the caller can confirm ("2 in
  /// basket") without re-reading.
  static Future<int> add(Product product, {int qty = 1}) async {
    final existing = lineFor(product.id);
    final next = <CartItem>[..._items];
    int resulting;
    if (existing == null) {
      resulting = qty.clamp(1, CartItem.maxQty);
      next.add(CartItem.fromProduct(product, qty: resulting));
    } else {
      resulting = (existing.qty + qty).clamp(1, CartItem.maxQty);
      final index = next.indexWhere((e) => e.productId == product.id);
      next[index] = existing.copyWith(qty: resulting);
    }
    _items = next;
    await _persist();
    return resulting;
  }

  static Future<void> setQty(String productId, int qty) async {
    if (qty <= 0) return remove(productId);
    final index = _items.indexWhere((e) => e.productId == productId);
    if (index == -1) return;
    final next = <CartItem>[..._items];
    next[index] = next[index].copyWith(qty: qty.clamp(1, CartItem.maxQty));
    _items = next;
    await _persist();
  }

  static Future<void> remove(String productId) async {
    _items = _items.where((e) => e.productId != productId).toList();
    await _persist();
  }

  /// Drop every line in one checkout unit — called once that unit's order
  /// is placed, so a multi-shop basket empties one shop at a time and a
  /// failure partway through leaves the unplaced shops intact.
  static Future<void> removeBasket(SellerBasket basket) async {
    _items = _items
        .where(
          (e) =>
              e.sellerId != basket.sellerId || e.currency != basket.currency,
        )
        .toList();
    await _persist();
  }

  static Future<void> clear() async {
    _items = const [];
    await _persist();
  }

  /// Called on sign-out. The basket is personal, and `clearUserData`
  /// deliberately preserves `pref:` keys, so it has to be cleared by name.
  static Future<void> clearOnSignOut() async {
    _items = const [];
    _loaded = false;
    revision.value++;
    try {
      await CacheService.deletePref(_storageKey);
    } catch (_) {}
  }

  @visibleForTesting
  static void resetForTest() {
    _items = const [];
    _loaded = true;
    revision.value = 0;
  }
}
