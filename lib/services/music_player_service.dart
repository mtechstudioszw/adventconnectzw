import 'package:just_audio/just_audio.dart';

import '../models/library_item_model.dart';

/// App-wide music player for the Library Music tab.
///
/// Plain [just_audio] — NO just_audio_background. The background plugin kept
/// throwing "_audioHandler has not been initialized" / MediaItem-tag errors on
/// some devices, so music wouldn't play at all. A plain AudioPlayer plays
/// reliably (in-app now-playing bar + full player). Lock-screen / background
/// notification controls are intentionally dropped for reliability; they can
/// be re-added later via a properly-configured audio_service.
///
/// Singleton so the now-playing bar, the music tab and the full player screen
/// all reflect one shared playback state.
class MusicPlayerService {
  MusicPlayerService._();
  static final MusicPlayerService instance = MusicPlayerService._();

  final AudioPlayer player = AudioPlayer();

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
    final signature = items.map((e) => e.id).join(',');
    if (signature == _loadedSignature) {
      await player.seek(Duration.zero, index: startIndex);
      await player.play();
      return;
    }
    _queue = items;
    _loadedSignature = signature;

    // Plain progressive streaming, no MediaItem tags. The PDF/audio is cached
    // by the OS HTTP layer; offline downloads use the per-track Download button.
    final source = ConcatenatingAudioSource(
      children: [
        for (final item in items) AudioSource.uri(Uri.parse(item.fileUrl)),
      ],
    );
    await player.setAudioSource(
      source,
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
