import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/screens/home/home_screen.dart';

import '../test/helpers/fake_supabase.dart';
import 'shot.dart';

// SAMPLE data only — placeholders, not real members or articles.
List<Map<String, Object?>> _people(int n) => [
  for (var i = 0; i < n; i++)
    {
      'id': 'u$i',
      'full_name': 'Member ${i + 1}',
      'profile_photo_url': null,
      'province': 'Harare',
      'city': i.isEven ? 'Harare' : 'Bulawayo',
      'bio': null,
      'church_id': null,
      'is_verified': false,
      'is_verified_admin': false,
      'churches': null,
    },
];

void main() {
  setUpAll(() async {
    await loadShotFonts();
    await initFakeSupabase();
    await signInFake('me', metadata: {'full_name': 'Tanatswa Mikuwa'});
    setFakeSupabaseHandler((req) {
      final path = req.url.path;
      final q = req.url.query;
      if (path.endsWith('/posts')) {
        return [
          for (var i = 0; i < 4; i++)
            {
              'id': 'p$i',
              'author_id': 'u$i',
              'body': i == 0
                  ? 'Sabbath School was a blessing this morning. Grateful for this family.'
                  : 'Sample post ${i + 1}',
              'created_at': '2026-10-2${8 - i}T06:00:00Z',
              'visibility': 'public',
              'profiles': {'full_name': 'Member ${i + 1}'},
              'post_likes': [],
              'post_comments': [],
            },
        ];
      }
      if (path.endsWith('/profiles') && q.contains('is_discoverable')) {
        return _people(40);
      }
      if (path.endsWith('/advent_news')) {
        return [
          for (var i = 0; i < 6; i++)
            {
              'id': 'n$i',
              'title': '[Sample headline ${i + 1} — an Adventist news story]',
              'summary': '[One-line summary of the story]',
              'category': 'church',
              'status': 'approved',
              'published_at': '2026-10-2${8 - i}T06:00:00Z',
              'source_label': '[Source]',
            },
        ];
      }
      if (path.endsWith('/youtube_videos')) {
        return [
          for (var i = 0; i < 10; i++)
            {
              'video_id': 'v$i',
              'channel_id': 'c',
              'channel_title': '[Church channel]',
              'title': '[Sermon title ${i + 1}]',
              'live_status': 'none',
              'published_at': '2026-10-28T10:00:00Z',
            },
        ];
      }
      if (path.endsWith('/quiz_questions')) {
        return [
          {
            'id': 'q1',
            'question': 'Who built the ark?',
            'options': ['Moses', 'Noah', 'Abraham', 'David'],
            'correct_index': 1,
            'category': 'bible',
            'difficulty': 'easy',
            'reference': 'Genesis 6:14',
            'is_published': true,
          },
        ];
      }
      if (path.endsWith('/rpc/todays_devotion')) return null;
      return null;
    });
  });

  testWidgets('feed', (t) async {
    await pumpShot(t, const HomeScreen(), dark: false);
    await saveShot(t, 'feed_0', rounds: 16);
    for (var k = 1; k <= 7; k++) {
      await t.drag(find.byType(Scrollable).first, const Offset(0, -760));
      await saveShot(t, 'feed_$k', rounds: 6);
    }
  });
}
