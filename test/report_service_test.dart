// patch_279: one open report per member per item. Reporting the same thing
// twice must read as done, not as "Could not send the report".

import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/services/report_service.dart';

import 'helpers/fake_supabase.dart';

void main() {
  setUpAll(() async {
    await initFakeSupabase();
    await signInFake('member-1');
  });

  test('a repeat report is not an error', () async {
    setFakeSupabaseHandler(
      (_) => const FakeError(409, {
        'code': '23505',
        'message': 'duplicate key value violates unique constraint',
      }),
    );
    await ReportService.submit(
      contentType: 'job',
      contentId: '12',
      reason: 'scam',
    );
  });

  test('other failures still surface', () async {
    setFakeSupabaseHandler(
      (_) => const FakeError(500, {'code': 'XX000', 'message': 'boom'}),
    );
    await expectLater(
      ReportService.submit(contentType: 'product', contentId: '3', reason: 'x'),
      throwsA(isA<Exception>()),
    );
  });

  test('jobs, products and stores send their own type', () async {
    final types = <String>[];
    setFakeSupabaseHandler((req) {
      if (req.method == 'POST') {
        types.add(Uri.decodeFull(req.body));
      }
      return null;
    });
    for (final t in ['job', 'product', 'seller']) {
      await ReportService.submit(contentType: t, contentId: '1', reason: 'r');
    }
    expect(types[0], contains('"content_type":"job"'));
    expect(types[1], contains('"content_type":"product"'));
    expect(types[2], contains('"content_type":"seller"'));
  });
}
