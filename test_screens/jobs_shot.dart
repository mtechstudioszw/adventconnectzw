import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/screens/jobs/jobs_screen.dart';

import '../test/helpers/fake_supabase.dart';
import 'shot.dart';

Map<String, Object?> _job(int id, String title, String company, String level,
        String type, {String? salary, bool sabbath = false, bool sda = false}) =>
    {
      'id': id,
      'poster_id': 'u$id',
      'title': title,
      'company': company,
      'category': 'education',
      'job_type': type,
      'level': level,
      'post_type': 'hiring',
      'location': 'Harare',
      'country': 'ZW',
      'province': 'Harare',
      'salary_range': salary,
      'sabbath_friendly': sabbath,
      'is_sda_institution': sda,
      'status': 'open',
      'created_at': '2026-10-2${id % 8}T08:00:00Z',
      'expires_at': '2026-11-30T00:00:00Z',
    };

void main() {
  setUpAll(() async {
    await loadShotFonts();
    await initFakeSupabase((req) {
      if (req.url.path.endsWith('/jobs')) {
        return [
          _job(1, 'Mathematics Teacher', 'Solusi Adventist High School',
              'mid', 'full_time', salary: r'$400 – $550', sabbath: true, sda: true),
          _job(2, 'Registered Nurse', 'Mwami Adventist Hospital', 'senior',
              'full_time', sabbath: true, sda: true),
          _job(3, 'Graphic Designer', 'Hope Media Zimbabwe', 'entry',
              'contract', salary: r'$250'),
          _job(4, 'Church Accountant', 'East Zimbabwe Conference', 'mid',
              'part_time', sda: true),
        ];
      }
      return null;
    });
  });

  testWidgets('jobs', (t) async {
    await pumpShot(t, const JobsScreen());
    await saveShot(t, 'jobs');
    await t.drag(find.byType(Scrollable).first, const Offset(0, -380));
    await saveShot(t, 'jobs_scrolled');
  });
}
