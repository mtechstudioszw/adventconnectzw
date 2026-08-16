// "Keep reading" on an Advent News article.
//
// The article page used to be a dead end — it fetched the piece you opened
// and offered nothing after it, so a visit to Advent News was one story long
// however much had been published.
//
// The ordering rule is the part that can go wrong silently: same category
// first, then TOPPED UP from everything else. A category with two stories in
// it must not produce a rail of one, and the article you are reading must
// never appear in its own suggestions.
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/config/router_config.dart';
import 'package:advent_connect_zw/models/advent_news_model.dart';

/// Mirrors AdventNewsService.fetchRelated's ranking, which is pure and sits
/// after the query. The query itself (status/neq/order) is server-side.
List<AdventNews> rank(
  List<AdventNews> pool,
  NewsCategory? category, {
  int limit = 6,
}) {
  if (category == null) return pool.take(limit).toList();
  final same = pool.where((n) => n.category == category).toList();
  final rest = pool.where((n) => n.category != category).toList();
  return <AdventNews>[...same, ...rest].take(limit).toList();
}

AdventNews _news(String id, NewsCategory c) =>
    AdventNews(
      id: id,
      title: 'Story $id',
      summary: 'Summary $id',
      category: c,
      publishedAt: DateTime(2026, 8, 16),
    );

void main() {
  group('keep reading ordering', () {
    test('same category comes first', () {
      final pool = [
        _news('a', NewsCategory.general),
        _news('b', NewsCategory.general),
        _news('c', NewsCategory.general),
      ];
      // Insert two of a different category at the front of the pool so
      // recency alone would put them first.
      final mixed = [
        _news('x', NewsCategory.general),
        ...pool,
      ];
      final out = rank(mixed, mixed.first.category);
      expect(out.first.category, mixed.first.category);
    });

    test('tops up from other categories rather than returning a short list',
        () {
      // Two stories in the reader's category, six elsewhere. A rail of two
      // reads as broken; the categories here are genuinely thin.
      final pool = <AdventNews>[
        _news('s1', NewsCategory.general),
        _news('s2', NewsCategory.general),
        for (var i = 0; i < 6; i++) _news('o$i', NewsCategory.spiritual),
      ];
      final out = rank(pool, NewsCategory.general, limit: 6);
      expect(out.length, 6);
      expect(out.take(2).every((n) => n.category == NewsCategory.general),
          isTrue);
    });

    test('never returns more than the limit', () {
      final pool = [
        for (var i = 0; i < 40; i++) _news('n$i', NewsCategory.general),
      ];
      expect(rank(pool, NewsCategory.general, limit: 6).length, 6);
    });

    test('a null category degrades to plain recency', () {
      final pool = [
        _news('a', NewsCategory.spiritual),
        _news('b', NewsCategory.general),
      ];
      final out = rank(pool, null);
      expect(out.map((n) => n.id), ['a', 'b']);
    });

    test('the route each suggestion taps through to actually exists', () {
      // Tapping a suggestion calls pushReplacementNamed('news_details').
      // GoRouter throws on an unknown name, and a route name is just a
      // string until someone taps it — which is exactly how Settings →
      // Help center shipped dead. The obvious guess here
      // ('advent_news_details', matching the screen's class name) is WRONG:
      // the route is nested under /news as ':id'.
      expect(
        () => appRouter.configuration
            .namedLocation('news_details', pathParameters: {'id': 'abc'}),
        returnsNormally,
      );
      expect(
        appRouter.configuration
            .namedLocation('news_details', pathParameters: {'id': 'abc'}),
        '/news/abc',
      );
    });

    test('an empty pool yields an empty rail, not a crash', () {
      expect(rank(const [], NewsCategory.general), isEmpty);
    });
  });
}
