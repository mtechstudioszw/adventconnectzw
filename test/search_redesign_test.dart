// Search redesign (28 Oct 2026):
// - Typing shows quick suggestions and does NOT run the full search — the
//   old screen fired seven searches on every pause, one of them pulling up
//   to 5,000 churches.
// - Pressing search runs it once, with churches capped at 20, and Pages
//   are a result type.
// - A Bible reference typed into search offers a jump to the verse.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/screens/home/search_screen.dart';
import 'package:advent_connect_zw/services/search_history_service.dart';
import 'package:advent_connect_zw/services/search_typeahead_service.dart';
import 'package:advent_connect_zw/theme/app_theme.dart';

import 'helpers/fake_supabase.dart';

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 8; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(() async {
    await initFakeSupabase();
    await signInFake('me');
  });

  testWidgets('typing suggests; submitting searches once, lightly', (t) async {
    fakeSupabaseRequests.clear();
    setFakeSupabaseHandler((req) {
      final path = req.url.path;
      if (path.endsWith('/pages')) {
        return [
          {
            'id': 'a1b2c3d4-0000-0000-0000-000000000001',
            'name': 'Pathfinder Club Harare',
            'city': 'Harare',
            'is_verified': false,
            'status': 'active',
          },
        ];
      }
      if (path.endsWith('/churches')) {
        return [
          {'id': 'c1', 'name': 'Highfield SDA Church', 'city': 'Harare'},
        ];
      }
      return const <Object>[];
    });
    t.view.physicalSize = const Size(412, 1400);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const SearchScreen(autoLoad: false),
      ),
    );
    await t.pump();

    await t.enterText(find.byType(TextField), 'path');
    await _settle(t);
    expect(find.text('Search for "path"'), findsOneWidget);
    expect(find.text('Pathfinder Club Harare'), findsOneWidget);
    // No heavy search while typing: nothing asked for posts.
    expect(
      fakeSupabaseRequests.any((r) => r.url.path.endsWith('/posts')),
      isFalse,
    );
    // Suggestions ask for a handful of rows, not thousands.
    final churchReq = fakeSupabaseRequests.lastWhere(
      (r) => r.url.path.endsWith('/churches'),
    );
    expect(churchReq.url.queryParameters['limit'], '3');

    await t.testTextInput.receiveAction(TextInputAction.search);
    await _settle(t);
    final full = fakeSupabaseRequests
        .where((r) => r.url.path.endsWith('/churches'))
        .last;
    expect(full.url.queryParameters['limit'], '20');
    expect(
      fakeSupabaseRequests.any((r) => r.url.path.endsWith('/posts')),
      isTrue,
      reason: 'the full search runs on submit',
    );
    expect(find.text('Top'), findsOneWidget);
    expect(find.text('Pages'), findsWidgets);
    expect(t.takeException(), isNull);
    await t.pump(const Duration(seconds: 2));
  });

  test('a Bible reference becomes a verse jump', () async {
    setFakeSupabaseHandler((_) => const <Object>[]);
    final hits = await SearchTypeaheadService.suggest('John 3:16');
    final verse = hits.where((h) => h.kind == SearchHitKind.verse).toList();
    expect(verse, hasLength(1));
    expect(verse.single.title, 'John 3:16');
  });

  test('a plain name is never read as a verse', () async {
    setFakeSupabaseHandler((_) => const <Object>[]);
    final hits = await SearchTypeaheadService.suggest('John');
    expect(hits.where((h) => h.kind == SearchHitKind.verse), isEmpty);
  });

  test('a phrase finds the verse that says it, not a near miss', () async {
    setFakeSupabaseHandler((_) => const <Object>[]);
    final hits = await SearchTypeaheadService.suggest('love one another');
    final verses = [
      for (final h in hits)
        if (h.kind == SearchHitKind.verse) h.title,
    ];
    // Plain substring matching used to return Deuteronomy 21:15 ("beloved").
    expect(verses, contains('John 13:34'));
    expect(verses.every((v) => !v.startsWith('Deuteronomy')), isTrue);
    final first = hits.firstWhere((h) => h.kind == SearchHitKind.verse);
    expect(first.preview, contains('love one another'));
  });

  test('a verse reference carries its text', () async {
    setFakeSupabaseHandler((_) => const <Object>[]);
    final hits = await SearchTypeaheadService.suggest('John 3:16');
    final v = hits.firstWhere((h) => h.kind == SearchHitKind.verse);
    expect(v.preview, contains('God so loved the world'));
  });

  test('suggested people carry their real mutual friend count', () async {
    setFakeSupabaseHandler((req) {
      final path = req.url.path;
      if (path.endsWith('/profiles')) {
        return [
          {'id': 'u9', 'full_name': 'Rudo Chikore', 'username': 'rudo'},
        ];
      }
      if (path.endsWith('/rpc/mutual_friends')) {
        return [
          {'id': 'x', 'full_name': 'X', 'total': 4},
        ];
      }
      return const <Object>[];
    });
    final hits = await SearchTypeaheadService.suggest('rudo');
    final p = hits.firstWhere((h) => h.kind == SearchHitKind.person);
    expect(p.mutualFriends, 4);
  });

  test('Recent remembers what was opened, newest first, and resets', () async {
    SearchHistoryService.reset();
    const a = SearchHit(kind: SearchHitKind.person, id: '1', title: 'A');
    const b = SearchHit(kind: SearchHitKind.page, id: '2', title: 'B');
    const verse = SearchHit(kind: SearchHitKind.verse, id: 'v', title: 'J');
    await SearchHistoryService.add(a);
    await SearchHistoryService.add(b);
    await SearchHistoryService.add(a);
    await SearchHistoryService.add(verse);
    expect(SearchHistoryService.items.value.map((h) => h.id), ['1', '2']);
    SearchHistoryService.reset();
    expect(SearchHistoryService.items.value, isEmpty);
  });
}
