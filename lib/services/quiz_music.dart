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
    // NO LONGER listens to QuizSfx.revision. The loop used to reconcile on
    // every effects-settings change so a master mute could stop it, but the
    // only things that bump that revision now are the two *Sound effects*
    // switches — and reacting to them is precisely the bug the founder
    // reported: turning effects off killed the soundtrack too. Nothing
    // reconcile() reads (the music toggle, and whether the Library player is
    // playing) changes when effects settings change, so the listener was
    // both harmful and pointless. See [shouldPlay].
    _off =
        (CacheService.readPref(_kOff) ?? CacheService.readPref(_legacyOff)) ==
        '1';
    _volume =
        double.tryParse(
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
  ///
  /// [muted] is a MASTER mute — "silence everything", as a single speaker
  /// icon in the arena would mean.
  ///
  /// It is deliberately NOT [QuizSfx.muted] any more (founder, Aug 2026:
  /// "turn off sound effects the music stops — it should only stop when I
  /// turn off music"). The original coupling was written for a speaker
  /// button in the arena's top bar, where one icon meaning "all the sound"
  /// was right. That button no longer calls [QuizSfx.setMuted] — the only
  /// two callers left are the *Sound effects* switches in the quiz lobby
  /// and in Sound & haptics, and neither of those should reach across and
  /// stop the soundtrack. Effects and music are two switches; each one now
  /// controls exactly what it is labelled.
  ///
  /// The parameter stays so a real master mute can be reintroduced without
  /// reworking this decision — pass `true` from it and the loop stops.
  @visibleForTesting
  static bool shouldPlay({
    required bool enabled,
    required bool userMusicOn,
    required bool muted,
  }) => enabled && !userMusicOn && !muted;

  /// Start the loop for a round. Safe to call more than once.
  /// The soundtrack's OWN audio context, not [QuizSfx.sharedAudioContext].
  ///
  /// ## Why this is separate
  ///
  /// The SFX context declares `contentType: sonification` and
  /// `usageType: game`. That is right for what it describes — short UI
  /// beeps and ticks. It is wrong for a three-megabyte looping music bed,
  /// and wrong in a way that is silent rather than loud: Android uses
  /// content type and usage to decide which STREAM the audio belongs to,
  /// and sonification can land on a stream governed by the notification
  /// volume instead of the media volume. A member with notifications turned
  /// down then gets a quiz that plays nothing while every other part of the
  /// app works and the haptics still fire — which is exactly the report.
  ///
  /// So the music declares itself as music: `contentType: music`,
  /// `usageType: media`. That is the stream the volume rocker controls when
  /// you are in an app playing audio, which is the one the member will
  /// reach for.
  ///
  /// **`audioFocus: none` is kept, and is deliberate.** It is the rule from
  /// `audio-background-playback-fix`: the arena must never duck or stop the
  /// member's own Library music. `QuizMusic.shouldPlay` already stands the
  /// soundtrack down when their music is playing, so nothing is lost by not
  /// grabbing focus — and grabbing it would be the regression that keeps
  /// killing background playback.
  ///
  /// iOS keeps `ambient` + `mixWithOthers` for the same reason. Note that
  /// ambient obeys the hardware ringer switch, so a silenced iPhone plays no
  /// arena music by design.
  static AudioContext get _musicContext => AudioContext(
    android: const AudioContextAndroid(
      isSpeakerphoneOn: false,
      stayAwake: false,
      contentType: AndroidContentType.music,
      usageType: AndroidUsageType.media,
      audioFocus: AndroidAudioFocus.none,
    ),
    iOS: AudioContextIOS(
      category: AVAudioSessionCategory.ambient,
      options: const {AVAudioSessionOptions.mixWithOthers},
    ),
  );

  static Future<void> start() async {
    _loadPrefs();
    if (!shouldPlay(
      enabled: enabled,
      userMusicOn: MusicPlayerService.instance.isPlayingNow,
      // The MASTER mute (the arena's speaker icon), never QuizSfx.muted.
      // The "Sound effects" switch must not reach across and stop the
      // soundtrack — that was the founder's earlier report — but the
      // speaker button is meant to silence everything, which is the
      // current one. Two flags, each controlling what it is labelled.
      muted: QuizSfx.masterMuted,
    )) {
      return;
    }
    if (_player != null) return;
    try {
      final player = AudioPlayer(playerId: 'quiz_music');
      // loop, not stop: this is a bed that runs for the whole round.
      await player.setReleaseMode(ReleaseMode.loop);
      await player.setPlayerMode(PlayerMode.mediaPlayer);
      await player.setAudioContext(_musicContext);
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
      // The MASTER mute (the arena's speaker icon), never QuizSfx.muted.
      // The "Sound effects" switch must not reach across and stop the
      // soundtrack — that was the founder's earlier report — but the
      // speaker button is meant to silence everything, which is the
      // current one. Two flags, each controlling what it is labelled.
      muted: QuizSfx.masterMuted,
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
