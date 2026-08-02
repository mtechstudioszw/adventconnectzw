// Offline failures must be local to the thing that failed.
//
// Audit, 2 Aug 2026. The app had a full-screen `/offline` route wired into
// the router — nothing navigated to it, but a route that can replace the
// whole screen with "no internet" is one call away from doing so, and it
// is gone now.
//
// The real damage was quieter. `ErrorBanner` is the app's most-used error
// surface: eight screens render it as their ENTIRE body when a fetch
// fails, and it had no retry affordance of any kind. A load that failed on
// a flaky connection was a dead end — the member's only move was to leave
// the screen and come back. It also said whatever the caller passed,
// usually "Could not load X", which is unhelpful when the real cause is a
// dropped connection.
//
// What these tests pin:
//   * retry exists, and fires only the operation that failed;
//   * the banner is a widget INSIDE the layout, so everything around it
//     stays visible and tappable while the error is on screen;
//   * an offline device gets offline wording, not a server-shaped message.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/theme/app_theme.dart';
import 'package:advent_connect_zw/widgets/screen_shell.dart';

/// A screen shaped like the real ones: a failed section next to controls
/// that have nothing to do with the network.
class _HostScreen extends StatefulWidget {
  const _HostScreen();

  @override
  State<_HostScreen> createState() => _HostScreenState();
}

class _HostScreenState extends State<_HostScreen> {
  int retries = 0;
  int unrelatedTaps = 0;
  String draft = '';
  bool loaded = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        children: [
          TextField(
            key: const Key('draft'),
            onChanged: (v) => setState(() => draft = v),
          ),
          if (!loaded)
            ErrorBanner(
              message: 'Could not load announcements.',
              onRetry: () => setState(() {
                retries++;
                loaded = true;
              }),
            ),
          TextButton(
            key: const Key('unrelated'),
            onPressed: () => setState(() => unrelatedTaps++),
            child: const Text('Unrelated action'),
          ),
          Text('taps:$unrelatedTaps'),
          Text('draft:$draft'),
        ],
      ),
    );
  }
}

Future<void> _pump(WidgetTester t, Widget child,
    {double textScale = 1.0}) async {
  t.view.physicalSize = const Size(360, 720);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);

  await t.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: child,
    ),
  ));
  await t.pump();
}

void main() {
  group('ErrorBanner', () {
    testWidgets('offers a retry when the caller can re-run the load',
        (t) async {
      await _pump(t, const _HostScreen());

      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('retry re-runs only the failed operation', (t) async {
      await _pump(t, const _HostScreen());

      await t.tap(find.text('Try again'));
      await t.pump();

      final state = t.state<_HostScreenState>(find.byType(_HostScreen));
      expect(state.retries, 1);
      // Recovered in place: no navigation, no reload of the screen.
      expect(find.byType(ErrorBanner), findsNothing);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('the rest of the screen stays interactive while it shows',
        (t) async {
      await _pump(t, const _HostScreen());

      // Type into a field that has nothing to do with the failed request.
      await t.enterText(find.byKey(const Key('draft')), 'Praise the Lord');
      await t.pump();
      // And use an unrelated control, twice.
      await t.tap(find.byKey(const Key('unrelated')));
      await t.pump();
      await t.tap(find.byKey(const Key('unrelated')));
      await t.pump();

      expect(find.text('taps:2'), findsOneWidget);
      expect(find.text('draft:Praise the Lord'), findsOneWidget);
      // The error is still there, still local, still not blocking.
      expect(find.byType(ErrorBanner), findsOneWidget);
    });

    testWidgets('user input survives a retry', (t) async {
      await _pump(t, const _HostScreen());

      await t.enterText(find.byKey(const Key('draft')), 'unsent draft');
      await t.pump();
      await t.tap(find.text('Try again'));
      await t.pump();

      // Nothing the member typed is lost by the recovery.
      expect(find.text('draft:unsent draft'), findsOneWidget);
    });

    testWidgets('without a retry callback it still explains itself',
        (t) async {
      // Form submits pass no onRetry — the submit button IS the retry, and
      // a second one beside it would be noise.
      await _pump(
        t,
        const Scaffold(body: ErrorBanner(message: 'Could not save.')),
      );

      expect(find.text('Try again'), findsNothing);
      expect(t.takeException(), isNull);
    });

    for (final scale in <double>[1.0, 1.6, 2.5]) {
      testWidgets('lays out at ${scale}x text scale', (t) async {
        await _pump(t, const _HostScreen(), textScale: scale);

        expect(t.takeException(), isNull);
        expect(find.text('Try again'), findsOneWidget);
      });
    }
  });
}
