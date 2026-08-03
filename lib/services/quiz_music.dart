import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'cache_service.dart';
import 'music_player_service.dart';
import 'quiz_sfx.dart';

/// The Quiz Arena's background music loop.
///
/// Deliberately built on **audioplayers**, the same package as [QuizSfx],
/// and NOT on just_audio. The Library music player owns the app's
/// just_audio instance and its media session; touching
/// `JustAudioPlatform.instance` has killed background playback three times
/// (see the `audio-background-playback-fix` note). Staying in a different
/// package means this loop cannot interact with it at all.
///
/// Two rules make it a good citizen:
///
///  * **It never steals audio focus.** Same [AudioContext] as the effects:
///    `AndroidAudioFocus.none` and the iOS `ambient` category, so it mixes
///    rather than pausing whatever else is going on. (`ambient` also means
///    the iOS hardware mute switch silences it, as a game should.)
///  * **It stands down for the member's own music.** If the Library player
///    is playing, the loop does not start — a game soundtrack fighting the
///    hymn someone chose is worse than no soundtrack. Checked via
///    [MusicPlayerService.isPlayingNow], which does not construct anything.
///
/// Fail-soft throughout: the arena must play perfectly with no audio at
/// all, including when the asset is missing entirely.
class QuizMusic {
  QuizMusic._();

  /// Drop a seamless loop here. Absent is a supported state — the arena
  /// simply runs silent rather than breaking.
  static const _asset = 'sounds/quiz/arena_loop.mp3';

  /// Stored INVERTED (`quiz_music_off`) so an absent pref means "on" — the
  /// music is part of how the arena is meant to feel, so it is opt-out.
  ///
  /// `pref:` prefixed for the same reason as [QuizSfx]: without it,
  /// `CacheService.clearUserData()` deleted these on every sign-out.
  static const _kOff = 'pref:quiz_music_off';
  static const _kVolume = 'pref:quiz_music_volume';

  /// Pre-`pref:` keys, read once so an existing install keeps its choice.
  static const _legacyOff = 'quiz_music_off';
  static const _legacyVolume = 'quiz_music_volume';

  /// Under the effects on purpose: a soundtrack that competes with the
  /// answer sounds makes the round feel muddy rather than exciting.
  static const double defaultVolume = 0.35;

  /// The loop may be quiet but never silent — silence is what the toggle
  /// is for, and a slider that reaches zero just looks broken. Same
  /// reasoning as [QuizSfx.kMinVolume].
  static const double kMinVolume = 0.05;

  static AudioPlayer? _player;
  static bool _off = false;
  static double _volume = defaultVolume;
  static bool _loaded = false;

  /// True when the asset failed to load. Lets the settings screen tell the
  /// truth instead of offering a control that cannot do anything.
  static bool _unavailable = false;
  static bool get unavailable => _unavailable;

  // Both getters load first, for the reason spelled out on [loadPrefs]:
  // a reader that forgets silently reports the default instead of what the
  // member chose.
  static bool get enabled {
    loadPrefs();
    return !_off;
  }

  static double get volume {
    loadPrefs();
    return _volume;
  }

  /// Notifies the settings UI so the toggle and slider stay in sync.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// Read the saved toggle + volume.
  ///
  /// Public, and it has to be: [enabled] and [volume] are plain statics, so
  /// anything that only READS them — the Sound & haptics screen — showed
  /// the compiled-in defaults until some setter happened to run. That is
  /// what "the quiz settings buttons don't work" was; see
  /// [QuizSfx.loadPrefs] for the full account.
  ///
  /// Idempotent and synchronous, so it is safe to call from `build`.
  static void loadPrefs() {
    if (_loaded) return;
    _loaded = true;
    _off = (CacheService.readPref(_kOff) ??
            CacheService.readPref(_legacyOff)) ==
        '1';
    _volume = double.tryParse(
              CacheService.readPref(_kVolume) ??
                  CacheService.readPref(_legacyVolume) ??
                  '',
            )?.clamp(kMinVolume, 1.0) ??
        defaultVolume;
  }

  static void _loadPrefs() => loadPrefs();

  static Future<void> setEnabled(bool value) async {
    _loadPrefs();
    _off = !value;
    await CacheService.writePref(_kOff, value ? '0' : '1');
    revision.value++;
    if (!value) {
      await stop();
    }
  }

  static Future<void> setVolume(double value) async {
    _loadPrefs();
    _volume = value.clamp(kMinVolume, 1.0);
    await CacheService.writePref(_kVolume, _volume.toStringAsFixed(2));
    try {
      await _player?.setVolume(_volume);
    } catch (_) {}
    revision.value++;
  }

  /// Whether the loop should be running at all right now.
  ///
  /// Pure and synchronous so the decision can be tested without any audio
  /// platform behind it — the decision is the part that matters, the
  /// playback is just plumbing.
  @visibleForTesting
  static bool shouldPlay({required bool enabled, required bool userMusicOn}) =>
      enabled && !userMusicOn;

  /// Start the loop for a round. Safe to call more than once.
  static Future<void> start() async {
    _loadPrefs();
    if (!shouldPlay(
      enabled: enabled,
      userMusicOn: MusicPlayerService.instance.isPlayingNow,
    )) {
      return;
    }
    if (_player != null) return;
    try {
      final player = AudioPlayer(playerId: 'quiz_music');
      // loop, not stop: this is a bed that runs for the whole round.
      await player.setReleaseMode(ReleaseMode.loop);
      await player.setPlayerMode(PlayerMode.mediaPlayer);
      await player.setAudioContext(QuizSfx.sharedAudioContext);
      await player.setSourceAsset(_asset);
      await player.setVolume(_volume);
      await player.resume();
      _player = player;
      _unavailable = false;
    } catch (e) {
      // Missing or unplayable asset. The arena runs silent; it never breaks.
      _unavailable = true;
      debugPrint('QuizMusic.start failed (arena will run silent): $e');
      await _release();
    }
    revision.value++;
  }

  /// Stop and release. Called when the round ends or the arena is left.
  static Future<void> stop() async {
    await _release();
    revision.value++;
  }

  static Future<void> _release() async {
    final player = _player;
    _player = null;
    if (player == null) return;
    try {
      await player.stop();
      await player.release();
      await player.dispose();
    } catch (_) {}
  }

  /// Duck out of the way when the member starts their own music mid-round,
  /// and come back when they stop. Cheap enough to call on a timer or from
  /// a lifecycle hook.
  static Future<void> reconcile() async {
    _loadPrefs();
    final should = shouldPlay(
      enabled: enabled,
      userMusicOn: MusicPlayerService.instance.isPlayingNow,
    );
    if (should && _player == null) {
      await start();
    } else if (!should && _player != null) {
      await stop();
    }
  }

  @visibleForTesting
  static void resetForTest() {
    _player = null;
    _off = false;
    _volume = defaultVolume;
    _loaded = false;
    _unavailable = false;
  }
}
