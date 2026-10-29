import 'package:advent_connect_zw/models/post_model.dart';
import 'package:advent_connect_zw/theme/app_theme.dart';
import 'package:advent_connect_zw/widgets/home/post_preview_sheet.dart';
import 'package:advent_connect_zw/widgets/preview_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The publish preview's proofing desk (28 Oct 2026): Light/Dark and
/// Large-text re-render the REAL card, and the checklist says what the card
/// can't show.
class _Probe extends StatelessWidget {
  const _Probe();
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scale = MediaQuery.textScalerOf(context).scale(10) / 10;
    return Text('card ${dark ? 'dark' : 'light'} ${scale.toStringAsFixed(1)}');
  }
}

Future<void> _open(
  WidgetTester t, {
  List<PreviewNote> notes = const [],
  Color? canvas,
}) async {
  t.view.physicalSize = const Size(400, 860);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Builder(
        builder: (ctx) => ElevatedButton(
          onPressed: () => showEntityPreview(
            ctx,
            title: 'How it will look',
            confirmLabel: 'Post it',
            notes: notes,
            canvasColor: canvas,
            child: const _Probe(),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await t.tap(find.text('open'));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('Dark re-renders the card in the dark theme', (t) async {
    await _open(t);
    expect(find.text('card light 1.0'), findsOneWidget);
    await t.tap(find.text('Dark'));
    await t.pumpAndSettle();
    expect(find.text('card dark 1.0'), findsOneWidget);
  });

  testWidgets('Large text re-renders at 1.3x', (t) async {
    await _open(t);
    await t.tap(find.text('Large text'));
    await t.pumpAndSettle();
    expect(find.text('card light 1.3'), findsOneWidget);
  });

  testWidgets('a fixed canvas hides the theme switch', (t) async {
    await _open(t, canvas: const Color(0xFF0D1B3E));
    expect(find.text('Dark'), findsNothing);
    expect(find.text('Large text'), findsOneWidget);
  });

  testWidgets('notes render under the card', (t) async {
    await _open(
      t,
      notes: const [PreviewNote(Icons.timer_outlined, 'Gone in 24 hours.')],
    );
    expect(find.text('BEFORE YOU PUBLISH'), findsOneWidget);
    expect(find.text('Gone in 24 hours.'), findsOneWidget);
  });

  test('post notes: identity, audience, photos, length', () {
    final notes = postPreviewNotes(
      body: 'x' * 1900,
      photos: 3,
      visibility: PostVisibility.friendsOnly,
      pageName: 'Youth Choir',
    ).map((n) => n.label).toList();
    expect(notes, contains('Posting as Youth Choir.'));
    expect(notes, contains('Only your friends can see it.'));
    expect(notes, contains('3 photos — swipe the card to check each crop.'));
    expect(notes.last, startsWith('1900 of 2,000'));

    final plain = postPreviewNotes(
      body: 'hi',
      photos: 0,
      visibility: PostVisibility.public,
    ).map((n) => n.label).toList();
    expect(plain, [
      'Posting as you.',
      'Anyone on Adventist Super App can see it.',
    ]);
  });
}
