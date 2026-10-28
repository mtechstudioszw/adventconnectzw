import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/screens/marketplace/marketplace_screen.dart';

import '../test/helpers/fake_supabase.dart';
import 'shot.dart';

Map<String, Object?> _p(int id, String title, num price, String cat) => {
      'id': id,
      'seller_id': id.isEven ? 's1' : 's2',
      'title': title,
      'price': price,
      'category': cat,
      'status': 'available',
      'country': 'ZW',
      'location': 'Harare',
      'image_urls': ['https://example.com/$id.jpg'],
    };

void main() {
  setUpAll(() async {
    await loadShotFonts();
    await initFakeSupabase((req) {
      final path = req.url.path;
      if (path.endsWith('/sellers')) {
        if (req.url.query.contains('select=auth_user_id')) {
          return [
            {'auth_user_id': 's1', 'business_name': 'Theopath Healthcare'},
            {'auth_user_id': 's2', 'business_name': 'Ammiel Uniforms'},
          ];
        }
        return [
          {
            'id': 1,
            'auth_user_id': 's1',
            'business_name': 'Theopath Healthcare',
            'category': 'health',
            'country': 'ZW',
            'city': 'Harare',
            'province': 'Harare',
            'status': 'approved',
            'is_active': true,
          },
          {
            'id': 2,
            'auth_user_id': 's2',
            'business_name': 'Ammiel Uniforms',
            'category': 'clothing',
            'country': 'ZW',
            'city': 'Harare',
            'province': 'Mashonaland Central',
            'status': 'approved',
            'is_active': true,
          },
        ];
      }
      if (path.endsWith('/products')) {
        return [
          _p(21, 'Vernonia Amygdalina Capsules', 10, 'other'),
          _p(22, 'Harpagophytum Capsules', 10, 'other'),
          _p(35, 'Neem Capsules', 10, 'other'),
          _p(40, 'Last Generation Theology', 15, 'books'),
          _p(41, 'Pathfinder Uniform — full set', 45, 'clothing'),
          _p(46, 'Church Hymnal (Shona)', 8, 'books'),
        ];
      }
      return null;
    });
  });

  testWidgets('marketplace', (t) async {
    await pumpShot(t, const MarketplaceScreen());
    await saveShot(t, 'marketplace');
    await t.drag(find.byType(Scrollable).first, const Offset(0, -420));
    await saveShot(t, 'marketplace_scrolled');
  });
}
