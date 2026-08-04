import 'dart:io';

import 'package:advent_connect_zw/screens/settings/sound_settings_screen.dart';
import 'package:advent_connect_zw/services/cache_service.dart';
import 'package:advent_connect_zw/services/quiz_music.dart';
import 'package:advent_connect_zw/services/quiz_sfx.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

/// Reported 3 Aug 2026: *"settings of quiz — all buttons there are not
/// working, both the setting inside quiz and the setting in main settings."*
///
/// They were being read, not written. `QuizSfx` loaded its stored
/// preferences **only inside `init()`**, which builds the whole audio pool
/// and is called when the ARENA opens. `QuizMusic` was the same, behind a
/// private `_loadPrefs()` that only its setters called. Neither getter
/// touched storage.
///
/// So opening Settings → Sound & haptics without having entered the quiz
/// first showed the compiled-in defaults — every switch ON — no matter what
/// was actually saved. Someone who had muted the arena saw "Sound
/// effects: ON", left it alone because it already looked right, and got a
/// silent quiz. From the outside that is exactly "the setting does not
/// work", and it is also a way the quiz ends up silent with the UI
/// insisting it should not be.
///
/// The second half is [CacheService.clearUserData], which keeps `pref:`
/// keys and deletes everything else. These five keys had no prefix, so
/// every sign-out silently reset the member's sound settings.
void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('quiz_prefs_test');
    Hive.init(dir.path);
    await CacheService.debugUseBox(await Hive.openBox<String>('test_box'));
    QuizSfx.resetForTest();
    QuizMusic.resetForTest();
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await CacheService.debugUseBox(null);
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  testWidgets('the screen shows what was actually saved', (tester) async {
    // A member who muted the arena and turned the soundtrack off.
    //
    // runAsync() is load-bearing, and its absence is what hung CI for a
    // whole day. `testWidgets` runs its body inside a FAKE-ASYNC zone: the
    // clock is controlled by pump(), and a Future that depends on real I/O
    // never completes because nothing is driving the real event loop. These
    // three calls write to Hive — actual disk — so awaiting them directly
    // wedges the test forever.
    //
    // The failure mode is nasty: the job does not error, it just stops
    // making progress, and the two tests below get reported as "did not
    // complete" as collateral. `flutter analyze` stays clean, so it sailed
    // through review and only ever showed up as a build that never ended.
    //
    // The plain `test()` cases in this file are unaffected — no fake async
    // there, which is exactly why they pass in isolation and hang in the
    // suite once this one has wedged the runner.
    await tester.runAsync(() async {
      await QuizSfx.setMuted(true);
      await QuizSfx.setVolume(0.4);
      await QuizMusic.setEnabled(false);
    });

    // Fresh launch: nothing has opened the arena, so nothing has called
    // QuizSfx.init(). This is the ordinary path to the settings screen.
    QuizSfx.resetForTest();
    QuizMusic.resetForTest();

    await tester.pumpWidget(const MaterialApp(home: SoundSettingsScreen()));
    // pump(), NOT pumpAndSettle().
    //
    // This is what hung CI. `pumpAndSettle` waits for the widget tree to go
    // quiet, and something on this screen animates continuously — so it
    // never settles and instead sits out its DEFAULT TIMEOUT, which is TEN
    // MINUTES. The whole suite then took just over ten minutes and the two
    // tests below were reported as "did not complete" purely as collateral.
    //
    // From the outside that looked like a hung build rather than a failing
    // test, which is why it survived a push: `flutter analyze` was clean and
    // the job simply stopped making progress.
    //
    // Two frames is all this test needs. It asserts what the controls read
    // on FIRST build from stored preferences — there is no animation to wait
    // for and nothing async to settle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
    expect(
      switches[0].value,
      isFalse,
      reason: 'sound effects were muted, so the switch must read off',
    );
    expect(
      switches[1].value,
      isFalse,
      reason: 'the soundtrack was turned off, so the switch must read off',
    );

    final sliders = tester.widgetList<Slider>(find.byType(Slider)).toList();
    expect(sliders.first.value, closeTo(0.4, 0.0001));
  });

  test('the arena honours a stored mute without opening settings first', () async {
    await QuizSfx.setMuted(true);
    QuizSfx.resetForTest();

    // What the round screen effectively asks before it plays anything.
    QuizSfx.loadPrefs();
    expect(QuizSfx.muted, isTrue);
  });

  test('sound settings survive a sign-out', () async {
    await QuizSfx.setMuted(true);
    await QuizSfx.setHapticsEnabled(false);
    await QuizMusic.setEnabled(false);

    // Sign-out wipes cached payloads but must spare device preferences.
    await CacheService.clearUserData();

    QuizSfx.resetForTest();
    QuizMusic.resetForTest();
    QuizSfx.loadPrefs();
    QuizMusic.loadPrefs();

    expect(QuizSfx.muted, isTrue, reason: 'a device setting, not user data');
    expect(QuizSfx.hapticsEnabled, isFalse);
    expect(QuizMusic.enabled, isFalse);
  });
}
