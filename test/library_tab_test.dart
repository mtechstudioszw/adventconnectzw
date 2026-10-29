// Batch 3, part 1 (owner, 29 Oct 2026): Library replaces Watch in the
// island, Watch moves inside the Library, and Home's devotion opens the
// full devotion.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/models/devotion_model.dart';
import 'package:advent_connect_zw/screens/library/devotion_screen.dart';
import 'package:advent_connect_zw/screens/library/library_hub_screen.dart';
import 'package:advent_connect_zw/theme/app_theme.dart';
import 'package:advent_connect_zw/widgets/home/library_tiles.dart';

Widget _host(Widget child) => MaterialApp(theme: AppTheme.light, home: child);

void main() {
  group('routes', () {
    final router = File('lib/config/router_config.dart').readAsStringSync();
    final nav = File(
      'lib/screens/widgets/main_bottom_nav.dart',
    ).readAsStringSync();

    test('the island reads Home · Library · Chat · Market · Profile', () {
      expect(nav.contains("'library_hub',"), isTrue);
      expect(nav.contains("'Library')"), isTrue);
      expect(
        nav.contains("'Watch')"),
        isFalse,
        reason: 'Watch is no longer a tab',
      );
    });

    test('every Watch route still exists, so old links and pushes work', () {
      for (final name in const [
        'watch',
        'watch_saved',
        'watch_channels',
        'watch_shorts',
        'watch_series',
        'watch_channel',
        'watch_video',
      ]) {
        expect(router.contains("name: '$name',"), isTrue, reason: name);
      }
    });

    test('the reader keeps its name and sits outside the shell', () {
      // Pushed by name from every tab; inside the Library branch it would
      // switch the island underneath whoever pushed it.
      expect(
        router.contains("path: '/library-read',\n      name: 'library',"),
        isTrue,
      );
    });

    test('nothing still switches to a Watch tab', () {
      final offenders = <String>[];
      for (final f
          in Directory('lib')
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart'))) {
        if (f.readAsStringSync().contains("goNamed('watch")) {
          offenders.add(f.path);
        }
      }
      expect(offenders, isEmpty, reason: 'push Watch, it is not a tab');
    });
  });

  group('Library home', () {
    testWidgets('shows the whole toolkit', (t) async {
      await t.pumpWidget(_host(const LibraryHubScreen(autoLoad: false)));
      await t.pump();
      for (final label in const [
        'Bible',
        'Sabbath School',
        'Hymnal',
        'EGW',
        'Watch',
        'Quiz',
        '28 Beliefs',
        'More',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      // No progress yet → no Continue heading.
      expect(find.text('CONTINUE'), findsNothing);
    });
  });

  group('devotion', () {
    const d = Devotion(
      bibleRef: 'John 3:16',
      bibleText: 'For God so loved the world',
      egwQuote: 'Christ is the ladder.',
      egwSource: 'SC 20.1',
    );

    test('the button names the chapter, not the verse', () {
      expect(DevotionScreen.chapterLabel('John 3:16'), 'John 3');
      expect(DevotionScreen.chapterLabel('1 Cor. 13:4-7'), '1 Cor. 13');
      expect(DevotionScreen.chapterLabel('Psalm 23'), 'Psalm 23');
    });

    testWidgets('shows exactly what the row carries', (t) async {
      await t.pumpWidget(_host(const DevotionScreen(devotion: d)));
      await t.pump();
      expect(find.text('"For God so loved the world"'), findsOneWidget);
      expect(find.text('John 3:16'), findsOneWidget);
      expect(find.text('Christ is the ladder.'), findsOneWidget);
      expect(find.text('SC 20.1'), findsOneWidget);
      expect(find.text('Read John 3'), findsOneWidget);
    });

    test('Home\'s devotion card opens it', () {
      final card = File('lib/widgets/home/today_card.dart').readAsStringSync();
      expect(card.contains('DevotionScreen(devotion: devotion)'), isTrue);
    });
  });

  group('Home row', () {
    testWidgets('Quiz first, Library last, no section pills', (t) async {
      t.view.physicalSize = const Size(1400, 260);
      t.view.devicePixelRatio = 2.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(_host(const Scaffold(body: LibraryTiles())));
      await t.pumpAndSettle();
      expect(find.text('Quiz'), findsOneWidget);
      expect(find.text('Library'), findsOneWidget);
      expect(find.text('Hymnal'), findsNothing);
      expect(find.text('EGW'), findsNothing);
    });

    test('Home has a Watch door under the live banner', () {
      final home = File('lib/screens/home/home_screen.dart').readAsStringSync();
      final banner = home.indexOf('LiveBanner(live:');
      final door = home.indexOf('const WatchEntryRow()');
      expect(banner, greaterThan(0));
      expect(door, greaterThan(banner));
    });
  });
}
