// Render harness: events, prayer, settings (not shipped).

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/screens/events/events_screen.dart';
import 'package:advent_connect_zw/screens/prayer/prayer_screen.dart';
import 'package:advent_connect_zw/screens/settings/settings_screen.dart';

import '../test/helpers/fake_supabase.dart';
import 'shot.dart';

String _day(int d) => DateTime.now()
    .add(Duration(days: d))
    .toIso8601String()
    .substring(0, 10);

Map<String, Object?> _event(int id, String title, int inDays, String venue) => {
  'id': id,
  'title': title,
  'description': 'Join us for a blessed time of fellowship and worship.',
  'start_date': _day(inDays),
  'event_date': _day(inDays),
  'start_time': '10:00',
  'end_time': '14:00',
  'venue': venue,
  'location': venue,
  'city': 'Harare',
  'country': 'ZW',
  'rsvp_count': 12 * id,
  'church_id': 4,
  'churches': {'name': 'Glen View SDA Church'},
  'created_at': '2026-10-20T10:00:00Z',
};

Map<String, Object?> _prayer(int id, String name, String text, int likes,
        {String cat = 'healing', bool answered = false}) =>
    {
      'id': id,
      'author_id': 'u$id',
      'author_name': name,
      'content': text,
      'category': cat,
      'prayer_count': likes,
      'comment_count': id,
      'is_answered': answered,
      'visibility': 'public',
      'created_at': DateTime.now()
          .subtract(Duration(hours: id * 5))
          .toUtc()
          .toIso8601String(),
    };

void main() {
  setUpAll(() async {
    await loadShotFonts();
    final mm = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final ch in [
      'xyz.luan/audioplayers',
      'xyz.luan/audioplayers.global',
      'dev.fluttercommunity.plus/package_info',
    ]) {
      mm.setMockMethodCallHandler(MethodChannel(ch), (c) async {
        if (c.method == 'getAll') {
          return {
            'appName': 'Adventist Super App',
            'packageName': 'zw.adventconnect',
            'version': '1.0.0',
            'buildNumber': '1',
          };
        }
        return null;
      });
    }
    await initFakeSupabase();
    await signInFake('me', metadata: {
      'full_name': 'Tanatswa Mikuwa',
      'church_id': '4',
      'country': 'ZW',
    });
    setFakeSupabaseHandler((req) {
      final path = req.url.path;
      if (path.endsWith('/events')) {
        return [
          _event(1, 'Youth Camp Meeting 2026', 2, 'Glen View SDA Church'),
          _event(2, 'Pathfinder Investiture', 6, 'Mabvuku SDA Church'),
          _event(3, 'Health Expo & Free Clinic', 12, 'Harare Gardens'),
          _event(4, 'Women\'s Ministries Prayer Breakfast', 20, 'Avondale SDA'),
        ];
      }
      if (path.endsWith('/prayers')) {
        return [
          _prayer(1, 'Rudo Moyo',
              'Please pray for my mother who is going for surgery on Monday.', 34),
          _prayer(2, 'Tendai Chikwanha',
              'Praying for my exams this week — trusting God for peace.', 12,
              cat: 'studies'),
          _prayer(3, 'Nyasha Dube',
              'Praise God! My husband found work after eight months.', 51,
              cat: 'thanksgiving', answered: true),
        ];
      }
      if (path.contains('/rpc/')) return [];
      return [];
    });
  });

  testWidgets('events', (t) async {
    await pumpShot(t, const EventsScreen());
    await saveShot(t, 'events');
  });

  testWidgets('prayer', (t) async {
    await pumpShot(t, const PrayerScreen());
    await saveShot(t, 'prayer');
  });

  testWidgets('settings', (t) async {
    await pumpShot(t, const SettingsScreen());
    await saveShot(t, 'settings');
  });
}
