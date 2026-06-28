import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import '../models/library_item_model.dart';

/// App-wide background music player for the Library Music tab.
///
/// Wraps a single [AudioPlayer] from `just_audio`. Because the app calls
/// `JustAudioBackground.init()` in main(), each [MediaItem] tag below surfaces
/// as a lock-screen / notification media session — so playback continues when
/// the app is backgrounded and the user can play/pause/skip from there.
///
/// Singleton so the now-playing bar, the music tab and the full player screen
/// all reflect one shared playback state.
class MusicPlayerService {
  MusicPlayerService._();
  static final MusicPlayerService instance = MusicPlayerService._();

  final AudioPlayer player = AudioPlayer();

  // just_audio_background must be init()'d exactly once, BEFORE any tagged
  // AudioSource is loaded — otherwise loading a track throws
  // "LateInitializationError: Field '_audioHandler' has not been initialized"
  // (the "music won't play" crash). We run it through a single shared future
  // so it's idempotent, and remember whether it succeeded. If it FAILS on a
  // device (some OEMs reject the media service), we fall back to plain,
  // tag-less playback so music still plays — just without the lock-screen
  // notification.
  static Future<void>? _bgInit;
  static bool _bgReady = false;

  static Future<void> ensureBackgroundReady() {
    return _bgInit ??= JustAudioBackground.init(
      androidNotificationChannelId: 'zw.adventconnect.audio',
      androidNotificationChannelName: 'Advent Connect Music',
      androidNotificationOngoing: true,
    ).then((_) {
      _bgReady = true;
    }).catchError((_) {
      _bgReady = false; // degrade to foreground-only playback
    });
  }

  /// The playlist currently loaded (the music tab's list), so the now-playing
  /// bar can resolve titles/art by index.
  List<LibraryItem> _queue = const [];
  List<LibraryItem> get queue => _queue;

  /// The id of the item whose playlist is loaded, to avoid rebuilding the
  /// source when the user taps another track in the same list.
  String _loadedSignature = '';

  bool get hasQueue => _queue.isNotEmpty;

  /// The currently-playing item, derived from the player's current index.
  LibraryItem? get current {
    final i = player.currentIndex;
    if (i == null || i < 0 || i >= _queue.length) return null;
    return _queue[i];
  }

  /// Load [items] as the active playlist and start at [startIndex]. Reuses the
  /// existing source if the same list is already loaded (just seeks).
  Future<void> setQueueAndPlay(
    List<LibraryItem> items,
    int startIndex,
  ) async {
    // Make sure the media session is up before loading a tagged source. Safe
    // to await every time — it resolves instantly after the first run.
    await ensureBackgroundReady();

    final signature = items.map((e) => e.id).join(',');
    if (signature == _loadedSignature) {
      await player.seek(Duration.zero, index: startIndex);
      await player.play();
      return;
    }
    _queue = items;
    _loadedSignature = signature;

    final sources = items
        .map(
          (item) => AudioSource.uri(
            Uri.parse(item.fileUrl),
            // Only attach the MediaItem tag when the background handler is
            // ready; a tag without it crashes playback. Tag-less still plays.
            tag: _bgReady
                ? MediaItem(
                    id: item.id,
                    title: item.title,
                    artist: item.author ?? 'Advent Connect ZW',
                    artUri:
                        (item.coverUrl != null && item.coverUrl!.isNotEmpty)
                            ? Uri.parse(item.coverUrl!)
                            : null,
                  )
                : null,
          ),
        )
        .toList();

    await player.setAudioSource(
      ConcatenatingAudioSource(children: sources),
      initialIndex: startIndex,
      initialPosition: Duration.zero,
    );
    await player.play();
  }

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
    // Restart the track if we're more than 3s in, else go to the previous one
    // (standard player behaviour).
    if ((player.position) > const Duration(seconds: 3) || !player.hasPrevious) {
      await player.seek(Duration.zero);
    } else {
      await player.seekToPrevious();
    }
  }

  Future<void> toggleShuffle() async {
    final on = !player.shuffleModeEnabled;
    if (on) await player.shuffle();
    await player.setShuffleModeEnabled(on);
  }

  /// Cycles off → all → one → off.
  Future<LoopMode> cycleRepeat() async {
    final next = switch (player.loopMode) {
      LoopMode.off => LoopMode.all,
      LoopMode.all => LoopMode.one,
      LoopMode.one => LoopMode.off,
    };
    await player.setLoopMode(next);
    return next;
  }
}
