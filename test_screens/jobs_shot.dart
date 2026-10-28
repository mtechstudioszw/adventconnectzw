import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/models/job_model.dart';
import 'package:advent_connect_zw/screens/jobs/job_details_screen.dart';
import 'package:advent_connect_zw/screens/jobs/jobs_screen.dart';
import 'package:advent_connect_zw/screens/jobs/my_jobs_screen.dart';
import 'package:advent_connect_zw/screens/jobs/post_job_screen.dart';

import '../test/helpers/fake_supabase.dart';
import 'shot.dart';

Map<String, Object?> _job(
  int id,
  String title,
  String company,
  String level,
  String type, {
  String? salary,
  bool sabbath = false,
  bool sda = false,
}) => {
  'id': id,
  'poster_id': 'u$id',
  'title': title,
  'company': company,
  'category': id.isEven ? 'healthcare' : 'teaching_education',
  'job_type': type,
  'level': level,
  'post_type': 'hiring',
  'location': 'Harare',
  'country': 'ZW',
  'province': 'Harare',
  'salary_range': salary,
  'sabbath_friendly': sabbath,
  'is_sda_institution': sda,
  'status': id == 3 ? 'pending' : 'open',
  'work_arrangement': id == 3 ? 'remote' : 'on_site',
  'apply_instructions': 'Send your CV and two references.',
  'contact_email': 'jobs@example.org',
  'contact_phone': '+263771234567',
  'description':
      'Teach Form 1 to 4 mathematics, prepare learners for ZIMSEC and help '
      'run the maths club. Boarding school with staff housing on campus.',
  'requirements': 'Degree in Mathematics or Education\nTwo years teaching',
  'created_at': '2026-10-2${id % 8}T08:00:00Z',
  'expires_at': '2026-11-30T00:00:00Z',
};

bool empty = false;

void main() {
  setUpAll(() async {
    await loadShotFonts();
    await initFakeSupabase((req) {
      if (req.url.path.endsWith('/saved_jobs')) {
        return [
          {'job_id': 2},
        ];
      }
      if (empty && req.url.path.endsWith('/jobs')) return const <Object>[];
      if (req.url.path.endsWith('/jobs')) {
        return [
          _job(
            1,
            'Mathematics Teacher',
            'Solusi Adventist High School',
            'mid',
            'full_time',
            salary: r'$400 – $550',
            sabbath: true,
            sda: true,
          ),
          _job(
            2,
            'Registered Nurse',
            'Mwami Adventist Hospital',
            'senior',
            'full_time',
            sabbath: true,
            sda: true,
          ),
          _job(
            3,
            'Graphic Designer',
            'Hope Media Zimbabwe',
            'entry',
            'contract',
            salary: r'$250',
          ),
          _job(
            4,
            'Church Accountant',
            'East Zimbabwe Conference',
            'mid',
            'part_time',
            sda: true,
          ),
        ];
      }
      return null;
    });
    await signInFake('u1');
  });

  testWidgets('jobs', (t) async {
    await pumpShot(t, const JobsScreen());
    await saveShot(t, 'jobs');
    await t.drag(find.byType(Scrollable).first, const Offset(0, -380));
    await saveShot(t, 'jobs_scrolled');
  });

  testWidgets('jobs light', (t) async {
    await pumpShot(t, const JobsScreen(), dark: false);
    await saveShot(t, 'jobs_light');
  });

  testWidgets('jobs empty', (t) async {
    empty = true;
    await pumpShot(t, const JobsScreen(), dark: false);
    await saveShot(t, 'jobs_empty');
    empty = false;
  });

  testWidgets('my jobs', (t) async {
    await pumpShot(t, const MyJobsScreen(), dark: false);
    await saveShot(t, 'my_jobs');
  });

  testWidgets('details', (t) async {
    final job = Job.fromJson({
      ..._job(
        1,
        'Mathematics Teacher',
        'Solusi Adventist High School',
        'mid',
        'full_time',
        salary: r'$400 – $550',
        sabbath: true,
        sda: true,
      ),
      'poster_id': 'other',
    });
    await pumpShot(
      t,
      JobDetailsScreen(jobId: '1', initialJob: job),
      dark: false,
    );
    await saveShot(t, 'job_details');
    await t.tap(find.text('Apply now'));
    await saveShot(t, 'job_apply_sheet');
  });

  testWidgets('post flow', (t) async {
    await pumpShot(t, const PostJobScreen(), dark: false);
    await saveShot(t, 'post_job_step_0');
  });

  testWidgets('edit flow', (t) async {
    final job = Job.fromJson(
      _job(
        1,
        'Mathematics Teacher',
        'Solusi Adventist High School',
        'mid',
        'full_time',
        salary: r'$400 – $550',
        sabbath: true,
        sda: true,
      ),
    );
    await pumpShot(t, PostJobScreen(existing: job), dark: false);
    await saveShot(t, 'post_job_step_1');
    for (var step = 2; step <= 5; step++) {
      await t.tap(find.text(step == 5 ? 'Review' : 'Continue'));
      await saveShot(t, 'post_job_step_$step');
    }
  });
}
