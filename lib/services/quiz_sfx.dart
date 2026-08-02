import 'dart:async';
import 'dart:io' show Platform;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'cache_service.dart';

/// One of the arena's sound effects.
enum QuizSound { tap, tick, count, go, correct, wrong, combo, levelUp, finish }

extension on QuizSound {
  String get asset => switch (this) {
        QuizSound.tap => 'sounds/quiz/tap.wav',
        QuizSound.tick => 'sounds/quiz/tick.wav',
        QuizSound.count => 'sounds/quiz/count.wav',
        QuizSound.go => 'sounds/quiz/go.wav',
        QuizSound.correct => 'sounds/quiz/correct.wav',
        QuizSound.wrong => 'sounds/quiz/wrong.wav',
        QuizSound.combo => 'sounds/quiz/combo.wav',
        QuizSound.levelUp => 'sounds/quiz/levelup.wav',
        QuizSound.finish => 'sounds/quiz/finish.wav',
      };

  /// Per-clip trim so the set feels balanced without re-rendering the WAVs.
  double get volume => switch (this) {
        QuizSound.tap => 0.35,
        QuizSound.tick => 0.30,
        QuizSound.count => 0.70,
        QuizSound.go => 0.75,
        QuizSound.correct => 0.80,
        QuizSound.wrong => 0.62,
        QuizSound.combo => 0.75,
        QuizSound.levelUp => 0.80,
        QuizSound.finish => 0.85,
      };
}

/// Sound + haptics for the Quiz Arena.
///
/// Design notes worth keeping:
/// * **Never steals audio focus.** The arena must not pause the Library
///   music player or a voice note. On Android the players request
///   `AndroidAudioFocus.none`; on iOS they use the `ambient` category, which
///   also means the hardware mute switch silences them, as a game should.
/// * **Pooled players.** One player per sound, pre-loaded, so a tap plays
///   with no allocation. Effects are short and never overlap themselves.
/// * **Fail-soft.** Audio is decoration. Every call is wrapped — a device
///   that refuses to play a clip must never break a round.
class QuizSfx {
  QuizSfx._();

  static const _kMuted = 'quiz_sfx_muted';
  static const _kHaptics = 'quiz_haptics_off';
  static const _kVolume = 'quiz_sfx_volume';

  static final Map<QuizSound, AudioPlayer> _players = {};
  static bool _initialised = false;
  static bool _initialising = false;

  /// Cached so the arena can render its mute button without a disk read.
  static bool _muted = false;

  static bool get muted => _muted;

  /// Master volume, 0.0–1.0, multiplied into each clip's own trim.
  ///
  /// The arena had a mute switch and nothing between "off" and "full",
  /// which is not a volume control — you either played in silence or woke
  /// the house. Defaults to 0.85.
  static double _volume = 0.85;

  static double get volume => _volume;

