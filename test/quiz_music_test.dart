import 'package:advent_connect_zw/services/quiz_music.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Quiz Arena soundtrack (#3 A2).
///
/// The decision of WHETHER to play is the part worth pinning — the
/// playback itself is plumbing, and there is no audio platform under a
/// headless binding anyway. The rule the founder set: the loop must not
/// fight the Library music player.
///
/// Note the loop is built on audioplayers, NOT just_audio, precisely so it
/// cannot touch `JustAudioPlatform.instance` — swapping that has killed
/// background music three times.
void main() {
  setUp(QuizMusic.resetForTest);

  group('when the loop should run', () {
    test('plays when enabled and nothing else is', () {
      expect(
        QuizMusic.shouldPlay(enabled: true, userMusicOn: false, muted: false),
        isTrue,
      );
    });

    test('stands down for the member\'s own music', () {
      // A game soundtrack over the hymn somebody chose is worse than no
      // soundtrack at all.
      expect(
        QuizMusic.shouldPlay(enabled: true, userMusicOn: true, muted: false),
        isFalse,
      );
    });

    test('stays off when switched off, whatever else is happening', () {
      expect(
        QuizMusic.shouldPlay(enabled: false, userMusicOn: false, muted: false),
        isFalse,
      );
      expect(
        QuizMusic.shouldPlay(enabled: false, userMusicOn: true, muted: false),
        isFalse,
      );
    });

    test('the arena mute button silences the soundtrack too', () {
      // The reported bug: the speaker icon only ever called
      // QuizSfx.setMuted, so muting killed the taps and ticks and left the
      // music bed playing. One speaker icon means all the sound.
      expect(
        QuizMusic.shouldPlay(enabled: true, userMusicOn: false, muted: true),
        isFalse,
      );
    });
  });

  group('settings', () {
    test('is on by default — the pref is stored inverted', () {
      // An absent pref must mean "on": the music is part of how the arena
      // is meant to feel, so it is opt-OUT.
      expect(QuizMusic.enabled, isTrue);
    });

    test('sits under the effects by default', () {
      // A soundtrack that competes with the answer sounds makes a round
      // feel muddy rather than exciting.
      expect(QuizMusic.defaultVolume, lessThan(0.5));
      expect(QuizMusic.volume, QuizMusic.defaultVolume);
    });

    test('the volume slider cannot reach silence', () async {
      // Same reasoning as the effects slider: silence belongs to the
      // toggle, which says what it does and can be undone.
      expect(QuizMusic.kMinVolume, greaterThan(0.0));

      await QuizMusic.setVolume(0);
      expect(QuizMusic.volume, QuizMusic.kMinVolume);

      await QuizMusic.setVolume(-1);
      expect(QuizMusic.volume, QuizMusic.kMinVolume);

      await QuizMusic.setVolume(5);
      expect(QuizMusic.volume, 1.0);
    });

    test('ordinary volumes are honoured', () async {
      await QuizMusic.setVolume(0.6);
      expect(QuizMusic.volume, closeTo(0.6, 0.0001));
    });

    test('turning it off reports off', () async {
      await QuizMusic.setEnabled(false);
      expect(QuizMusic.enabled, isFalse);

      await QuizMusic.setEnabled(true);
      expect(QuizMusic.enabled, isTrue);
    });
  });

  group('fail-soft', () {
    test('stopping when nothing is playing never throws', () async {
      await expectLater(QuizMusic.stop(), completes);
      await expectLater(QuizMusic.stop(), completes);
    });
  });

  // NOT tested here: start() and reconcile() when they decide to PLAY.
  // Constructing an audioplayers AudioPlayer opens platform + event
  // channels, and under a headless binding those never answer — the call
  // hangs rather than failing, so a test of it would only ever prove the
  // test harness has no audio. The guarantee that matters (a missing or
  // unplayable assets/sounds/quiz/arena_loop.mp3 leaves the arena silent
  // instead of broken) is a try/catch around the whole start path that
  // sets `unavailable` and swallows. The decision of whether to play at
  // all — the part with real logic in it — is `shouldPlay`, covered above.
}
