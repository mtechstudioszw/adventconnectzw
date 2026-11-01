// Render harness for churches (not shipped).

import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/models/church_model.dart';
import 'package:advent_connect_zw/screens/churches/church_details_screen.dart';
import 'package:advent_connect_zw/screens/churches/churches_screen.dart';

import '../test/helpers/fake_supabase.dart';
import 'shot.dart';

Map<String, Object?> _church(int id, String name, String city,
        {bool verified = false}) =>
    {
      'id': id,
      'name': name,
      'city': city,
      'province': 'Harare',
      'country': 'ZW',
      'conference': 'East Zimbabwe Conference',
      'district': 'Glen View District',
      'address': '12 Church Road, $city',
      'description':
          'A warm Seventh-day Adventist family. Sabbath School at 9:00, '
              'Divine Service at 11:00. Everyone welcome.',
      'pastor_name': 'Pastor T. Moyo',
      'phone': '+263 77 123 4567',
      'verified': verified,
      'follower_count': 120 + id,
      'members_count': 120 + id,
      'status': 'active',
      'service_times': [
        {'label': 'Sabbath School', 'day': 'Saturday', 'time': '09:00'},
        {'label': 'Divine Service', 'day': 'Saturday', 'time': '11:00'},
      ],
    };

final _churches = [
  _church(4, 'Glen View SDA Church', 'Harare', verified: true),
  _church(5, 'Mabvuku SDA Church', 'Harare'),
  _church(6, 'Avondale SDA Church', 'Harare', verified: true),
  _church(7, 'Highfield Central SDA', 'Harare'),
];

void main() {
  setUpAll(() async {
    await loadShotFonts();
    await initFakeSupabase();
    await signInFake('me', metadata: {
      'full_name': 'Tanatswa Mikuwa',
      'church_id': '4',
      'country': 'ZW',
    });
    setFakeSupabaseHandler((req) {
      final path = req.url.path;
      if (path.endsWith('/churches')) {
        final id = req.url.queryParameters['id'];
        if (id != null && id.startsWith('eq.')) {
          return _churches.where((c) => '${c['id']}' == id.substring(3)).toList();
        }
        return _churches;
      }
      if (path.endsWith('/rpc/church_member_counts')) {
        return [
          {'church_id': 4, 'members': 214},
        ];
      }
      if (path.contains('/rpc/')) return [];
      return [];
    });
  });

  testWidgets('churches', (t) async {
    await pumpShot(t, const ChurchesScreen());
    await saveShot(t, 'churches');
  });

  testWidgets('church home', (t) async {
    await pumpShot(
      t,
      ChurchDetailsScreen(
        churchId: '4',
        initialChurch: Church.fromJson(_churches[0]),
      ),
    );
    await saveShot(t, 'church_home');
  });

  testWidgets('church other', (t) async {
    await pumpShot(
      t,
      ChurchDetailsScreen(
        churchId: '5',
        initialChurch: Church.fromJson(_churches[1]),
      ),
    );
    await saveShot(t, 'church_other');
  });
}
