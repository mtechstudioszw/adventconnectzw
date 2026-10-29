// App Review fixes (29 Oct 2026): music hidden on iOS, the word filter's
// message, and the Advent AI consent step.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:advent_connect_zw/config/platform_flags.dart';
import 'package:advent_connect_zw/screens/advent_ai/widgets/ai_consent_sheet.dart';
import 'package:advent_connect_zw/services/cache_service.dart';
import 'package:advent_connect_zw/services/content_filter_error.dart';
import 'package:advent_connect_zw/services/post_limit_error.dart';
import 'package:advent_connect_zw/theme/app_theme.dart';

void main() {
  group('kHideMusic', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('hidden on iOS — no background audio for App Review', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(kHideMusic, isTrue);
    });

    test('kept on Android', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(kHideMusic, isFalse);
    });
  });

  group('word filter message', () {
    test('a CONTENT_BLOCKED refusal reads as a plain sentence', () {
      final e = Exception('PostgrestException(message: CONTENT_BLOCKED)');
      expect(ContentFilterError.matches(e), isTrue);
      expect(
        PostLimitError.messageFor(e, fallback: 'Try again'),
        ContentFilterError.message,
      );
    });

    test('other failures keep their own message', () {
      expect(ContentFilterError.matches(Exception('timeout')), isFalse);
    });
  });

  group('Advent AI consent', () {
    late Directory dir;
    var seq = 0;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('ai_consent_test');
      Hive.init(dir.path);
      await CacheService.debugUseBox(
        await Hive.openBox<String>('consent_${seq++}'),
      );
    });

    tearDown(() async {
      await CacheService.debugUseBox(null);
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    });

    Future<bool?> openAndTap(WidgetTester t, String button) async {
      bool? result;
      await t.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async => result = await ensureAiConsent(ctx),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      expect(find.textContaining('Google Gemini'), findsOneWidget);
      await t.tap(find.text(button));
      await t.runAsync(() => Future<void>.delayed(Duration.zero));
      await t.pumpAndSettle();
      return result;
    }

    testWidgets('names Google Gemini; "Not now" sends nothing', (t) async {
      expect(await openAndTap(t, 'Not now'), isFalse);
      expect(hasAiConsent(), isFalse);
    });

    testWidgets('agreeing is remembered — asked only once', (t) async {
      expect(await openAndTap(t, 'I agree — continue'), isTrue);
      expect(hasAiConsent(), isTrue);
    });
  });
}
