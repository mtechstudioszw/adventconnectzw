import 'dart:io';

import 'package:advent_connect_zw/services/cache_service.dart';
import 'package:advent_connect_zw/theme/app_theme.dart';
import 'package:advent_connect_zw/widgets/home/composer_sheet.dart'
    show postDraftKey;
import 'package:advent_connect_zw/widgets/home/create_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

/// The create studio's features (28 Oct 2026): each shortcut must come back
/// to Home as the right request, and an autosaved draft must surface on
/// the canvas instead of staying hidden inside the composer.
Future<CreateRequest?> _pick(WidgetTester t, Finder target) async {
  CreateRequest? chosen;
  await t.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Builder(
          builder: (ctx) => Center(
            child: ElevatedButton(
              onPressed: () async => chosen = await showCreateSheet(ctx),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await t.tap(find.text('open'));
  await t.pump();
  await t.pump(const Duration(milliseconds: 700));
  await t.ensureVisible(target);
  await t.pump();
  await t.tap(target);
  await t.pump(const Duration(milliseconds: 700));
  return chosen;
}

void main() {
  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(400, 860);
    view.devicePixelRatio = 1.0;
  });
  tearDown(() {
    TestWidgetsFlutterBinding.instance.platformDispatcher.views.first.reset();
  });

  testWidgets('Write opens a plain post', (t) async {
    final r = await _pick(t, find.text('Write'));
    expect(r?.kind, CreateKind.post);
    expect(r?.initialText, isNull);
    expect(r?.pickPhoto, isFalse);
  });

  testWidgets('Photo opens a post straight on the picker', (t) async {
    final r = await _pick(t, find.text('Photo'));
    expect(r?.kind, CreateKind.post);
    expect(r?.pickPhoto, isTrue);
  });

  testWidgets('Photo story opens a story on the picker', (t) async {
    final r = await _pick(t, find.text('Photo story'));
    expect(r?.kind, CreateKind.story);
    expect(r?.pickPhoto, isTrue);
  });

  testWidgets('Text story opens a text story', (t) async {
    final r = await _pick(t, find.text('Text story'));
    expect(r?.kind, CreateKind.story);
    expect(r?.pickPhoto, isFalse);
  });

  testWidgets('a starter seeds the post with its opener', (t) async {
    final r = await _pick(t, find.text('Testimony'));
    expect(r?.kind, CreateKind.post);
    expect(r?.initialText, startsWith('I want to share what God did'));
  });

  testWidgets('no verse button without a cached devotion', (t) async {
    // Offering "Today's verse" and then opening an empty post would be a
    // button that lies.
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => showCreateSheet(ctx),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 700));
    expect(find.text("Today's verse"), findsNothing);
  });

  group('with a saved draft', () {
    late Directory dir;
    var seq = 0;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('create_studio_test');
      Hive.init(dir.path);
      await CacheService.debugUseBox(
        await Hive.openBox<String>('studio_${seq++}'),
      );
    });

    tearDown(() async {
      await CacheService.debugUseBox(null);
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    });

    testWidgets('the canvas shows it and offers Continue', (t) async {
      await t.runAsync(
        () => CacheService.writeString(
          postDraftKey(),
          '{"body":"Half-written thoughts on Sabbath","images":["a","b"]}',
        ),
      );
      final r = await _pick(t, find.text('Continue'));
      expect(r?.kind, CreateKind.post);
    });

    testWidgets('draft text and photo count are on the canvas', (t) async {
      await t.runAsync(
        () => CacheService.writeString(
          postDraftKey(),
          '{"body":"Half-written thoughts on Sabbath","images":["a","b"]}',
        ),
      );
      await t.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => showCreateSheet(ctx),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await t.tap(find.text('open'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 700));
      expect(find.text('DRAFT'), findsOneWidget);
      expect(find.text('Half-written thoughts on Sabbath'), findsOneWidget);
      expect(find.text('2 photos'), findsOneWidget);
      expect(find.text('Write'), findsNothing);
    });
  });
}
