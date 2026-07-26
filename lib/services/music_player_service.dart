import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import '../models/library_item_model.dart';
import 'music_download_service.dart';
import 'music_prefs_service.dart';

/// App-wide music player for the Library (Music tab + Audio Bible).
///
/// ## Why background playback works now
///
/// This used to be plain `just_audio` with NO media session, because
/// `just_audio_background` kept throwing `_audioHandler has not been
/// initialized` and music wouldn't play at all. Two things caused that, and
/// both are fixed here:
///
/// 1. **Init ordering.** `JustAudioBackground.init()` must fully complete
///    before the FIRST `AudioPlayer` is constructed. The old code built the
///    player in a field initializer on a singleton that could be touched at
///    any time. Here the player is created lazily by [player], and
///    [ensureInitialized] is awaited in `main()` before `runApp`.
/// 2. **Missing MediaItem tags.** `just_audio_background` reads a
///    [MediaItem] off every audio source's `tag`. An untagged source throws
///    at load time. [_sourceFor] now always attaches one.
///
/// If background init fails for any reason (an OEM with no media session,
/// a platform without the plugin), [backgroundReady] stays false and the
/// player degrades to plain in-app playback rather than refusing to play —
/// the reliability property the previous author was protecting.
class MusicPlayerService {
  MusicPlayerService._();
  static final MusicPlayerService instance = MusicPlayerService._();

  static bool _backgroundReady = false;
  static bool _initStarted = false;

  /// True when the media session came up, so lock-screen / notification
  /// controls are live.
  static bool get backgroundReady => _backgroundReady;

  /// Boots the media session. Call (and await) ONCE from `main()` before
  /// `runApp` and before anything touches [player]. Never throws.
  static Future<void> ensureInitialized() async {
    if (_initStarted) return;
    _initStarted = true;
    // Web and desktop have no audio_service implementation; calling init
    // there throws a MissingPluginException we can't usefully recover from.
    if (kIsWeb) return;
    try {
      // Timeboxed: this runs on the critical path before runApp, and a
      // wedged platform channel on some OEM would otherwise hang the splash
      // forever. A timeout degrades to plain playback, same as a throw.
      await JustAudioBackground.init(
        androidNotificationChannelId:
            'com.mtechstudioszw.adventconnect.channel.audio',
        androidNotificationChannelName: 'Advent Connect audio',
        androidNotificationChannelDescription:
            'Playback controls for hymns, worship music and the Audio Bible.',
        // Let the notification be dismissed when paused, so a user who
        // stopped listening isn't stuck with a permanent shade entry.
        androidNotificationOngoing: false,
        androidStopForegroundOnPause: true,
        androidNotificationIcon: 'mipmap/ic_launcher',
        preloadArtwork: true,
      ).timeout(const Duration(seconds: 6));
      _backgroundReady = true;
    } catch (e, s) {
      // Non-fatal by design — see the class doc.
      debugPrint('JustAudioBackground.init failed, falling back to plain '
          'playback: $e\n$s');
      _backgroundReady = false;
    }
  }

  // ---- Player -------------------------------------------------------------

  AudioPlayer? _player;

  /// The shared player. Constructed lazily so it can never be built before
  /// [ensureInitialized] has run.
  AudioPlayer get player => _player ??= AudioPlayer();

  /// The playlist currently loaded, so the mini bar and full player can
  /// resolve titles / art by index.
  List<LibraryItem> _queue = const [];
  List<LibraryItem> get queue => _queue;

  /// Identifies the loaded playlist so tapping another track in the same list
  /// seeks instead of rebuilding the source (which would restart buffering).
  String _loadedSignature = '';

  bool get hasQueue => _queue.isNotEmpty;

  /// Bumped on queue / track changes so widgets outside a StreamBuilder can
  /// rebuild (the mini bar lives above the navigator).
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// The currently-playing item, derived from the player's current index.
  LibraryItem? get current {
    final i = player.currentIndex;
    if (i == null || i < 0 || i >= _queue.length) return null;
    return _queue[i];
  }

  /// Emits whenever the active track changes.
  Stream<LibraryItem?> get currentStream =>
      player.currentIndexStream.map((_) => current);

  // ---- Loading ------------------------------------------------------------

  /// Builds an audio source for [item], preferring a downloaded local file so
  /// saved tracks play with zero network. Always tagged with a [MediaItem] —
  /// see the class doc.
  AudioSource _sourceFor(LibraryItem item) {
    final local = MusicDownloadService.cachedPathSync(item.id);
    final uri = local != null ? Uri.file(local) : Uri.parse(item.fileUrl);
    return AudioSource.uri(
      uri,
      tag: MediaItem(
        // Must be globally unique and stable — the media session dedupes on it.
        id: item.id,
        title: item.title,
        artist: (item.author?.isNotEmpty ?? false)
            ? item.author
            : 'Advent Connect ZW',
        album: item.kind == 'audio_bible' ? 'Audio Bible' : 'Library',
        artUri: (item.coverUrl?.isNotEmpty ?? false)
            ? Uri.tryParse(item.coverUrl!)
            : null,
        duration: item.durationSeconds != null
            ? Duration(seconds: item.durationSeconds!)
            : null,
      ),
    );
  }

