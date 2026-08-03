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
    await QuizSfx.setMuted(true);
    await QuizSfx.setVolume(0.4);
    await QuizMusic.setEnabled(false);

    // Fresh launch: nothing has opened the arena, so nothing has called
    // QuizSfx.init(). This is the ordinary path to the settings screen.
    QuizSfx.resetForTest();
    QuizMusic.resetForTest();

    await tester.pumpWidget(const MaterialApp(home: SoundSettingsScreen()));
    await tester.pumpAndSettle();

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
