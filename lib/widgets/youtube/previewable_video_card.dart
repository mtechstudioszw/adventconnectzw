import 'dart:async';

import 'package:flutter/material.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../models/youtube_video.dart';
import '../../services/connectivity_service.dart';
import '../../services/youtube_prefs.dart';
import 'youtube_video_card.dart';

/// Coordinates the in-feed auto-preview so ONLY ONE card ever plays at a
/// time — the one most centered in the viewport. Cards report their visible
/// fraction; the most-visible (above a threshold) becomes [active].
class PreviewController {
  PreviewController._();
  static final PreviewController instance = PreviewController._();

  /// videoId of the card that may currently preview, or null.
  final ValueNotifier<String?> active = ValueNotifier<String?>(null);
  final Map<String, double> _fractions = {};

  void report(String id, double fraction) {
    if (fraction <= 0.05) {
      _fractions.remove(id);
    } else {
      _fractions[id] = fraction;
    }
    _recompute();
  }

  void remove(String id) {
    _fractions.remove(id);
    _recompute();
  }

  void _recompute() {
    String? best;
    var bestF = 0.65; // must be ~2/3 on screen to win
    _fractions.forEach((id, f) {
      if (f > bestF) {
        bestF = f;
        best = id;
      }
    });
    if (active.value != best) active.value = best;
  }
}

/// A feed video card that auto-previews (muted, 5s loop) when it's the
/// centered card AND the user's "Autoplay previews" setting allows it
/// (Wi-Fi only / Always). Otherwise it's a normal static card. Tapping
/// always opens the full player (the preview ignores pointers).
class PreviewableVideoCard extends StatefulWidget {
  const PreviewableVideoCard({
    super.key,
    required this.video,
    required this.onTap,
    this.saved = false,
    this.onSaveToggle,
  });

  final YoutubeVideo video;
  final VoidCallback onTap;
  final bool saved;
  final VoidCallback? onSaveToggle;

  @override
  State<PreviewableVideoCard> createState() => _PreviewableVideoCardState();
}

class _PreviewableVideoCardState extends State<PreviewableVideoCard> {
  YoutubePlayerController? _controller;
  Timer? _restartTimer;
  Timer? _activateDebounce;
  bool _previewing = false;

  String get _id => widget.video.videoId;

  @override
  void initState() {
    super.initState();
    PreviewController.instance.active.addListener(_onActiveChanged);
  }

  bool get _allowed {
    switch (YoutubePrefs.previewMode) {
      case PreviewMode.never:
        return false;
      case PreviewMode.always:
        return ConnectivityService.isOnline;
      case PreviewMode.wifiOnly:
        return ConnectivityService.isWifi;
    }
  }

  void _onActiveChanged() {
    final isActive = PreviewController.instance.active.value == _id;
    if (isActive && _allowed && !widget.video.isLive) {
      // Debounce so fast scrolling doesn't spin up a webview per card.
      _activateDebounce?.cancel();
      _activateDebounce = Timer(const Duration(milliseconds: 350), () {
        if (mounted && PreviewController.instance.active.value == _id) {
          _startPreview();
        }
      });
    } else {
      _activateDebounce?.cancel();
      _stopPreview();
    }
  }

  void _startPreview() {
    if (_previewing) return;
    _previewing = true;
    _controller = YoutubePlayerController.fromVideoId(
      videoId: _id,
      autoPlay: true,
      startSeconds: 0,
      params: const YoutubePlayerParams(
        mute: true,
        showControls: false,
        showFullscreenButton: false,
        enableCaption: false,
        strictRelatedVideos: true,
      ),
    );
    // Loop the first 5 seconds as a teaser.
    _restartTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _controller?.seekTo(seconds: 0, allowSeekAhead: true);
    });
    if (mounted) setState(() {});
  }

  void _stopPreview() {
    if (!_previewing && _controller == null) return;
    _previewing = false;
    _restartTimer?.cancel();
    _restartTimer = null;
    _controller?.close();
    _controller = null;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    PreviewController.instance.active.removeListener(_onActiveChanged);
    PreviewController.instance.remove(_id);
    _activateDebounce?.cancel();
    _restartTimer?.cancel();
    _controller?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: Key('yt-prev-$_id'),
      onVisibilityChanged: (info) {
        if (!mounted) return;
        PreviewController.instance.report(_id, info.visibleFraction);
      },
      child: YoutubeVideoCard(
        video: widget.video,
        onTap: widget.onTap,
        saved: widget.saved,
        onSaveToggle: widget.onSaveToggle,
        // When previewing, overlay the muted player; IgnorePointer lets the
        // card's tap fall through to open the full player.
        thumbnailOverlay: (_previewing && _controller != null)
            ? IgnorePointer(
                child: YoutubePlayer(
                  controller: _controller!,
                  aspectRatio: 16 / 9,
                ),
              )
            : null,
      ),
    );
  }
}
