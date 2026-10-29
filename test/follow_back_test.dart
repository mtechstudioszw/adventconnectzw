// Follow back (28 Oct 2026): one tap from a follower notification or the
// Followers list, never shown for someone you already follow.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/services/follow_service.dart';
import 'package:advent_connect_zw/theme/app_theme.dart';
import 'package:advent_connect_zw/widgets/profile/follow_back_button.dart';

import 'helpers/fake_supabase.dart';

Future<void> _pump(WidgetTester t) async {
  await t.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: const Scaffold(
        body: Center(
          child: FollowBackButton(userId: 'them', name: 'Rudo'),
        ),
      ),
    ),
  );
  await t.pump();
}

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 4; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await t.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUpAll(() async {
    await initFakeSupabase();
    await signInFake('me');
  });

  testWidgets('hidden until we know who you follow', (t) async {
    FollowService.followingIds.value = null;
    await _pump(t);
    expect(find.text('Follow back'), findsNothing);
  });

  testWidgets('already following reads Following, not Follow back', (t) async {
    FollowService.followingIds.value = {'them'};
    await _pump(t);
    expect(find.text('Following'), findsOneWidget);
    expect(find.text('Follow back'), findsNothing);
  });

  testWidgets('tapping follows back', (t) async {
    FollowService.followingIds.value = <String>{};
    setFakeSupabaseHandler((req) {
      if (req.method == 'POST' && req.url.path.endsWith('/follows')) {
        return {'status': 'active'};
      }
      return null;
    });
    await _pump(t);
    await t.tap(find.text('Follow back'));
    await _settle(t);
    expect(find.text('Following'), findsOneWidget);
    expect(FollowService.followingIds.value, contains('them'));
  });

  testWidgets('a private account shows Requested', (t) async {
    FollowService.followingIds.value = <String>{};
    setFakeSupabaseHandler((req) {
      if (req.method == 'POST') return {'status': 'pending'};
      return null;
    });
    await _pump(t);
    await t.tap(find.text('Follow back'));
    await _settle(t);
    expect(find.text('Requested'), findsOneWidget);
  });

  testWidgets('their setting refusing it says so', (t) async {
    FollowService.followingIds.value = <String>{};
    setFakeSupabaseHandler((req) {
      if (req.method == 'POST') {
        return const FakeError(403, {
          'code': '42501',
          'message': 'FOLLOW_NOT_ALLOWED',
        });
      }
      return null;
    });
    await _pump(t);
    await t.tap(find.text('Follow back'));
    await _settle(t);
    expect(find.text("Rudo isn't taking followers."), findsOneWidget);
  });
}
