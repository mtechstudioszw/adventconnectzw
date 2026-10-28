import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/models/job_model.dart';
import 'package:advent_connect_zw/screens/jobs/job_applicants_screen.dart';
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
  String category, {
  String type = 'full_time',
  String level = 'mid',
  double? pay,
  double? payMax,
  String period = 'month',
  bool urgent = false,
  bool sabbath = false,
  bool sda = false,
  String postType = 'hiring',
  String location = 'Harare',
  String status = 'open',
  int hoursAgo = 30,
  String? description,
}) => {
  'id': id,
  'poster_id': id == 1 ? 'u1' : 'u$id',
  'title': title,
  'company': company,
  'category': category,
  'job_type': type,
  'level': level,
  'post_type': postType,
  'location': location,
  'country': 'ZW',
  'province': 'Harare',
  'pay_min': pay,
  'pay_max': payMax,
  'pay_period': pay == null ? null : period,
  'pay_currency': 'USD',
  'is_urgent': urgent,
  'sabbath_friendly': sabbath,
  'is_sda_institution': sda,
  'status': status,
  'work_arrangement': 'on_site',
  'apply_instructions': 'Send a short note and two references.',
  'contact_email': 'jobs@example.org',
  'contact_phone': '+263771234567',
  'description':
      description ??
      'Teach Form 1 to 4 mathematics, prepare learners for ZIMSEC and help '
          'run the maths club. Boarding school with staff housing on campus.',
  'requirements': 'Degree in Mathematics or Education\nTwo years teaching',
  'created_at': DateTime.now()
      .subtract(Duration(hours: hoursAgo))
      .toUtc()
      .toIso8601String(),
  'expires_at': '2026-11-30T00:00:00Z',
};

final _vacancies = [
  _job(
    1,
    'Gardener',
    'Family home, Borrowdale',
    'domestic_caregiving',
    type: 'casual',
    level: 'entry',
    pay: 15,
    period: 'day',
    urgent: true,
    sabbath: true,
    hoursAgo: 3,
    description: 'Mowing, weeding and watering, three days a week.',
  ),
  _job(
    2,
    'Registered nurse',
    'Mwami Adventist Hospital',
    'healthcare',
    pay: 900,
    payMax: 1200,
    sabbath: true,
    sda: true,
    hoursAgo: 20,
  ),
  _job(
    3,
    'Bricklayer for a 3-room house',
    'Private client',
    'construction_trades',
    type: 'contract',
    pay: 1800,
    period: 'job',
    urgent: true,
    location: 'Chitungwiza',
    hoursAgo: 50,
  ),
  _job(
    4,
    'Mathematics teacher',
    'Solusi Adventist High School',
    'teaching_education',
    pay: 550,
    sabbath: true,
    sda: true,
    location: 'Bulawayo',
    hoursAgo: 80,
  ),
  _job(
    5,
    'Church accountant',
    'East Zimbabwe Conference',
    'business_admin',
    type: 'part_time',
    sda: true,
    hoursAgo: 120,
  ),
];

final _seekers = [
  _job(
    11,
    'Electrician — wiring, repairs, solar',
    '',
    'construction_trades',
    type: 'contract',
    level: 'senior',
    pay: 25,
    period: 'day',
    urgent: true,
    sabbath: true,
    postType: 'seeking',
    description:
        'Qualified electrician, 8 years. House wiring, DB boards, solar '
        'installs. Own tools and transport.',
  ),
  _job(
    12,
    'Housekeeper & nanny',
    '',
    'domestic_caregiving',
    level: 'mid',
    pay: 180,
    sabbath: true,
    postType: 'seeking',
    location: 'Mabelreign',
    description:
        'Four years with one family; references available. Good with '
        'children, cooking and laundry.',
  ),
];