  /// Notifies the arena UI so a slider and the mute button stay in sync
  /// wherever they're drawn.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static Future<void> setVolume(double value) async {
    _volume = value.clamp(0.0, 1.0);
    await CacheService.writePref(_kVolume, _volume.toStringAsFixed(2));
    for (final entry in _players.entries) {
      try {
        await entry.value.setVolume(entry.key.volume * _volume);
      } catch (_) {}
    }
    revision.value++;
  }

  /// Haptics are opt-OUT: on by default, because the tap tick is a core part
  /// of how the arena feels. Stored inverted (`quiz_haptics_off`) so an
  /// absent pref means "on".
  static bool _hapticsOff = false;

  static bool get hapticsEnabled => !_hapticsOff;

  static Future<void> setHapticsEnabled(bool value) async {
    _hapticsOff = !value;
    await CacheService.writePref(_kHaptics, value ? '0' : '1');
  }

  static AudioContext get _context => AudioContext(
        android: const AudioContextAndroid(
          isSpeakerphoneOn: false,
          stayAwake: false,
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.game,
          // Critical: do NOT duck or pause whatever the user is listening to.
          audioFocus: AndroidAudioFocus.none,
        ),
        iOS: AudioContextIOS(
          // `ambient` mixes with other audio AND obeys the ringer switch.
          category: AVAudioSessionCategory.ambient,
          options: const {AVAudioSessionOptions.mixWithOthers},
        ),
      );

  /// Warm the players up. Safe to call more than once; call it when the
  /// arena opens so the first tap isn't the one that pays for loading.
  static Future<void> init() async {
    if (_initialised || _initialising) return;
    _initialising = true;
    _muted = CacheService.readPref(_kMuted) == '1';
    _hapticsOff = CacheService.readPref(_kHaptics) == '1';
    _volume = double.tryParse(CacheService.readPref(_kVolume) ?? '')
            ?.clamp(0.0, 1.0) ??
        0.85;
    try {
      for (final sound in QuizSound.values) {
        final player = AudioPlayer(playerId: 'quiz_${sound.name}');
        await player.setReleaseMode(ReleaseMode.stop);
        // NOT PlayerMode.lowLatency. On Android that routes through
        // SoundPool, which ignores most of the AudioContext below and
        // applies volume only at load time — so the arena could end up
        // playing at zero with no way to tell. mediaPlayer honours
        // setVolume and the context, and these clips are short and
        // pre-loaded, so the extra latency isn't perceptible.
        await player.setPlayerMode(PlayerMode.mediaPlayer);
        await player.setAudioContext(_context);
        await player.setSourceAsset(sound.asset);
        await player.setVolume(sound.volume * _volume);
        _players[sound] = player;
      }
      _initialised = true;
      revision.value++;
    } catch (e) {
      // Leave _initialised false — play() degrades to haptics only.
      debugPrint('QuizSfx.init failed: $e');
    } finally {
      _initialising = false;
    }
  }

  /// Free the players when the arena closes. The arena is the only caller.
  static Future<void> dispose() async {
    for (final player in _players.values) {
      try {
        await player.release();
        await player.dispose();
      } catch (_) {}
    }
    _players.clear();
    _initialised = false;
  }

  static Future<void> setMuted(bool value) async {
    _muted = value;
    await CacheService.writePref(_kMuted, value ? '1' : '0');
    if (value) {
      for (final player in _players.values) {
        try {
          await player.stop();
        } catch (_) {}
      }
    } else {
      // stop() released the sources above; re-attach so unmuting
      // actually produces sound again.
      for (final entry in _players.entries) {
        try {
          await entry.value.setSourceAsset(entry.key.asset);
          await entry.value.setVolume(entry.key.volume * _volume);
        } catch (_) {}
      }
    }
    revision.value++;
  }

  static Future<void> toggleMute() => setMuted(!_muted);

  /// Play [sound]. Silent (and cheap) when muted.
  ///
  /// Self-healing: if the pool isn't up yet (the round screen fires its
  /// countdown before `init()` has finished, and the lobby releases the
  /// pool on the way out) this kicks off initialisation instead of
  /// silently dropping every effect for the whole round.
  static void play(QuizSound sound) {
    if (_muted) return;
    if (!_initialised) {
      unawaited(init());
      return;
    }
    final player = _players[sound];
    if (player == null) return;
    unawaited(() async {
      try {
        // seek(0), NOT stop(). On Android `stop()` tears the prepared
        // MediaPlayer down, and the resume() that follows has nothing
        // left to play — a rapid second tap fell silent. Seeking rewinds
        // a clip that's still ringing out without releasing it.
        await player.seek(Duration.zero);
        await player.resume();
      } catch (_) {
        // Source lost (backgrounded, focus stolen). Re-attach once and
        // let the next call play it.
        try {
          await player.setSourceAsset(sound.asset);
          await player.setVolume(sound.volume * _volume);
          await player.resume();
        } catch (_) {}
      }
    }());
  }

  // ---- Haptics ------------------------------------------------------------
  //
  // Haptics are NOT gated on the mute toggle — muting is about sound in a
  // quiet room, and silent feedback is exactly what you still want there.
  // iOS ignores vibrate() patterns, so each helper picks the closest
  // platform-appropriate impact.

  static void hapticTap() {
    if (_hapticsOff) return;
    HapticFeedback.selectionClick();
  }

  static void hapticCorrect() {
    if (_hapticsOff) return;
    HapticFeedback.mediumImpact();
  }

  static void hapticWrong() {
    if (_hapticsOff) return;
    if (Platform.isAndroid) {
      HapticFeedback.vibrate();
    } else {
      HapticFeedback.heavyImpact();
    }
  }

  static void hapticCombo() {
    if (_hapticsOff) return;
    HapticFeedback.heavyImpact();
  }

  static void hapticCountBeat() {
    HapticFeedback.mediumImpact();
  }

  /// Fires sound + haptic together for the common moments, so call sites
  /// stay one line and can't accidentally do one without the other.
  static void correct() {
    play(QuizSound.correct);
    hapticCorrect();
  }

  static void wrong() {
    play(QuizSound.wrong);
    hapticWrong();
  }

  static void combo() {
    play(QuizSound.combo);
    hapticCombo();
  }

  static void tap() {
    play(QuizSound.tap);
    hapticTap();
  }

  static void countBeat() {
    play(QuizSound.count);
    hapticCountBeat();
  }
}
