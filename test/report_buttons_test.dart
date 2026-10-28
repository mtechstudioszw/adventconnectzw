// Apple 1.2 asks for a way to report all user content. Jobs, events,
// prayers, comments, stories and news had none. This pins the job screen:
// a flag for other people's posts, none on your own.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/screens/jobs/job_details_screen.dart';
import 'package:advent_connect_zw/theme/app_theme.dart';

import 'helpers/fake_supabase.dart';

Map<String, Object?> _job(String poster) => {
  'id': 5,
  'poster_id': poster,
  'title': 'Teacher',
  'company': 'Solusi',
  'status': 'open',
  'created_at': '2026-10-01T00:00:00Z',
};

Future<void> _pump(WidgetTester t) async {
  t.view.physicalSize = const Size(390, 1600);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: const JobDetailsScreen(jobId: '5'),
    ),
  );
  for (var i = 0; i < 5; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(() async {
    await initFakeSupabase();
    await signInFake('viewer-1');
  });

  testWidgets("someone else's job can be reported", (t) async {
    setFakeSupabaseHandler((req) {
      if (req.url.path.endsWith('/jobs')) return [_job('someone-else')];
      return null;
    });
    await _pump(t);
    expect(find.byIcon(Icons.flag_outlined), findsOneWidget);
    await t.pump(const Duration(seconds: 2));
  });

  testWidgets('your own job has no report flag', (t) async {
    setFakeSupabaseHandler((req) {
      if (req.url.path.endsWith('/jobs')) return [_job('viewer-1')];
      return null;
    });
    await _pump(t);
    expect(find.byIcon(Icons.flag_outlined), findsNothing);
    await t.pump(const Duration(seconds: 2));
  });
}
