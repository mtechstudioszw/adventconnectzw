// Founder, 19 Aug 2026: *"tt sabbath school error comes when reading n u
// click the pencil icon n click back the screens turns red with tt error"* —
// the `'_dependents.isEmpty': is not true` assertion at framework.dart:6268.
//
// His repro is the whole diagnosis. The pencil opens the note editor, and
// the editor used to be a plain `builder:` closure over a controller created
// beside it:
//
//     final controller = TextEditingController(...);
//     await showModalBottomSheet(...);
//     controller.dispose();
//
// `showModalBottomSheet`'s future completes when the route is POPPED, not
// when it has finished leaving. The sheet is mounted for the whole exit
// transition, so `dispose()` ran on a controller a live `EditableText` was
// still listening to — and the field then failed on its way out while it
// was still registered as a dependent of the inherited widgets it had read.
// `InheritedElement.debugDeactivated()` asserts that no dependents remain,
// so the screen went red. `autofocus: true` is why it happened every time
// rather than occasionally: the field being torn down was always focused.
//
// These tests pump the exit transition rather than jumping past it, which
// is the only way the old code fails and the new code does not.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:advent_connect_zw/models/sabbath_school_model.dart';
import 'package:advent_connect_zw/screens/library/ss_lesson_screen.dart';
import 'package:advent_connect_zw/services/cache_service.dart';
import 'package:advent_connect_zw/theme/app_theme.dart';

const _days = [
  SsDay(
    id: '01',
    title: 'Sabbath Afternoon',
    readPath: 'en/quarterlies/2026-03/lessons/05/days/01/read',
  ),
  SsDay(
    id: '02',
    title: 'Sunday',
    readPath: 'en/quarterlies/2026-03/lessons/05/days/02/read',
  ),
];

Widget _host() => MaterialApp(
  theme: AppTheme.light,
  home: const SsDayReaderScreen(
    lang: 'en',
    quarterlyId: '2026-03',
    quarterlyTitle: 'A Quarter',
    lessonId: '05',
    lessonTitle: 'A Week',
    days: _days,
    initialIndex: 0,
  ),
);

void main() {
  late Directory dir;
  var boxSeq = 0;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ss_note_sheet');
    Hive.init(dir.path);
    await CacheService.debugUseBox(
      await Hive.openBox<String>('ss_notes_${boxSeq++}'),
    );
  });

  tearDown(() async {
    await CacheService.debugUseBox(null);
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  Future<void> openNote(WidgetTester t) async {
    await t.pumpWidget(_host());
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));

    await t.tap(find.byIcon(Icons.edit_note_rounded));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.byType(TextField), findsOneWidget);
  }

  testWidgets('dismissing the note sheet does not blow up on the way out',
      (t) async {
    await openNote(t);

    // Back, exactly as he described. The frames after the pop are the whole
    // point — the old crash happened DURING the exit transition, so a test
    // that settles straight past it would have seen nothing.
    Navigator.of(t.element(find.byType(TextField))).pop();
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
    await t.pump(const Duration(milliseconds: 100));
    await t.pumpAndSettle();

    expect(t.takeException(), isNull);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('saving a note does not blow up either', (t) async {
    await openNote(t);

    await t.enterText(find.byType(TextField), 'This stood out to me.');
    await t.tap(find.text('Save note'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
    await t.pumpAndSettle();

    expect(t.takeException(), isNull);
    // Deliberately unprefixed — a note is the member's own writing, so
    // sign-out clearing it is correct.
    expect(
      CacheService.readPref('ss_notes_v1'),
      contains('This stood out to me.'),
    );
  });

  testWidgets('the note comes back when the sheet is reopened', (t) async {
    await openNote(t);
    await t.enterText(find.byType(TextField), 'Remember this.');
    await t.tap(find.text('Save note'));
    await t.pumpAndSettle();

    await t.tap(find.byIcon(Icons.edit_note_rounded));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));

    expect(find.text('Remember this.'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('opening and dismissing repeatedly stays clean', (t) async {
    // A controller owned by the sheet must not survive it, and one owned by
    // the screen must not be disposed twice. Three rounds catches both.
    await t.pumpWidget(_host());
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));

    for (var i = 0; i < 3; i++) {
      await t.tap(find.byIcon(Icons.edit_note_rounded));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      Navigator.of(t.element(find.byType(TextField))).pop();
      await t.pump();
      await t.pumpAndSettle();
      expect(t.takeException(), isNull, reason: 'round $i');
    }
  });
}
