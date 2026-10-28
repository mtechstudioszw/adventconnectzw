// Marketplace filters and search run on the server, and search also
// matches shop names.

import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/services/market_ranking.dart';
import 'package:advent_connect_zw/services/marketplace_service.dart';

import 'helpers/fake_supabase.dart';

void main() {
  setUpAll(() async {
    await initFakeSupabase();
    await signInFake('me');
  });

  test('filters and search become query parameters', () async {
    Uri? productsUrl;
    setFakeSupabaseHandler((req) {
      if (req.url.path.endsWith('/sellers')) {
        return [
          {
            'auth_user_id': 'u-suits',
            'business_name': 'TheSuitKings',
            'approved_at': '2026-10-20T00:00:00Z',
            'rating': 4.5,
            'rating_count': 4,
          },
          {
            'auth_user_id': 'u-books',
            'business_name': 'Adventist Online Library',
            'approved_at': '2025-01-01T00:00:00Z',
            'rating': 5,
            'rating_count': 1,
          },
        ];
      }
      if (req.url.path.endsWith('/products')) {
        productsUrl = req.url;
        return [
          {
            'id': 1,
            'seller_id': 'u-suits',
            'title': 'Navy suit',
            'price': 80,
            'image_urls': [],
            'created_at': '2026-10-27T00:00:00Z',
          },
        ];
      }
      return null;
    });
    final catalog = await MarketplaceService.fetchCatalog(
      search: 'suit',
      country: 'ZW',
      filters: const MarketFilters(
        minPrice: 10,
        maxPrice: 100,
        condition: 'new',
        location: 'Harare',
      ),
    );
    final q = productsUrl!.query;
    expect(q, contains('price=gte.10'));
    expect(q, contains('price=lte.100'));
    expect(q, contains('condition=eq.new'));
    expect(q, contains('country=eq.ZW'));
    expect(Uri.decodeComponent(q), contains('location.ilike'));
    // The shop name matched, so its listings are folded into the search.
    expect(Uri.decodeComponent(q), contains('seller_id.in.(u-suits)'));
    expect(catalog.matchedSellerIds, {'u-suits'});
    expect(catalog.products.single.sellerName, 'TheSuitKings');
    // Approved 8 days ago → new; rating counts only with 3+ reviews.
    expect(catalog.newSellerIds, contains('u-suits'));
    expect(catalog.sellerRatings.keys, ['u-suits']);
  });
}
