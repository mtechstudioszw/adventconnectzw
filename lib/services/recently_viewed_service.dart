import 'dart:convert';

import 'package:flutter/foundation.dart' show ValueNotifier;

import '../models/product_model.dart';
import 'cache_service.dart';

/// Listings this member opened recently, newest first, on this device.
///
/// User-scoped on purpose: the key has no `pref:` prefix, so sign-out
/// clears it (CLAUDE.md) — the next person on a shared phone doesn't see
/// what the last one browsed. Stored as the product rows themselves so the
/// rail paints offline; the marketplace drops any that are no longer for
/// sale before showing them.
class RecentlyViewedService {
  RecentlyViewedService._();

  static const _key = 'market_recently_viewed_v1';
  static const max = 12;

  static final ValueNotifier<List<Product>> items = ValueNotifier(const []);

  static void load() {
    try {
      final raw = CacheService.readStringStale(_key);
      if (raw == null) {
        items.value = const [];
        return;
      }
      items.value = [
        for (final e in jsonDecode(raw) as List)
          Product.fromJson(e as Map<String, dynamic>),
      ];
    } catch (_) {
      items.value = const [];
    }
  }

  static Future<void> add(Product p) async {
    final next = [
      p,
      ...items.value.where((x) => x.id != p.id),
    ].take(max).toList();
    items.value = next;
    try {
      await CacheService.writeString(
        _key,
        jsonEncode([for (final x in next) x.toJson()]),
      );
    } catch (_) {}
  }

  /// Categories the member has been looking at — a light "Recommended"
  /// signal that never leaves the device.
  static Set<String> get interestCategories => {
    for (final p in items.value.take(6))
      if ((p.category ?? '').isNotEmpty) p.category!,
  };
}
