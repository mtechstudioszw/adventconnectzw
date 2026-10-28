// Marketplace ranking (brief §11): deterministic per day with controlled
// exploration, quality and recency count, sellers are spread out, and
// paid/featured placement is not part of the organic order.

import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/models/product_model.dart';
import 'package:advent_connect_zw/services/market_ranking.dart';

final _now = DateTime(2026, 10, 28, 12);

Product _p(
  String id, {
  String seller = 's1',
  int daysOld = 1,
  int photos = 1,
  String desc = '',
  double price = 10,
  bool featured = false,
  String? category,
}) => Product(
  id: id,
  sellerId: seller,
  sellerName: 'Shop $seller',
  title: 'Item $id',
  price: price,
  imageUrls: [for (var i = 0; i < photos; i++) 'https://x/$id/$i.jpg'],
  createdAt: _now.subtract(Duration(days: daysOld)),
  description: desc,
  isFeatured: featured,
  category: category,
);

void main() {
  test('same viewer, same day → same order (no reshuffle on refresh)', () {
    final items = [for (var i = 0; i < 20; i++) _p('$i', seller: 's${i % 5}')];
    final a = MarketRanking.rank(items, now: _now, viewer: 'v');
    final b = MarketRanking.rank(
      items.reversed.toList(),
      now: _now,
      viewer: 'v',
    );
    expect(a.map((p) => p.id), b.map((p) => p.id));
  });

  test('a new day gives other listings a turn', () {
    final items = [
      for (var i = 0; i < 30; i++) _p('$i', seller: 's$i', daysOld: 3),
    ];
    final today = MarketRanking.rank(items, now: _now, viewer: 'v');
    final tomorrow = MarketRanking.rank(
      items,
      now: _now.add(const Duration(days: 1)),
      viewer: 'v',
    );
    expect(today.map((p) => p.id), isNot(tomorrow.map((p) => p.id)));
  });

  test('a complete, fresh listing beats a stale one with no photo', () {
    final good = _p('good', photos: 3, desc: 'x' * 80, daysOld: 1);
    final poor = _p('poor', seller: 's2', photos: 0, price: 0, daysOld: 40);
    final ranked = MarketRanking.rank([poor, good], now: _now, viewer: 'v');
    expect(ranked.first.id, 'good');
  });

  test('featured is not boosted in the organic order', () {
    final plain = _p('a', photos: 3, desc: 'x' * 80);
    final featured = _p(
      'b',
      seller: 's2',
      photos: 3,
      desc: 'x' * 80,
      featured: true,
    );
    expect(
      MarketRanking.score(plain, now: _now, viewer: 'v') -
          MarketRanking.dailySeed('a', 'v', _now) * 0.10,
      closeTo(
        MarketRanking.score(featured, now: _now, viewer: 'v') -
            MarketRanking.dailySeed('b', 'v', _now) * 0.10,
        1e-9,
      ),
    );
  });

  test('new sellers get a fair first look', () {
    final p = _p('n', seller: 'new');
    final base = MarketRanking.score(p, now: _now, viewer: 'v');
    final boosted = MarketRanking.score(
      p,
      now: _now,
      viewer: 'v',
      newSellerIds: {'new'},
    );
    expect(boosted, greaterThan(base));
  });

  test('one shop never fills more than two slots in a row', () {
    final items = [
      for (var i = 0; i < 6; i++)
        _p('big$i', seller: 'big', photos: 3, desc: 'x' * 80),
      _p('small1', seller: 'small', photos: 0, daysOld: 20),
      _p('small2', seller: 'other', photos: 0, daysOld: 20),
    ];
    final ranked = MarketRanking.rank(items, now: _now, viewer: 'v');
    for (var i = 2; i < 5; i++) {
      final run = {
        ranked[i - 2].sellerId,
        ranked[i - 1].sellerId,
        ranked[i].sellerId,
      };
      expect(run.length, greaterThan(1), reason: 'at $i');
    }
  });

  test('price and newest sorts do what they say', () {
    final items = [
      _p('a', price: 30, daysOld: 5),
      _p('b', price: 10, daysOld: 1),
      _p('c', price: 20, daysOld: 9),
    ];
    expect(
      MarketRanking.rank(
        items,
        sort: MarketSort.priceLow,
        now: _now,
      ).map((p) => p.id),
      ['b', 'c', 'a'],
    );
    expect(
      MarketRanking.rank(
        items,
        sort: MarketSort.priceHigh,
        now: _now,
      ).map((p) => p.id),
      ['a', 'c', 'b'],
    );
    expect(
      MarketRanking.rank(
        items,
        sort: MarketSort.newest,
        now: _now,
      ).map((p) => p.id),
      ['b', 'a', 'c'],
    );
  });

  test('filter count ignores sort', () {
    expect(const MarketFilters(sort: MarketSort.priceLow).activeCount, 0);
    expect(const MarketFilters(minPrice: 5, condition: 'new').activeCount, 2);
  });
}
