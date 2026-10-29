import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/screens/pages/page_studio_screen.dart';
import 'package:advent_connect_zw/services/page_service.dart';

import '../test/helpers/fake_supabase.dart';
import 'shot.dart';

Map<String, Object?> _post(String id, String body, int likes, int comments) => {
  'id': id,
  'author_id': 'me',
  'page_id': 'pg1',
  'body': body,
  'created_at': '2026-10-2${id.substring(1)}T10:00:00Z',
  'post_likes': {'count': likes},
  'post_comments': {'count': comments},
};

void main() {
  setUpAll(() async {
    await loadShotFonts();
    await initFakeSupabase((req) {
      final path = req.url.path;
      if (path.endsWith('/pages')) {
        return [
          {
            'id': 'pg1',
            'name': 'Harare Pathfinder Club',
            'category': 'ministry',
            'description': 'Youth ministry meeting every Sunday.',
            'city': 'Harare',
            'contact_phone': '+263 77 123 4567',
            'status': 'active',
            'created_at': '2026-03-01T00:00:00Z',
          },
        ];
      }
      if (path.endsWith('/rpc/page_stats')) {
        return [
          {'followers': 248, 'i_follow': false, 'my_role': 'owner'},
        ];
      }
      if (path.endsWith('/posts')) {
        return [
          _post('p6', 'Camporee this weekend — bring your tents!', 41, 12),
          _post('p5', 'Thank you to every parent who drove us.', 18, 4),
          _post('p4', 'Investiture service next Sabbath at 3pm.', 9, 2),
        ];
      }
      if (path.endsWith('/rpc/list_page_admins')) {
        return [
          {'user_id': 'me', 'full_name': 'Me', 'role': 'owner'},
        ];
      }
      return const <Object>[];
    });
    await signInFake('me');
    PageService.available = true;
  });

  for (final dark in [false, true]) {
    testWidgets('page studio ${dark ? 'dark' : 'light'}', (t) async {
      await pumpShot(
        t,
        const PageStudioScreen(pageId: 'pg1'),
        dark: dark,
        size: const Size(412, 1500),
      );
      await saveShot(t, 'page_studio_${dark ? 'dark' : 'light'}');
    });
  }
}
