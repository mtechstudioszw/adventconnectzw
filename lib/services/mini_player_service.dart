import 'package:flutter/foundation.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../models/youtube_video.dart';
import 'music_player_service.dart';
import 'youtube_service.dart';

/// Keeps a video playing while the user browses the rest of the app.
///
/// ## Why a hand-off and not a moving player
///
/// Playback runs through the official YouTube IFrame player, which is a
/// WebView. A WebView cannot be re-parented between widget trees without
/// reloading, so the usual "shrink the player into the corner" trick —
/// where one player widget animates between two positions — is not
/// available to us. The alternatives were:
///
/// * host one WebView in a global overlay and have every screen render a
///   placeholder for it to be positioned over. Seamless, but it puts the
///   most important surface in the app behind an overlay-geometry system
///   that also has to cope with fullscreen, rotation and the live-chat
///   panel; or
/// * hand the position over: when the full player closes, the mini bar
///   starts its own controller at the second the last one reached.
///
/// This is the second. The cost is a ~1s re-buffer at the moment of
/// docking and expanding. The benefit is that the full player is
/// untouched, and a failure here can never take playback down with it.
///
/// True picture-in-picture is deliberately not attempted: OS-level PiP
/// would need native plumbing on both platforms, and YouTube's terms
/// don't permit backgrounding an embedded player.
class MiniPlayerService extends ChangeNotifier {
  MiniPlayerService._();

  static final MiniPlayerService instance = MiniPlayerService._();

  YoutubeVideo? _video;
  YoutubePlayerController? _controller;
  bool _expanding = false;

  YoutubeVideo? get video => _video;
  YoutubePlayerController? get controller => _controller;

  /// True while a video is docked and the bar should be on screen.
  bool get isActive => _video != null && _controller != null;

  /// Where the docked video has got to, for handing back to the full
  /// player. Best-effort: 0 if the controller can't be read.
  Future<int> currentSeconds() async {
    try {
      return (await _controller?.currentTime ?? 0).round();
    } catch (_) {
      return 0;
    }
  }

  /// Dock [video] and resume it at [atSeconds].
  ///
  /// Called when the full player is dismissed mid-playback.
  Future<void> dock(YoutubeVideo video, {int atSeconds = 0}) async {
    // A live stream has no meaningful position and a docked 16:9 strip is
    // a poor way to watch one — let live playback end with the screen.
    if (video.isLive) return;

    // Only one thing plays at a time.
    //
    // Both windows float over the whole app, so without this a docked
    // sermon and a hymn would play OVER each other — two audio streams and
    // two cards fighting for the same corner. Founder's call (4 Aug 2026):
    // opening the video window removes the music one.
    //
    // stop(), not pause(): the music card is dismissed along with the
    // sound, because a paused card that silently reappears later is worse
    // than one that clearly went away. This is the same `stop()` the ✕
    // button calls, so the behaviour is one the member already knows.
    await MusicPlayerService.instance.stop();

    await _disposeController();
    _video = video;
    _controller = YoutubePlayerController.fromVideoId(
      videoId: video.videoId,
      autoPlay: true,
      startSeconds: atSeconds.toDouble(),
      params: const YoutubePlayerParams(
        showControls: false,
        showFullscreenButton: false,
        showVideoAnnotations: false,
        enableCaption: false,
      ),
    );
    notifyListeners();
  }

  /// Hand the position back to the full player and clear the bar.
  ///
  /// Returns the second to resume from, so the caller can open the player
  /// exactly where the bar left off rather than at the last position that
  /// happened to reach the database.
  Future<int> takeOver() async {
    if (!isActive) return 0;
    _expanding = true;
    final at = await currentSeconds();
    final video = _video;
    if (video != null && at > 0) {
      // Persist too, so a cold open of the same video also resumes here.
      await YoutubeService.recordProgress(
        video.videoId,
        positionSeconds: at,
        durationSeconds: video.durationSeconds,
      );
    }
    await close();
    _expanding = false;
    return at;
  }

  /// True while [takeOver] is mid-flight — stops the bar flickering back
  /// on as the full player route pushes.
  bool get isExpanding => _expanding;

  Future<void> togglePlay() async {
    final c = _controller;
    if (c == null) return;
    try {
      final state = c.value.playerState;
      state == PlayerState.playing ? c.pauseVideo() : c.playVideo();
    } catch (_) {/* best effort */}
    notifyListeners();
  }

  /// Stop and clear, saving the position first so Keep-watching is right.
  Future<void> close() async {
    final video = _video;
    if (video != null && _controller != null) {
      final at = await currentSeconds();
      if (at > 0) {
        await YoutubeService.recordProgress(
          video.videoId,
          positionSeconds: at,
          durationSeconds: video.durationSeconds,
        );
      }
    }
    await _disposeController();
    _video = null;
    notifyListeners();
  }

  Future<void> _disposeController() async {
    final c = _controller;
    _controller = null;
    if (c != null) {
      try {
        await c.close();
      } catch (_) {/* already gone */}
    }
  }
}
