import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/screens/home/search_screen.dart';
import 'package:advent_connect_zw/services/search_history_service.dart';
import 'package:advent_connect_zw/services/search_typeahead_service.dart';

import '../test/helpers/fake_supabase.dart';
import 'shot.dart';

final _people = [
  for (final (i, n, c) in [
    (1, 'Tendai Moyo', 'Harare'),
    (2, 'Rudo Chikore', 'Bulawayo'),
    (3, 'Tatenda Ncube', 'Mutare'),
    (4, 'Blessing Sibanda', 'Gweru'),
  ])
    {
      'id': 'u$i',
      'full_name': n,
      'username': n.toLowerCase().replaceAll(' ', '.'),
      'city': c,
      'province': c,
      'is_verified': i == 1,
      'is_discoverable': true,
      'bio': 'Pathfinder leader',
    },
];

final _churches = [
  {
    'id': 'c1',
    'name': 'Highfield SDA Church',
    'city': 'Harare',
    'province': 'Harare',
    'country': 'ZW',
  },
  {
    'id': 'c2',
    'name': 'Hillside SDA Church',
    'city': 'Bulawayo',
    'province': 'Bulawayo',
    'country': 'ZW',
  },
];

final _products = [
  {
    'id': 1,
    'seller_id': 's1',
    'title': 'Pathfinder uniform — full set',
    'price': 45,
    'price_currency': 'USD',
    'status': 'available',
    'image_urls': [],
    'created_at': '2026-10-20T00:00:00Z',
  },
];

final _jobs = [
  {
    'id': 1,
    'poster_id': 'p',
    'title': 'Mathematics teacher',
    'company': 'Solusi Adventist High School',
    'category': 'teaching_education',
    'job_type': 'full_time',
    'post_type': 'hiring',
    'status': 'open',
    'location': 'Bulawayo',
    'country': 'ZW',
    'created_at': '2026-10-26T00:00:00Z',
    'expires_at': '2026-11-30T00:00:00Z',
  },
];

void main() {
  setUpAll(() async {
    await loadShotFonts();
    await initFakeSupabase((req) {
      final path = req.url.path;
      if (path.contains('/rpc/')) {
        if (path.endsWith('search_profiles')) return _people;
        if (path.endsWith('page_stats')) {
          return [
            {'followers': 214, 'i_follow': false},
          ];
        }
        if (path.endsWith('mutual_friends')) {
          return [
            {'id': 'x', 'full_name': 'X', 'total': 3},
          ];
        }
        return const <Object>[];
      }
      if (path.endsWith('/profiles')) return _people;
      if (path.endsWith('/churches')) return _churches;
      if (path.endsWith('/products')) return _products;
      if (path.endsWith('/jobs')) return _jobs;
      if (path.endsWith('/pages')) {
        return [
          {
            'id': 'a1b2c3d4-0000-0000-0000-000000000001',
            'name': 'Pathfinder Club Harare',
            'category': 'ministry',
            'city': 'Harare',
            'is_verified': true,
            'status': 'active',
          },
        ];
      }
      return const <Object>[];
    });
    await signInFake('me');
  });

  testWidgets('search', (t) async {
    for (final h in const [
      SearchHit(
        kind: SearchHitKind.product,
        id: '1',
        title: 'Pathfinder uniform',
      ),
      SearchHit(
        kind: SearchHitKind.page,
        id: 'p',
        title: 'Pathfinder Club Harare',
      ),
      SearchHit(kind: SearchHitKind.person, id: 'u2', title: 'Rudo Chikore'),
      SearchHit(
        kind: SearchHitKind.person,
        id: 'u1',
        title: 'Tendai Moyo',
        verified: true,
      ),
    ]) {
      await SearchHistoryService.add(h);
    }
    await pumpShot(t, const SearchScreen(), dark: false);
    await saveShot(t, 'search_landing');
    await t.enterText(find.byType(EditableText), 'pa');
    await saveShot(t, 'search_typing');
    await t.testTextInput.receiveAction(TextInputAction.search);
    await saveShot(t, 'search_results');
    await t.tap(find.text('People').last);
    await saveShot(t, 'search_people_tab');
  });

  testWidgets('search dark', (t) async {
    await pumpShot(t, const SearchScreen());
    await saveShot(t, 'search_landing_dark');
  });

  testWidgets('verse', (t) async {
    await pumpShot(t, const SearchScreen(), dark: false);
    await t.enterText(find.byType(EditableText), 'John 3:16');
    await saveShot(t, 'search_verse');
    await t.enterText(find.byType(EditableText), 'love one another');
    await saveShot(t, 'search_phrase');
  });
}
