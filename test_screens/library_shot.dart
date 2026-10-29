import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:advent_connect_zw/models/devotion_model.dart';
import 'package:advent_connect_zw/screens/home/home_screen.dart';
import 'package:advent_connect_zw/screens/library/devotion_screen.dart';
import 'package:advent_connect_zw/screens/library/library_hub_screen.dart';
import 'package:advent_connect_zw/services/bible_prefs_service.dart';
import 'package:advent_connect_zw/services/cache_service.dart';
import 'package:advent_connect_zw/services/sabbath_school_prefs.dart';

import '../test/helpers/fake_supabase.dart';
import 'shot.dart';

const _devotion = {
  'id': 1,
  'bible_ref': 'Hebrews 10:36',
  'bible_text':
      'For ye have need of patience, that, after ye have '
      'done the will of God, ye might receive the promise.',
  'egw_quote': 'Patience is faith holding on when it cannot see.',
  'egw_source': 'Testimonies for the Church',
  'devotion_date': '2026-10-29',
};

Map<String, Object?> _video(String id, String title, {bool live = false}) => {
  'video_id': id,
  'channel_id': 'c1',
  'channel_title': '[Church channel]',
  'title': title,
  'live_status': live ? 'live' : 'none',
  'published_at': '2026-10-28T10:00:00Z',
};

void main() {
  setUpAll(() async {
    await loadShotFonts();
    await initFakeSupabase();
    await signInFake('me', metadata: {'full_name': 'Tanatswa Michael Mikuwa'});
    final dir = await Directory.systemTemp.createTemp('library_shot');
    Hive.init(dir.path);
    // ignore: invalid_use_of_visible_for_testing_member
    await CacheService.debugUseBox(await Hive.openBox<String>('lib_shot'));
    await BiblePrefsService.setLastPosition(42, 2); // John 3
    await SabbathSchoolPrefs.setLastRead(
      lang: 'en',
      quarterlyId: 'q',
      quarterlyTitle: '[This quarter]',
      lessonId: 'l5',
      lessonTitle: '[Lesson 5 title]',
      dayPath: 'en/quarterlies/q/lessons/l5/days/04',
      dayTitle: 'Wednesday',
    );
    setFakeSupabaseHandler((req) {
      final path = req.url.path;
      if (path.endsWith('/rpc/todays_devotion')) return _devotion;
      if (path.endsWith('/youtube_videos')) {
        if (req.url.query.contains('live_status=eq.live')) {
          return [_video('l1', '[Church name] — Sabbath service', live: true)];
        }
        return [
          _video('v1', '[Sermon title one]'),
          _video('v2', '[Sermon title two]'),
          _video('v3', '[Sermon title three]'),
        ];
      }
      return null;
    });
  });

  for (final dark in [false, true]) {
    final tag = dark ? '_dark' : '';
    testWidgets('library$tag', (t) async {
      await pumpShot(t, const LibraryHubScreen(), dark: dark);
      await saveShot(t, 'library$tag', rounds: 12);
      await t.drag(find.byType(Scrollable).first, const Offset(0, -500));
      await saveShot(t, 'library_scrolled$tag');
    });
  }

  testWidgets('devotion', (t) async {
    await pumpShot(
      t,
      DevotionScreen(devotion: Devotion.fromJson(_devotion)),
      dark: false,
    );
    await saveShot(t, 'devotion');
  });

  testWidgets('home', (t) async {
    await pumpShot(t, const HomeScreen(), dark: false);
    await saveShot(t, 'home_top', rounds: 12);
    await t.drag(find.byType(Scrollable).first, const Offset(0, -520));
    await saveShot(t, 'home_library_row');
  });
}