void main() {
  setUpAll(() async {
    await loadShotFonts();
    await initFakeSupabase((req) {
      final path = req.url.path;
      final q = Uri.decodeFull(req.url.query);
      if (path.endsWith('/saved_jobs')) {
        return [
          {'job_id': 4},
        ];
      }
      if (path.endsWith('/rpc/job_applicant_count')) return 3;
      if (path.endsWith('/job_alerts')) {
        return [
          {'id': 1, 'category': 'healthcare', 'country': 'ZW'},
          {'id': 2, 'category': null, 'country': 'ZW', 'keyword': 'driver'},
        ];
      }
      if (path.endsWith('/job_applications')) {
        if (q.contains('applicant_id=eq')) {
          return [
            {
              'id': 1,
              'job_id': 2,
              'applicant_id': 'u1',
              'status': 'shortlisted',
              'created_at': '2026-10-26T08:00:00Z',
              'jobs': _vacancies[1],
            },
            {
              'id': 2,
              'job_id': 4,
              'applicant_id': 'u1',
              'status': 'viewed',
              'created_at': '2026-10-25T08:00:00Z',
              'jobs': _vacancies[3],
            },
          ];
        }
        return [
          {
            'id': 7,
            'job_id': 1,
            'applicant_id': 'u9',
            'status': 'sent',
            'message':
                'Good morning. I have kept gardens in Borrowdale for five '
                'years and can start on Monday. References available.',
            'phone': '0772 555 019',
            'created_at': '2026-10-28T06:00:00Z',
            'profiles': {'full_name': 'Tendai Moyo', 'city': 'Harare'},
          },
          {
            'id': 8,
            'job_id': 1,
            'applicant_id': 'u10',
            'status': 'shortlisted',
            'message': 'I am available Monday to Thursday.',
            'created_at': '2026-10-27T15:00:00Z',
            'profiles': {'full_name': 'Blessing Ncube', 'city': 'Epworth'},
          },
        ];
      }
      if (path.endsWith('/jobs')) {
        if (q.contains('poster_id=eq')) {
          return [
            _job(
              1,
              'Gardener',
              'Family home, Borrowdale',
              'domestic_caregiving',
              type: 'casual',
              pay: 15,
              period: 'day',
              urgent: true,
            ),
            _job(
              6,
              'Driver',
              'Family home',
              'driving_transport',
              status: 'pending',
              pay: 300,
            ),
          ];
        }
        if (q.contains('post_type=eq.seeking')) return _seekers;
        if (q.contains('id=eq.') && q.contains('limit=1')) {
          return [_vacancies[1]];
        }
        return _vacancies;
      }
      return null;
    });
    await signInFake('u1');
  });

  testWidgets('find work', (t) async {
    await pumpShot(t, const JobsScreen(), dark: false);
    await saveShot(t, 'jobs_find');
    await t.drag(find.byType(Scrollable).first, const Offset(0, -620));
    await saveShot(t, 'jobs_find_scrolled');
    await t.drag(find.byType(Scrollable).first, const Offset(0, -700));
    await saveShot(t, 'jobs_find_scrolled2');
  });

  testWidgets('find work dark', (t) async {
    await pumpShot(t, const JobsScreen());
    await saveShot(t, 'jobs_find_dark');
  });

  testWidgets('hire', (t) async {
    await pumpShot(t, const JobsScreen(), dark: false);
    await saveShot(t, 'jobs_hire_pre', rounds: 3);
    await t.tap(find.text('Hire someone'));
    await saveShot(t, 'jobs_hire');
    await t.drag(find.byType(Scrollable).first, const Offset(0, -560));
    await saveShot(t, 'jobs_hire_scrolled');
  });

  testWidgets('details', (t) async {
    final job = Job.fromJson({..._vacancies[1], 'poster_id': 'other'});
    await pumpShot(
      t,
      JobDetailsScreen(jobId: '2', initialJob: job),
      dark: false,
    );
    await saveShot(t, 'job_details');
  });

  testWidgets('quick apply', (t) async {
    final job = Job.fromJson({..._vacancies[0], 'poster_id': 'other'});
    await pumpShot(
      t,
      JobDetailsScreen(jobId: '1', initialJob: job),
      dark: false,
    );
    await saveShot(t, 'job_details_casual');
    await t.tap(find.text('Quick apply'));
    await saveShot(t, 'job_quick_apply');
  });

  testWidgets('applicants', (t) async {
    await pumpShot(
      t,
      JobApplicantsScreen(jobId: '1', job: Job.fromJson(_vacancies[0])),
      dark: false,
    );
    await saveShot(t, 'job_applicants');
  });

  testWidgets('my jobs', (t) async {
    await pumpShot(t, const MyJobsScreen(), dark: false);
    await saveShot(t, 'my_jobs_applied');
    await t.tap(find.text('My posts'));
    await saveShot(t, 'my_jobs_posts');
    await t.tap(find.text('Alerts'));
    await saveShot(t, 'my_jobs_alerts');
  });

  testWidgets('post flow', (t) async {
    await pumpShot(t, const PostJobScreen(), dark: false);
    await saveShot(t, 'post_job_step_0');
    await t.drag(find.byType(Scrollable).first, const Offset(0, -500));
    await saveShot(t, 'post_job_step_0_scrolled');
  });

  testWidgets('edit flow', (t) async {
    final job = Job.fromJson(_vacancies[0]);
    await pumpShot(t, PostJobScreen(existing: job), dark: false);
    await saveShot(t, 'post_job_step_1');
    for (var step = 2; step <= 5; step++) {
      await t.tap(find.text(step == 5 ? 'Review' : 'Continue'));
      await saveShot(t, 'post_job_step_$step');
    }
  });
}
