// The church profile carries both of the avatar traps from the notes at
// once: Container(alignment:) hands its child LOOSE constraints (an
// unsized image floats inside its circle and leaves a rim), while
// CachedImage hands its errorBuilder TIGHT ones (a bare child paints
// top-left). Full APK builds aren't possible on the dev machine, so this
// is what proves the hero lays out.
//
// It also pins the thing that was actually wrong: NO church in production
// has a logo, and the avatar used to render nothing at all in that case,
// so the identity slot simply wasn't on the page for any real church.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/models/church_model.dart';
import 'package:advent_connect_zw/screens/churches/church_details_screen.dart';
import 'package:advent_connect_zw/theme/app_theme.dart';

Church _church({String? logo, String? cover}) => Church(
      id: 'c1',
      name: 'Harare City Centre Seventh-day Adventist Church',
      city: 'Harare',
      membersCount: 42,
      profilePhotoUrl: logo,
      coverPhotoUrl: cover,
    );

Widget _wrap(Church church, {double textScale = 1.0}) => MaterialApp(
      theme: AppTheme.light,
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: ChurchDetailsScreen(
          churchId: church.id,
          initialChurch: church,
          autoLoad: false,
        ),
      ),
    );

void main() {
  testWidgets('an unbranded church still gets an avatar', (t) async {
    await t.pumpWidget(_wrap(_church()));
    await t.pump();

    // The glyph placeholder, not an empty gap. Every church in production
    // is currently in this state.
    expect(find.byIcon(Icons.church), findsWidgets);
    expect(t.takeException(), isNull);
  });

  for (final scale in <double>[1.0, 1.6, 2.5]) {
    testWidgets('hero lays out on a 360x640 phone at ${scale}x', (t) async {
      t.view.physicalSize = const Size(360, 640);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);

      await t.pumpWidget(_wrap(_church(), textScale: scale));
      await t.pump();

      expect(t.takeException(), isNull);
    });
  }

  testWidgets('the cover matches the 16:9 the admin uploads against',
      (t) async {
    t.view.physicalSize = const Size(360, 800);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);

    // Must pass a cover: there is no 16:9 box at all without one now, by
    // design (see the no-cover test below).
    await t.pumpWidget(_wrap(_church(cover: 'https://example.test/c.jpg')));
    await t.pump();

    // edit_church_screen frames the admin's cover at 16:9. The public
    // profile used to render a fixed 180dp at full width — ~2:1 on this
    // phone — so the composition they arranged was cropped top and bottom.
    final cover = t.widget<AspectRatio>(
      find.byType(AspectRatio).first,
    );
    expect(cover.aspectRatio, closeTo(16 / 9, 0.001));
  });

  // A missing cover photo is not a reason to paint a navy rectangle
  // (founder rule, 28 Jul 2026; re-confirmed for churches 17 Aug). This
  // one matters more than the profile version it came from: NO church in
  // production has a cover photo, so the placeholder was not an edge case
  // — it was the hero on every church, a navy slab across the top ~26% of
  // the screen ending in a hard seam.
  group('no cover photo', () {
    testWidgets('paints no 16:9 slab at all', (t) async {
      await t.pumpWidget(_wrap(_church()));
      await t.pump();

      expect(
        find.byType(AspectRatio),
        findsNothing,
        reason: 'the no-cover hero must not reserve a 16:9 band',
      );
      expect(t.takeException(), isNull);
    });

    testWidgets('lifts the name above the fold on a small phone', (t) async {
      t.view.physicalSize = const Size(360, 640);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);

      await t.pumpWidget(_wrap(_church()));
      await t.pump();

      // The whole point of removing the slab: the identity and the primary
      // action come up the screen. The slab was ~200dp on this phone.
      final name = t.getTopLeft(find.textContaining('Harare City Centre'));
      expect(
        name.dy,
        lessThan(240),
        reason: 'church name should sit high without a cover slab',
      );
    });

    testWidgets('the back arrow survives the flattening', (t) async {
      // The standing trap: flattening a navy surface breaks every
      // foreground that assumed a dark backdrop. This arrow was white on a
      // 40%-black scrim, which is invisible on light grey.
      await t.pumpWidget(_wrap(_church()));
      await t.pump();

      final arrow = t.widget<Icon>(find.byIcon(Icons.arrow_back));
      expect(arrow.color, isNot(const Color(0xFFFFFFFF)));
      expect(
        arrow.color!.computeLuminance(),
        lessThan(0.5),
        reason: 'back arrow must be dark on the light scaffold',
      );
    });
  });
}