  /// Loads [items] as the active playlist and starts at [startIndex].
  ///
  /// Reuses the loaded source when the same list is already active (seek
  /// only). Resolves local download paths first so offline tracks play from
  /// disk.
  Future<void> setQueueAndPlay(List<LibraryItem> items, int startIndex) async {
    if (items.isEmpty) return;
    final index = startIndex.clamp(0, items.length - 1);
    final signature = items.map((e) => e.id).join(',');

    if (signature == _loadedSignature && _player != null) {
      await player.seek(Duration.zero, index: index);
      await player.play();
      _afterTrackChange(items[index]);
      return;
    }

    // Resolve which of these are downloaded before building the sources.
    await MusicDownloadService.warmPaths(items);

    _queue = items;
    _loadedSignature = signature;

    final source = ConcatenatingAudioSource(
      children: [for (final item in items) _sourceFor(item)],
    );
    await player.setAudioSource(
      source,
      initialIndex: index,
      initialPosition: Duration.zero,
    );
    await player.setSpeed(MusicPrefsService.speed());
    await player.play();
    _afterTrackChange(items[index]);
    _watchTrackChanges();
  }

  StreamSubscription<int?>? _indexSub;

  /// Keeps "recently played" and the resume-queue in sync as the playlist
  /// advances on its own.
  void _watchTrackChanges() {
    _indexSub?.cancel();
    _indexSub = player.currentIndexStream.listen((i) {
      if (i == null || i < 0 || i >= _queue.length) return;
      _afterTrackChange(_queue[i]);
    });
  }

  void _afterTrackChange(LibraryItem item) {
    revision.value++;
    unawaited(MusicPrefsService.notePlayed(item.id));
    unawaited(
      MusicPrefsService.saveQueue(_queue, player.currentIndex ?? 0),
    );
  }

  /// Restores the queue persisted by a previous session so the mini bar can
  /// reappear on cold start. Loads paused — never auto-plays on launch.
  Future<void> restoreLastQueue() async {
    if (hasQueue) return;
    final saved = MusicPrefsService.lastQueue();
    if (saved == null) return;
    final (items, index) = saved;
    try {
      await MusicDownloadService.warmPaths(items);
      _queue = items;
      _loadedSignature = items.map((e) => e.id).join(',');
      await player.setAudioSource(
        ConcatenatingAudioSource(
          children: [for (final item in items) _sourceFor(item)],
        ),
        initialIndex: index,
        initialPosition: Duration.zero,
      );
      await player.setSpeed(MusicPrefsService.speed());
      revision.value++;
      _watchTrackChanges();
    } catch (e) {
      debugPrint('restoreLastQueue failed: $e');
    }
  }

  // ---- Transport ----------------------------------------------------------

  Future<void> togglePlayPause() async {
    if (player.playing) {
      await player.pause();
    } else {
      await player.play();
    }
  }

  Future<void> next() async {
    if (player.hasNext) await player.seekToNext();
  }

  Future<void> previous() async {
    // Restart the track when more than 3s in, else step back — standard
    // player behaviour.
    if (player.position > const Duration(seconds: 3) || !player.hasPrevious) {
      await player.seek(Duration.zero);
    } else {
      await player.seekToPrevious();
    }
  }

  /// Jumps forward/back within the current track. Used by the ±15s buttons,
  /// which matter most for the Audio Bible.
  Future<void> nudge(Duration delta) async {
    final target = player.position + delta;
    final duration = player.duration ?? Duration.zero;
    final clamped = target < Duration.zero
        ? Duration.zero
        : (duration > Duration.zero && target > duration ? duration : target);
    await player.seek(clamped);
  }

  Future<void> toggleShuffle() async {
    final on = !player.shuffleModeEnabled;
    if (on) await player.shuffle();
    await player.setShuffleModeEnabled(on);
    revision.value++;
  }

  /// Cycles off → all → one → off.
  Future<LoopMode> cycleRepeat() async {
    final next = switch (player.loopMode) {
      LoopMode.off => LoopMode.all,
      LoopMode.all => LoopMode.one,
      LoopMode.one => LoopMode.off,
    };
    await player.setLoopMode(next);
    revision.value++;
    return next;
  }

  /// Sets and persists playback speed (0.5×–2×).
  Future<void> setSpeed(double speed) async {
    final v = speed.clamp(0.5, 2.0);
    await player.setSpeed(v);
    await MusicPrefsService.setSpeed(v);
    revision.value++;
  }

  double get speed => _player?.speed ?? MusicPrefsService.speed();

  /// Plays the track at [index] in the ALREADY-loaded queue.
  Future<void> jumpTo(int index) async {
    if (index < 0 || index >= _queue.length) return;
    await player.seek(Duration.zero, index: index);
    await player.play();
  }

  // ---- Sleep timer --------------------------------------------------------

  Timer? _sleepTimer;

  /// When a sleep timer is armed, the wall-clock moment it fires.
  final ValueNotifier<DateTime?> sleepAt = ValueNotifier<DateTime?>(null);

  /// Pauses playback after [duration]. Passing null cancels a pending timer.
  void setSleepTimer(Duration? duration) {
    _sleepTimer?.cancel();
    if (duration == null) {
      sleepAt.value = null;
      return;
    }
    sleepAt.value = DateTime.now().add(duration);
    _sleepTimer = Timer(duration, () async {
      await player.pause();
      sleepAt.value = null;
    });
  }

  bool get hasSleepTimer => sleepAt.value != null;

  /// Stops playback and tears the queue down (used by "Close player").
  Future<void> stop() async {
    _sleepTimer?.cancel();
    sleepAt.value = null;
    await _indexSub?.cancel();
    _indexSub = null;
    await player.stop();
    _queue = const [];
    _loadedSignature = '';
    revision.value++;
    unawaited(MusicPrefsService.clearQueue());
  }
}
