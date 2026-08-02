// The white-rim bug, pinned.
//
// Seven files hand-rolled a round avatar and six carried the same
// mistake: `Container(width: 44, height: 44, alignment: Alignment.center)`
// around an unsized image. `alignment` makes Container wrap its child in
// an Align, Align hands the child LOOSE constraints, and the photo then
// laid itself out at its own size and floated inside the circle — the
// "white edges" reported on 2 Aug 2026.
//
// Nothing throws when this regresses and no golden is involved, so what
// these tests assert is the contract that prevents it: the image is
// explicitly sized to the circle, and the fallback fills the circle
// rather than sitting in a corner of it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/theme/app_theme.dart';
import 'package:advent_connect_zw/widgets/cached_image.dart';
import 'package:advent_connect_zw/widgets/user_avatar.dart';

Future<void> _pump(WidgetTester t, Widget child) async {
  await t.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    // Centre gives the avatar LOOSE constraints — the situation the bug
    // needed. If UserAvatar leaned on a tight parent it would pass here
    // and still leave a rim in a ListTile's leading slot.
    home: Scaffold(body: Center(child: child)),
  ));
  await t.pump();
}

void main() {
  testWidgets('the photo is sized to the circle, not left to float',
      (t) async {
    await _pump(t, const UserAvatar(
      photoUrl: 'https://example.test/p.jpg',
      name: 'Tanatswa',
      size: 44,
    ));

    final image = t.widget<CachedImage>(find.byType(CachedImage));
    expect(image.width, 44);
    expect(image.height, 44);
    expect(image.fit, BoxFit.cover);

    // And the box it sits in is the full circle.
    expect(t.getSize(find.byType(UserAvatar)), const Size(44, 44));
  });

  testWidgets('the fallback fills the circle instead of sitting top-left',
      (t) async {
    await _pump(t, const UserAvatar(photoUrl: null, name: 'Rudo', size: 56));

    expect(find.byType(CachedImage), findsNothing);
    expect(t.getSize(find.byType(UserAvatar)), const Size(56, 56));

    // The initial is centred in the circle, not parked in a corner.
    final avatar = t.getRect(find.byType(UserAvatar));
    final initial = t.getRect(find.text('R'));
    expect(initial.center.dx, closeTo(avatar.center.dx, 0.5));
    expect(initial.center.dy, closeTo(avatar.center.dy, 0.5));
  });

  testWidgets('groups fall back to an icon, people to an initial', (t) async {
    await _pump(t, const UserAvatar(
      photoUrl: null,
      name: 'Youth Choir',
      fallbackIcon: Icons.groups,
      size: 104,
    ));

    expect(find.byIcon(Icons.groups), findsOneWidget);
    expect(find.text('Y'), findsNothing);
  });

  testWidgets('an empty or blank url takes the fallback path', (t) async {
    await _pump(t, const UserAvatar(photoUrl: '   ', name: 'Blank', size: 40));

    expect(find.byType(CachedImage), findsNothing);
    expect(find.text('B'), findsOneWidget);
  });

  testWidgets('a nameless avatar still renders', (t) async {
    await _pump(t, const UserAvatar(photoUrl: null, name: '', size: 40));

    expect(find.text('?'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
