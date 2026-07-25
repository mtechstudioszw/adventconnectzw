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

  static final Map<QuizSound, AudioPlayer> _players = {};
  static bool _initialised = false;
  static bool _initialising = false;

  /// Cached so the arena can render its mute button without a disk read.
  static bool _muted = false;

  static bool get muted => _muted;

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
    try {
      for (final sound in QuizSound.values) {
        final player = AudioPlayer(playerId: 'quiz_${sound.name}');
        await player.setReleaseMode(ReleaseMode.stop);
        await player.setPlayerMode(PlayerMode.lowLatency);
        await player.setAudioContext(_context);
        await player.setSourceAsset(sound.asset);
        await player.setVolume(sound.volume);
        _players[sound] = player;
      }
      _initialised = true;
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
    }
  }

  static Future<void> toggleMute() => setMuted(!_muted);

  /// Play [sound]. Silent (and cheap) when muted or not initialised.
  static void play(QuizSound sound) {
    if (_muted || !_initialised) return;
    final player = _players[sound];
    if (player == null) return;
    unawaited(() async {
      try {
        await player.stop(); // restart if it's still ringing out
        await player.resume();
      } catch (_) {}
    }());
  }

  // ---- Haptics ------------------------------------------------------------
  //
  // Haptics are NOT gated on the mute toggle — muting is about sound in a
  // quiet room, and silent feedback is exactly what you still want there.
  // iOS ignores vibrate() patterns, so each helper picks the closest
  // platform-appropriate impact.

  static void hapticTap() {
    HapticFeedback.selectionClick();
  }

  static void hapticCorrect() {
    HapticFeedback.mediumImpact();
  }

  static void hapticWrong() {
    if (Platform.isAndroid) {
      HapticFeedback.vibrate();
    } else {
      HapticFeedback.heavyImpact();
    }
  }

  static void hapticCombo() {
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
