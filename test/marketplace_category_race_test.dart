// Flicking between categories let a slower answer land last: tap Books,
// then Clothing, and the Books response filled the grid under the
// Clothing chip. Changing category also left the previous grid up, and
// if the load failed it stayed there with no error.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/screens/marketplace/marketplace_screen.dart';
import 'package:advent_connect_zw/theme/app_theme.dart';

import 'helpers/fake_supabase.dart';

Map<String, Object?> _product(int id, String title, String category) => {
  'id': id,
  'seller_id': 's1',
  'title': title,
  'price': 10,
  'category': category,
  'status': 'available',
  'country': 'ZW',
};

Future<void> _settle(WidgetTester t, {int rounds = 8}) async {
  for (var i = 0; i < rounds; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pump(WidgetTester t) async {
  t.view.physicalSize = const Size(390, 844);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(theme: AppTheme.light, home: const MarketplaceScreen()),
  );
  await _settle(t);
}

void main() {
  setUpAll(() => initFakeSupabase());

  testWidgets('a slow earlier category cannot overwrite the current one', (
    t,
  ) async {
    setFakeSupabaseHandler((req) async {
      final path = req.url.path;
      final q = req.url.query;
      if (path.endsWith('/sellers')) {
        return [
          {'auth_user_id': 's1'},
        ];
      }
      if (path.endsWith('/products')) {
        if (q.contains('category=eq.books')) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
          return [_product(1, 'Study Bible', 'books')];
        }
        if (q.contains('category=eq.clothing')) {
          return [_product(2, 'Church shirt', 'clothing')];
        }
        return [_product(3, 'Anything', 'other')];
      }
      return null;
    });
    await _pump(t);
    expect(find.text('Anything'), findsOneWidget);

    await t.tap(find.text('Bibles & Books'));
    await t.pump();
    // The chips must still be there and tappable while Books loads — the
    // first version of this fix skeletoned the whole screen, chips too.
    await t.tap(find.text('Clothing'));
    await _settle(t, rounds: 12);

    expect(find.text('Church shirt'), findsOneWidget);
    expect(find.text('Study Bible'), findsNothing);
    await t.pump(const Duration(seconds: 2));
  });

  testWidgets('a failed category load does not keep the old grid', (t) async {
    setFakeSupabaseHandler((req) {
      final path = req.url.path;
      if (path.endsWith('/sellers')) {
        return [
          {'auth_user_id': 's1'},
        ];
      }
      if (path.endsWith('/products')) {
        if (req.url.query.contains('category=eq.clothing')) {
          throw Exception('network down');
        }
        return [_product(3, 'Anything', 'other')];
      }
      return null;
    });
    await _pump(t);
    expect(find.text('Anything'), findsOneWidget);

    await t.tap(find.text('Clothing'));
    await _settle(t);

    expect(find.text('Anything'), findsNothing);
    expect(find.text('Clothing'), findsOneWidget); // chips still usable
    // postgrest retries a failed request with back-off; let it run out.
    await _settle(t, rounds: 20);
    await t.pump(const Duration(seconds: 30));
  });
}
