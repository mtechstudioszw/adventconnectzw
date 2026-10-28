// Renders real screens to PNGs so design changes can be looked at without
// a device. NOT part of the test suite (lives outside test/). Run:
//
//   flutter test test_screens/<file>_shot.dart
//
// Output goes to $SHOT_DIR (default: build/shots). Fonts are the bundled
// Poppins + Material Icons, so text and icons render as on a phone; network
// images do not load (no HTTP in tests) and show their placeholders.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:advent_connect_zw/theme/app_text_styles.dart';
import 'package:advent_connect_zw/theme/app_theme.dart';
import 'package:advent_connect_zw/widgets/ambient_background.dart';

Future<void> loadShotFonts() async {
  GoogleFonts.config.allowRuntimeFetching = false;
  Future<void> load(String family, String path) async {
    final bytes = await File(path).readAsBytes();
    final loader = FontLoader(family)
      ..addFont(Future.value(ByteData.view(bytes.buffer)));
    await loader.load();
  }

  const fonts = 'assets/fonts';
  for (final w in ['400', 'regular']) {
    await load('Poppins_$w', '$fonts/Poppins-Regular.ttf');
  }
  await load('Poppins_500', '$fonts/Poppins-Medium.ttf');
  await load('Poppins_600', '$fonts/Poppins-SemiBold.ttf');
  await load('Poppins_700', '$fonts/Poppins-Bold.ttf');
  await load('Poppins_800', '$fonts/Poppins-Bold.ttf');
  await load('Poppins', '$fonts/Poppins-Regular.ttf');
  final sdk = Platform.environment['FLUTTER_ROOT'] ?? '/opt/sdk/flutter';
  await load(
    'MaterialIcons',
    '$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  final roboto = '$sdk/bin/cache/artifacts/material_fonts';
  await load('Roboto', '$roboto/Roboto-Regular.ttf');

  // The image cache wants a folder. Photos still can't load (no network).
  final tmp = Directory.systemTemp.createTempSync('shots');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => tmp.path,
      );
}

final _boundary = GlobalKey();

/// Pumps [screen] the way the app shows it: dark theme, ambient field
/// behind, a phone-sized view with a status-bar inset.
Future<void> pumpShot(
  WidgetTester t,
  Widget screen, {
  Size size = const Size(412, 892),
  bool dark = true,
}) async {
  // Sample photo URLs can't load here; that must not fail the shot.
  final onError = FlutterError.onError;
  FlutterError.onError = (d) {
    if (d.library == 'image resource service') return;
    onError?.call(d);
  };
  addTearDown(() => FlutterError.onError = onError);
  t.view.physicalSize = size * 2.0;
  t.view.devicePixelRatio = 2.0;
  t.view.padding = const FakeViewPadding(top: 48, bottom: 32);
  addTearDown(t.view.reset);
  // main.dart does this before every MaterialApp build; without it every
  // direct AppTextStyles use keeps light-mode text colours.
  AppTextStyles.applyBrightness(dark ? Brightness.dark : Brightness.light);
  await t.pumpWidget(
    RepaintBoundary(
      key: _boundary,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        builder: (context, child) => AmbientBackground(child: child!),
        home: screen,
      ),
    ),
  );
}

/// Lets fake HTTP and animations settle, then writes `<name>.png`.
Future<void> saveShot(WidgetTester t, String name, {int rounds = 8}) async {
  for (var i = 0; i < rounds; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await t.pump(const Duration(milliseconds: 250));
  }
  final dir = Platform.environment['SHOT_DIR'] ?? 'build/shots';
  await t.runAsync(() async {
    final boundary =
        _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1.0);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(dir).create(recursive: true);
    await File('$dir/$name.png').writeAsBytes(png!.buffer.asUint8List());
  });
  // Drain retry timers (postgrest, image cache) before the test ends.
  await t.pump(const Duration(seconds: 30));
}
