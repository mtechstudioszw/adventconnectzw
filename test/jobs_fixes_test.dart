// Jobs audit, Batch 2:
// - a shared link to a deleted job crashed the details screen (`_job!`);
// - owner writes (edit, delete, filled, reopen) reported success when RLS
//   changed zero rows;
// - switching Hiring/Offering in the edit form was never saved;
// - "Mark as filled" rebuilt the job by hand and dropped five fields.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/models/job_model.dart';
import 'package:advent_connect_zw/screens/jobs/job_details_screen.dart';
import 'package:advent_connect_zw/services/job_service.dart';
import 'package:advent_connect_zw/theme/app_theme.dart';

import 'helpers/fake_supabase.dart';

void main() {
  setUpAll(() async {
    await initFakeSupabase();
    await signInFake('poster-1');
  });

  testWidgets('deleted job via shared link shows a notice, not a crash', (
    t,
  ) async {
    setFakeSupabaseHandler((_) => const <Object>[]);
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const JobDetailsScreen(jobId: '404'),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await t.pump(const Duration(milliseconds: 50));
    }
    expect(t.takeException(), isNull);
    expect(find.text('This job is no longer available'), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);
    await t.pump(const Duration(seconds: 2));
  });

  test('owner writes that change no row are errors', () async {
    setFakeSupabaseHandler((_) => const <Object>[]);
    await expectLater(JobService.markAsFilled('3'), throwsStateError);
    await expectLater(JobService.reopen('3'), throwsStateError);
    await expectLater(JobService.deleteJob('3'), throwsStateError);
    await expectLater(
      JobService.updateJob(jobId: '3', title: 'x'),
      throwsStateError,
    );
  });

  test('editing saves the Hiring/Offering switch', () async {
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
    await JobService.updateJob(jobId: '3', postType: 'seeking');
    expect(sent!['post_type'], 'seeking');
  });

  test('copyWith(status) keeps every other field', () {
    final job = Job(
      id: '3',
      posterId: 'poster-1',
      title: 'Teacher',
      company: 'Solusi',
      createdAt: DateTime(2026, 10, 1),
      country: 'ZW',
      province: 'Matabeleland North',
      postType: 'seeking',
      level: 'senior',
      expiresAt: DateTime(2026, 11, 30),
    );
    final filled = job.copyWith(status: 'filled');
    expect(filled.status, 'filled');
    expect(filled.country, 'ZW');
    expect(filled.province, 'Matabeleland North');
    expect(filled.postType, 'seeking');
    expect(filled.level, 'senior');
    expect(filled.expiresAt, DateTime(2026, 11, 30));
  });
}
