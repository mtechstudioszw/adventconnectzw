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
    expect(find.text('Filters'), findsOneWidget);
    // Nothing pretends to be personalised or paid for.
    expect(find.textContaining('Recommended'), findsNothing);
    expect(find.textContaining('Featured'), findsNothing);
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
