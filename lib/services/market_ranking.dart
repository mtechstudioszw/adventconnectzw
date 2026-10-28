import 'dart:math' as math;

import '../models/product_model.dart';

/// How the results grid is ordered.
enum MarketSort { best, newest, priceLow, priceHigh }

extension MarketSortX on MarketSort {
  String get label => switch (this) {
    MarketSort.best => 'Best match',
    MarketSort.newest => 'Newest',
    MarketSort.priceLow => 'Price: low to high',
    MarketSort.priceHigh => 'Price: high to low',
  };
}

/// Filters the buyer chose. Applied on the server (see
/// MarketplaceService.fetchProducts) so they narrow the query rather than
/// a page that's already been fetched.
class MarketFilters {
  const MarketFilters({
    this.minPrice,
    this.maxPrice,
    this.condition,
    this.location,
    this.sellerId,
    this.sellerName,
    this.sort = MarketSort.best,
  });

  final double? minPrice;
  final double? maxPrice;

  /// A key of [Product.conditionLabels].
  final String? condition;

  /// Town / province text, matched loosely.
  final String? location;
  final String? sellerId;

  /// For the chip label only.
  final String? sellerName;
  final MarketSort sort;

  /// How many filters are on (sort isn't a filter).
  int get activeCount => [
    minPrice != null || maxPrice != null,
    condition != null,
    (location ?? '').trim().isNotEmpty,
    sellerId != null,
  ].where((b) => b).length;

  bool get isEmpty => activeCount == 0;

  static const none = MarketFilters();

  MarketFilters copyWith({MarketSort? sort}) => MarketFilters(
    minPrice: minPrice,
    maxPrice: maxPrice,
    condition: condition,
    location: location,
    sellerId: sellerId,
    sellerName: sellerName,
    sort: sort ?? this.sort,
  );
}

/// The marketplace's organic ranking (redesign brief §11, "Marketplace
/// ranking"). Replaces `list.shuffle()`, which reordered the whole catalogue
/// on every refresh.
///
/// Deterministic with controlled exploration:
///   * The same viewer sees the same order all day; it moves once a day
///     (the [dailySeed] jitter), so fresh items get a turn without the grid
///     reshuffling under someone's thumb.
///   * Signals: recency, listing quality (photos, description, a price),
///     a measured seller rating only once it rests on enough reviews, the
///     viewer's own recent interest, and a boost for new sellers' first
///     weeks — the brief's "fair discovery for new sellers".
///   * Deliberately NOT: follower counts, sales volume or views. Those
///     reward whoever is already big.
///   * Paid placement isn't here at all. Featured items are shown in their
///     own labelled section, never mixed into this order.
class MarketRanking {
  MarketRanking._();

  static double recency(Product p, DateTime now) {
    final days = now.difference(p.createdAt).inHours / 24.0;
    // Halves every 10 days; never below zero.
    return math.pow(0.5, math.max(0, days) / 10).toDouble();
  }

  /// 0..1: what a buyer needs to decide, present or not.
  static double quality(Product p) {
    var q = 0.0;
    if (p.imageUrls.isNotEmpty) q += 0.4;
    if (p.imageUrls.length >= 3) q += 0.15;
    if ((p.description ?? '').trim().length >= 60) q += 0.25;
    if (p.price > 0) q += 0.2;
    return q;
  }

  /// Stable 0..1 per (listing, viewer, day).
  static double dailySeed(String productId, String viewer, DateTime now) {
    final key = '$productId|$viewer|${now.year}-${now.month}-${now.day}';
    // FNV-1a, so it's identical on every device and every run.
    var h = 0x811c9dc5;
    for (final c in key.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xffffffff;
    }
    return h / 0xffffffff;
  }

  static double score(
    Product p, {
    required DateTime now,
    required String viewer,
    Set<String> newSellerIds = const {},
    Map<String, double> sellerRatings = const {},
    Set<String> interestCategories = const {},
  }) {
    var s = 0.40 * recency(p, now) + 0.30 * quality(p);
    // New sellers' first weeks: a fair first look, capped so it can't
    // bury everyone else.
    if (newSellerIds.contains(p.sellerId)) s += 0.12;
    final rating = sellerRatings[p.sellerId];
    if (rating != null) s += 0.06 * ((rating - 3).clamp(0, 2) / 2);
    if (p.category != null && interestCategories.contains(p.category)) {
      s += 0.10;
    }
    s += 0.10 * dailySeed(p.id, viewer, now);
    return s;
  }

  /// Orders [products] for [sort]. For [MarketSort.best] it also spreads
  /// sellers out so one shop's ten listings can't fill the first screen.
  static List<Product> rank(
    List<Product> products, {
    MarketSort sort = MarketSort.best,
    required DateTime now,
    String viewer = '',
    Set<String> newSellerIds = const {},
    Map<String, double> sellerRatings = const {},
    Set<String> interestCategories = const {},
  }) {
    final list = [...products];
    switch (sort) {
      case MarketSort.newest:
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return list;
      case MarketSort.priceLow:
        list.sort((a, b) => a.price.compareTo(b.price));
        return list;
      case MarketSort.priceHigh:
        list.sort((a, b) => b.price.compareTo(a.price));
        return list;
      case MarketSort.best:
        final scores = {
          for (final p in list)
            p.id: score(
              p,
              now: now,
              viewer: viewer,
              newSellerIds: newSellerIds,
              sellerRatings: sellerRatings,
              interestCategories: interestCategories,
            ),
        };
        list.sort((a, b) {
          final c = scores[b.id]!.compareTo(scores[a.id]!);
          return c != 0 ? c : a.id.compareTo(b.id);
        });
        return spreadSellers(list);
    }
  }

  /// No more than two in a row from the same seller, keeping the ranked
  /// order otherwise. Falls back to the original order when every remaining
  /// item is from that seller.
  static List<Product> spreadSellers(List<Product> ranked) {
    final pending = [...ranked];
    final out = <Product>[];
    while (pending.isNotEmpty) {
      var pick = 0;
      if (out.length >= 2 &&
          out[out.length - 1].sellerId == out[out.length - 2].sellerId) {
        final run = out.last.sellerId;
        final alt = pending.indexWhere((p) => p.sellerId != run);
        if (alt != -1) pick = alt;
      }
      out.add(pending.removeAt(pick));
    }
    return out;
  }
}
