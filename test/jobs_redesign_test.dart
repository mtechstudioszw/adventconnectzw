// Stage 7 Jobs redesign (28 Oct 2026):
// - Filters narrow the server query, not a fetched page.
// - Search covers role, employer, skill and place.
// - Clearing an apply link or Page sends null, never '' (which would
//   break apply_url's http check, and '' is not a uuid).
// - Posting still works before patch_278: it retries without the new
//   columns.
// - The landing's empty state offers both sides of the market.
// - My job posts shows the row's real moderation status.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/models/job_model.dart';
import 'package:advent_connect_zw/screens/jobs/jobs_screen.dart';
import 'package:advent_connect_zw/screens/jobs/my_jobs_screen.dart';
import 'package:advent_connect_zw/services/job_application_service.dart';
import 'package:advent_connect_zw/services/job_service.dart';
import 'package:advent_connect_zw/theme/app_theme.dart';

import 'helpers/fake_supabase.dart';

Job _job(String status, {DateTime? expires}) => Job(
  id: '1',
  posterId: 'poster-1',
  title: 'Teacher',
  company: 'Solusi',
  createdAt: DateTime(2026, 10, 1),
  status: status,
  expiresAt: expires ?? DateTime.now().add(const Duration(days: 10)),
);

void main() {
  setUpAll(() async {
    await initFakeSupabase();
    await signInFake('poster-1');
  });

  test('filters and search go into the query', () async {
    fakeSupabaseRequests.clear();
    setFakeSupabaseHandler((_) => const <Object>[]);
    await JobService.fetchJobs(
      search: 'nurse',
      category: 'healthcare',
      country: 'ZW',
      filters: const JobFilters(
        jobType: 'part_time',
        level: 'entry',
        postType: 'hiring',
        workArrangement: 'remote',
        sabbathFriendly: true,
        sdaInstitution: true,
      ),
    );
    final q = Uri.decodeFull(fakeSupabaseRequests.last.url.query);
    expect(q, contains('status=eq.open'));
    expect(q, contains('category=eq.healthcare'));
    expect(q, contains('country=eq.ZW'));
    expect(q, contains('job_type=eq.part_time'));
    expect(q, contains('level=eq.entry'));
    expect(q, contains('post_type=eq.hiring'));
    expect(q, contains('work_arrangement=eq.remote'));
    expect(q, contains('sabbath_friendly=eq.true'));
    expect(q, contains('is_sda_institution=eq.true'));
    for (final col in ['title', 'company', 'description', 'requirements']) {
      expect(q, contains('$col.ilike'));
    }
  });

  test('filter count ignores what is off', () {
    expect(JobFilters.none.activeCount, 0);
    expect(
      const JobFilters(jobType: 'contract', sabbathFriendly: true).activeCount,
      2,
    );
  });

  test('category ids match the database', () {
    // The old browse strip filtered on ids no row ever had.
    expect(JobCategory.byId('teaching_education'), isNotNull);
    expect(JobCategory.byId('it_technology'), isNotNull);
    expect(JobCategory.byId('teaching'), isNull);
    expect(JobCategory.all.any((c) => c.id == 'all'), isFalse);
  });

  test('clearing the apply link and Page sends null', () async {
    Map<String, dynamic>? sent;
    setFakeSupabaseHandler((req) {
      if (req.method == 'PATCH') {
        sent = jsonDecode(req.body) as Map<String, dynamic>;
        return [
          {'id': 3},
        ];
      }
      return null;
    });
    await JobService.updateJob(
      jobId: '3',
      applyUrl: '  ',
      pageId: '',
      applyInstructions: 'Send a CV',
    );
    expect(sent!.containsKey('apply_url'), isTrue);
    expect(sent!['apply_url'], isNull);
    expect(sent!['page_id'], isNull);
    expect(sent!['apply_instructions'], 'Send a CV');
    // Not passed → not touched.
    expect(sent!.containsKey('work_arrangement'), isFalse);
  });

  test('moderation status reads as the owner would say it', () {
    expect(jobPostState(_job('pending')), JobPostState.review);
    expect(jobPostState(_job('open')), JobPostState.live);
    expect(
      jobPostState(
        _job('open', expires: DateTime.now().subtract(const Duration(days: 1))),
      ),
      JobPostState.ended,
    );
    expect(jobPostState(_job('filled')), JobPostState.filled);
    expect(jobPostState(_job('rejected')), JobPostState.rejected);
    expect(jobPostState(_job('expired')), JobPostState.ended);
  });

  testWidgets('empty landing offers a vacancy and looking for work', (t) async {
    setFakeSupabaseHandler((_) => const <Object>[]);
    t.view.physicalSize = const Size(390, 1400);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const JobsScreen()),
    );
    for (var i = 0; i < 6; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await t.pump(const Duration(milliseconds: 50));
    }
    expect(t.takeException(), isNull);
    expect(find.text('Post a vacancy'), findsOneWidget);
    expect(find.text("I'm looking for work"), findsOneWidget);
    expect(find.byTooltip('Filters'), findsOneWidget);
    expect(find.text('Find work'), findsOneWidget);
    expect(find.text('Hire someone'), findsOneWidget);
    // Every kind of work has a door.
    expect(find.text('Everyday work'), findsOneWidget);
    expect(find.text('Skilled & medical'), findsOneWidget);
    expect(find.text('Professional'), findsOneWidget);
    // Nothing pretends to be personalised or paid for.
    expect(find.textContaining('Recommended'), findsNothing);
    expect(find.textContaining('Featured'), findsNothing);
    await t.pump(const Duration(seconds: 2));
  });

  test('pay reads the way people say it', () {
    expect(Job.formatPay(min: 15, period: 'day'), r'$15 / day');
    expect(
      Job.formatPay(min: 900, max: 1200, period: 'month'),
      r'$900–1,200 / month',
    );
    expect(
      Job.formatPay(min: 25000, period: 'month', currency: 'KES'),
      'KES 25,000 / month',
    );
    expect(Job.formatPay(min: 200, max: 200, period: 'job'), r'$200 / job');
    final structured = Job.fromJson({
      'id': 1,
      'title': 'Gardener',
      'pay_min': 15,
      'pay_period': 'day',
      'pay_currency': 'USD',
      'salary_range': 'old text',
      'is_urgent': true,
    });
    expect(structured.payLabel, r'$15 / day');
    expect(structured.isUrgent, isTrue);
    // Older rows keep what the poster typed.
    expect(
      Job.fromJson({'id': 2, 'title': 'x', 'salary_range': r'$400'}).payLabel,
      r'$400',
    );
    expect(Job.fromJson({'id': 3, 'title': 'x'}).payLabel, isNull);
    expect(structured.toJson()['pay_period'], 'day');
  });

  test('every field belongs to a kind of work, everyday work has roles', () {
    for (final c in JobCategory.all) {
      expect(JobKind.values, contains(c.kind));
    }
    final everyday = JobCategory.ofKind(JobKind.everyday).map((c) => c.id);
    expect(everyday, contains('domestic_caregiving'));
    final home = JobCategory.byId('domestic_caregiving')!;
    expect(home.roles.map((r) => r.title), containsAll(['Gardener', 'Nanny']));
    expect(jobTypes['casual'], 'Casual / day work');
  });

  test('quick apply sends the job, message and phone', () async {
    Map<String, dynamic>? sent;
    setFakeSupabaseHandler((req) {
      if (req.method == 'POST' && req.url.path.endsWith('/job_applications')) {
        sent = jsonDecode(req.body) as Map<String, dynamic>;
        return const <Object>[];
      }
      return null;
    });
    await JobApplicationService.apply(
      jobId: '7',
      message: '  I have 3 years experience  ',
      phone: '0771234567',
    );
    expect(sent!['job_id'], 7);
    expect(sent!['applicant_id'], 'poster-1');
    expect(sent!['message'], 'I have 3 years experience');
    expect(sent!['phone'], '0771234567');
    expect(JobApplicationService.appliedJobIds.value, contains('7'));
  });

  test('applicant count is the server number, null when unknown', () async {
    setFakeSupabaseHandler((req) {
      if (req.url.path.endsWith('/rpc/job_applicant_count')) return 4;
      return null;
    });
    expect(await JobApplicationService.count('7'), 4);
    setFakeSupabaseHandler(
      (_) => const FakeError(404, {'code': 'PGRST202', 'message': 'nope'}),
    );
    expect(await JobApplicationService.count('7'), isNull);
  });

  test('alerts save the field and country', () async {
    Map<String, dynamic>? sent;
    setFakeSupabaseHandler((req) {
      if (req.method == 'POST' && req.url.path.endsWith('/job_alerts')) {
        sent = jsonDecode(req.body) as Map<String, dynamic>;
        return {'id': 1, ...sent!};
      }
      return null;
    });
    await JobAlertService.create(category: 'healthcare', country: 'ZW');
    expect(sent!['category'], 'healthcare');
    expect(sent!['country'], 'ZW');
    expect(
      JobAlertService.alerts.value.single.matches(
        category: 'healthcare',
        jobType: null,
        country: 'ZW',
      ),
      isTrue,
    );
  });

  testWidgets('hire mode offers one-tap role templates', (t) async {
    setFakeSupabaseHandler((_) => const <Object>[]);
    t.view.physicalSize = const Size(390, 1600);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const JobsScreen()),
    );
    for (var i = 0; i < 4; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await t.pump(const Duration(milliseconds: 50));
    }
    await t.tap(find.text('Hire someone'));
    for (var i = 0; i < 4; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await t.pump(const Duration(milliseconds: 50));
    }
    expect(t.takeException(), isNull);
    expect(find.text('Hiring? Post in two minutes'), findsOneWidget);
    expect(find.text('Gardener'), findsOneWidget);
    expect(find.text('Housekeeper'), findsOneWidget);
    expect(find.text('Registered nurse'), findsOneWidget);
    final q = Uri.decodeFull(fakeSupabaseRequests.last.url.query);
    expect(q, contains('post_type=eq.seeking'));
    await t.pump(const Duration(seconds: 2));
  });

  // Last: it flips the service's "columns missing" flag for the run.
  test('posting before patch_278 retries without the new columns', () async {
    final bodies = <Map<String, dynamic>>[];
    setFakeSupabaseHandler((req) {
      if (req.method != 'POST') return null;
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      bodies.add(body);
      if (body.containsKey('work_arrangement')) {
        return const FakeError(400, {
          'code': 'PGRST204',
          'message': "Could not find the 'work_arrangement' column of 'jobs'",
        });
      }
      return {'id': 9};
    });
    final id = await JobService.postJob(
      title: 'Nurse',
      description: 'Ward nurse for the mission hospital.',
      category: 'healthcare',
      location: 'Mutare',
      country: 'ZW',
      province: 'Manicaland',
      workArrangement: 'on_site',
      applyUrl: 'https://example.org/apply',
    );
    expect(id, '9');
    expect(bodies, hasLength(2));
    expect(bodies.last.containsKey('work_arrangement'), isFalse);
    expect(bodies.last.containsKey('apply_url'), isFalse);
    expect(bodies.last['title'], 'Nurse');
    expect(JobService.redesignAvailable, isFalse);
  });
}
