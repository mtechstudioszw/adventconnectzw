import 'package:advent_connect_zw/services/quiz_sfx.dart';
import 'package:flutter_test/flutter_test.dart';

/// The volume floor (#3 A1, 3 Aug 2026).
///
/// The arena's volume slider had `min: 0.0` with 10 divisions, so one drag
/// to 0% persisted "0.00" to `quiz_sfx_volume`. Every clip then played at
/// volume zero, in that session and every session after it, while the mute
/// button still read UNMUTED — there was nothing on screen to explain it
/// and no reason to suspect the slider. That is indistinguishable from
/// "the quiz has no sound", which is how it was reported.
///
/// Silence now belongs solely to the mute button, which has an icon and an
/// obvious way back.
///
/// CacheService's Hive box is never opened under the test binding, so
/// setVolume's persistence is a no-op here and this exercises the clamp,
/// which is the part that was wrong.
void main() {
  test('the slider floor is above silence', () {
    expect(QuizSfx.kMinVolume, greaterThan(0.0));
  });

  test('setVolume refuses to latch the arena at silent', () async {
    await QuizSfx.setVolume(0);

    expect(QuizSfx.volume, QuizSfx.kMinVolume);
    expect(QuizSfx.volume, greaterThan(0.0));
  });

  test('a negative or absurd value cannot get through either', () async {
    await QuizSfx.setVolume(-5);
    expect(QuizSfx.volume, QuizSfx.kMinVolume);

    await QuizSfx.setVolume(99);
    expect(QuizSfx.volume, 1.0);
  });

  test('ordinary values are still honoured exactly', () async {
    await QuizSfx.setVolume(0.5);
    expect(QuizSfx.volume, closeTo(0.5, 0.0001));

    await QuizSfx.setVolume(1.0);
    expect(QuizSfx.volume, 1.0);
  });

  test('muting is what silences the arena, not the volume control', () {
    // Kept explicit: these are two different controls and the fix depends
    // on mute remaining the only route to actual silence.
    expect(QuizSfx.muted, isFalse);
    expect(QuizSfx.volume, greaterThan(0.0));
  });
}
