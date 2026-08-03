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

  // `pref:` prefixed, and that prefix is load-bearing:
  // `CacheService.clearUserData()` deletes every key that does NOT start
  // with it. These are device settings, not user data, so without the
  // prefix every sign-out silently reset the member's sound and vibration
  // choices back to full volume.
  static const _kMuted = 'pref:quiz_sfx_muted';
  static const _kHaptics = 'pref:quiz_haptics_off';
  static const _kVolume = 'pref:quiz_sfx_volume';

  // The unprefixed keys these used to be written under. Read once, on the
  // first load, so nobody's existing settings are thrown away by the
  // rename — then written back under the new key.
  static const _legacyMuted = 'quiz_sfx_muted';
  static const _legacyHaptics = 'quiz_haptics_off';
  static const _legacyVolume = 'quiz_sfx_volume';

  static final Map<QuizSound, AudioPlayer> _players = {};
  static bool _initialised = false;
  static bool _initialising = false;

  /// Bumped by [dispose]. [init] captures it before its first await and
  /// re-checks it after every one, so a pool that was torn down while it
  /// was still being built is abandoned instead of half-published.
  ///
  /// This is what "the quiz has no sound" was. [init] used to write each
  /// player into [_players] as it created it, and [dispose] releases and
  /// clears that same map — so when the lobby went away while the round's
  /// init was still looping (lobby.dispose() and round.initState() both
  /// run on the same frame), every sound built before the clear was
  /// disposed and dropped, while init carried on and still set
  /// [_initialised] to true. play() only self-heals when that flag is
  /// false, so those clips stayed dead for the rest of the session — and
  /// being first in the enum, they were tap, tick and count: the tap on
  /// every answer and the countdown ticks.
  static int _generation = 0;

  /// Cached so the arena can render its mute button without a disk read.
  static bool _muted = false;

  /// Every getter below loads the stored preferences first.
  ///
  /// Belt and braces on purpose: relying on each call site to remember is
  /// precisely what failed. [loadPrefs] is idempotent and is three map
  /// lookups once per session, so the safe thing is also the cheap thing.
  static bool get muted {
    loadPrefs();
    return _muted;
  }

  /// The quietest the SLIDER may go.
  ///
  /// Not a stylistic floor — silence has to stay reachable only through
  /// the mute button, which has an icon and an obvious way back. The
  /// slider's own minimum used to be 0.0, so one drag to 0% persisted
  /// "0.00", and from then on every clip played at volume zero in every
  /// future session while the mute button still read UNMUTED. That is
  /// indistinguishable from "the quiz has no sound", with nothing on
  /// screen to explain it and no reason to suspect the slider.
  static const double kMinVolume = 0.1;

  /// Master volume, [kMinVolume]–1.0, multiplied into each clip's own trim.
  ///
  /// The arena had a mute switch and nothing between "off" and "full",
  /// which is not a volume control — you either played in silence or woke
  /// the house. Defaults to 0.85.
  static double _volume = 0.85;

  static double get volume {
    loadPrefs();
    return _volume;
  }

  /// Notifies the arena UI so a slider and the mute button stay in sync
  /// wherever they're drawn.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static Future<void> setVolume(double value) async {
    loadPrefs();
    _volume = value.clamp(kMinVolume, 1.0);
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

  static bool get hapticsEnabled {
    loadPrefs();
    return !_hapticsOff;
  }

  static Future<void> setHapticsEnabled(bool value) async {
    loadPrefs();
    _hapticsOff = !value;
    await CacheService.writePref(_kHaptics, value ? '0' : '1');
  }

  /// The arena's audio contract, shared with [QuizMusic] so there is ONE
  /// definition of "never steal focus" rather than two that can drift.
  static AudioContext get sharedAudioContext => _context;

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

  /// True once the stored preferences have been read into the statics.
  static bool _prefsLoaded = false;

  /// Read the saved mute / volume / haptics settings.
  ///
  /// Split out of [init] because the two jobs have completely different
  /// costs and completely different callers. [init] builds nine audio
  /// players and is only worth doing when the arena opens; this is three
  /// synchronous map lookups, and **anything that merely READS these
  /// settings has to call it first**.
  ///
  /// Not doing so was the bug behind "the quiz settings buttons don't
  /// work". The settings screen renders straight off [muted], [volume] and
  /// [hapticsEnabled], and those are plain statics that started at their
  /// compiled-in defaults. Open Settings → Sound & haptics without having
  /// entered the arena that session and every control read ON regardless of
  /// what was saved — so a member who had muted the quiz saw "Sound
  /// effects: ON", left it alone, and got silence.
  ///
  /// Idempotent, and safe to call from `build`.
  static void loadPrefs() {
    if (_prefsLoaded) return;
    _prefsLoaded = true;
    _muted = _readFlag(_kMuted, _legacyMuted);
    _hapticsOff = _readFlag(_kHaptics, _legacyHaptics);
    // Clamped to kMinVolume on the way IN as well, so a phone that already
    // stored "0.00" before the slider had a floor heals itself on the next
    // launch instead of staying silent forever.
    _volume = double.tryParse(
              CacheService.readPref(_kVolume) ??
                  CacheService.readPref(_legacyVolume) ??
                  '',
            )?.clamp(kMinVolume, 1.0) ??
        0.85;
  }

  /// Reads the current key, falling back to the pre-`pref:` one so an
  /// existing install keeps the settings it already had.
  static bool _readFlag(String key, String legacyKey) =>
      (CacheService.readPref(key) ?? CacheService.readPref(legacyKey)) == '1';

  /// Warm the players up. Safe to call more than once; call it when the
  /// arena opens so the first tap isn't the one that pays for loading.
  static Future<void> init() async {
    if (_initialised || _initialising) return;
    _initialising = true;
    loadPrefs();
    final generation = _generation;
    // Built off to the side and published in one go at the end, so a
    // concurrent dispose() can never find a half-filled pool.
    final loaded = <QuizSound, AudioPlayer>{};
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
        loaded[sound] = player;

        // dispose() ran underneath us. Everything built so far belongs to
        // a pool nobody wants; release it rather than publishing players
        // the arena has already walked away from.
        if (generation != _generation) {
          await _releaseAll(loaded.values);
          return;
        }
      }
      _players.addAll(loaded);
      _initialised = true;
      revision.value++;
    } catch (e) {
      await _releaseAll(loaded.values);
      // Leave _initialised false — play() degrades to haptics only.
      debugPrint('QuizSfx.init failed: $e');
    } finally {
      _initialising = false;
    }
  }

  static Future<void> _releaseAll(Iterable<AudioPlayer> players) async {
    for (final player in players) {
      try {
        await player.release();
        await player.dispose();
      } catch (_) {}
    }
  }

  /// Free the players when the arena closes. The arena is the only caller.
  ///
  /// Bumping [_generation] first is what tells an init() that is still
  /// looping to abandon its work instead of publishing into a pool this
  /// call is tearing down.
  static Future<void> dispose() async {
    _generation++;
    final players = List<AudioPlayer>.of(_players.values);
    _players.clear();
    _initialised = false;
    await _releaseAll(players);
  }

  static Future<void> setMuted(bool value) async {
    loadPrefs();
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
    if (muted) return;
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
    if (!hapticsEnabled) return;
    HapticFeedback.selectionClick();
  }

  static void hapticCorrect() {
    if (!hapticsEnabled) return;
    HapticFeedback.mediumImpact();
  }

  static void hapticWrong() {
    if (!hapticsEnabled) return;
    if (Platform.isAndroid) {
      HapticFeedback.vibrate();
    } else {
      HapticFeedback.heavyImpact();
    }
  }

  static void hapticCombo() {
    if (!hapticsEnabled) return;
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

  @visibleForTesting
  static void resetForTest() {
    _players.clear();
    _initialised = false;
    _initialising = false;
    _prefsLoaded = false;
    _muted = false;
    _hapticsOff = false;
    _volume = 0.85;
    _generation++;
  }
}
