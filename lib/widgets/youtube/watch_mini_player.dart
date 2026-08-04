import 'dart:async';

import 'package:flutter/material.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../config/router_config.dart';
import '../../services/mini_player_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_tokens.dart';
import '../media/floating_dock.dart';

/// The floating video window that keeps a sermon playing while you browse.
///
/// ## What changed and why
///
/// This used to be a full-width bar with a 92dp thumbnail-sized embed pinned
/// to the bottom of the screen. It played video, but it read as a notification
/// about a video. The founder asked for "a real YouTube-style floating player,
/// draggable and resizable with video playing inside" — so the video IS the
/// window now: 16:9, corner-parked, moved with a finger and sized with the
/// grip, with controls that fade in on tap the way YouTube's do.
///
/// The embed is the same live [YoutubePlayerController] throughout. It is
/// never rebuilt by dragging or resizing — a WebView reloads if it is
/// re-parented, and a reload here means the sermon restarts. [FloatingDock]
/// only ever moves the box the player already lives in.
///
/// Positioning and size live in statics on this class, not in State, because
/// `GlobalMediaBars` rebuilds on every route change: State would reset the
/// window to the default corner each time you navigated.
class WatchMiniPlayer extends StatelessWidget {
  const WatchMiniPlayer({super.key});

  /// Parked corner. Defaults to bottom-right, clear of the back gesture on
  /// the left edge and of most FABs.
  static final ValueNotifier<Alignment> anchor =
      ValueNotifier<Alignment>(Alignment.bottomRight);

  /// Window width; height follows at 16:9.
  static final ValueNotifier<double> width = ValueNotifier<double>(196);

  static const double minWidth = 148;
  static const double maxWidth = 300;

  /// Corners it may park in.
  static const List<Alignment> anchors = [
    Alignment.topLeft,
    Alignment.topRight,
    Alignment.bottomLeft,
    Alignment.bottomRight,
  ];

  @override
  Widget build(BuildContext context) {
    final svc = MiniPlayerService.instance;
    return AnimatedBuilder(
      animation: svc,
      builder: (context, _) {
        if (!svc.isActive || svc.isExpanding) return const SizedBox.shrink();
        return ValueListenableBuilder<double>(
          valueListenable: width,
          builder: (context, w, _) => _FloatingWindow(service: svc, width: w),
        );
      },
    );
  }
}

class _FloatingWindow extends StatefulWidget {
  const _FloatingWindow({required this.service, required this.width});

  final MiniPlayerService service;
  final double width;

  @override
  State<_FloatingWindow> createState() => _FloatingWindowState();
}

class _FloatingWindowState extends State<_FloatingWindow> {
  /// Controls are revealed on tap and hide themselves again, so the window is
  /// mostly just video. Anything that keeps chrome permanently over a 196dp
  /// picture is covering the thing you are trying to watch.
  bool _controlsVisible = true;
  Timer? _hideControls;

  @override
  void initState() {
    super.initState();
    _scheduleHide();
  }

  @override
  void dispose() {
    // A cancellable Timer, not a `mounted` check: `mounted` is not a
    // sufficient guard during teardown, and a pending callback that calls
    // setState after dispose throws.
    _hideControls?.cancel();
    super.dispose();
  }

  void _scheduleHide() {
    _hideControls?.cancel();
    _hideControls = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  void _revealControls() {
    setState(() => _controlsVisible = true);
    _scheduleHide();
  }

  Future<void> _expand() async {
    final video = widget.service.video;
    if (video == null) return;
    // takeOver() persists the position and tears the window down, so the
    // player screen's own resume read lands on the right second.
    await widget.service.takeOver();
    appRouter.pushNamed(
      'watch_video',
      pathParameters: {'id': video.videoId},
      extra: video,
    );
  }

  @override
  Widget build(BuildContext context) {
    final video = widget.service.video;
    final controller = widget.service.controller;
    if (video == null || controller == null) return const SizedBox.shrink();

    final height = widget.width * 9 / 16;
    final playing =
        controller.value.playerState == PlayerState.playing;

    return FloatingDock(
      size: Size(widget.width, height),
      anchors: WatchMiniPlayer.anchors,
      anchor: WatchMiniPlayer.anchor,
      minWidth: WatchMiniPlayer.minWidth,
      maxWidth: WatchMiniPlayer.maxWidth,
      onResize: (next) => WatchMiniPlayer.width.value = next,
      // Bottom clearance keeps the window off the floating navigation
      // island when it is parked low.
      margin: const EdgeInsets.fromLTRB(
        AppSpace.md,
        AppSpace.md,
        AppSpace.md,
        96,
      ),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.white.withValues(alpha: 0.14)),
          boxShadow: AppShadows.floating(context),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // The live embed. IgnorePointer so YouTube's own overlay never
            // eats a drag — every gesture belongs to the window.
            IgnorePointer(
              child: YoutubePlayer(
                controller: controller,
                aspectRatio: 16 / 9,
              ),
            ),
            // Tap anywhere to bring the controls back.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _controlsVisible ? _expand : _revealControls,
                child: const SizedBox.expand(),
              ),
            ),
            AnimatedOpacity(
              opacity: _controlsVisible ? 1 : 0,
              duration: AppMotion.maybe(context, AppMotion.quick),
              child: IgnorePointer(
                ignoring: !_controlsVisible,
                child: _controls(playing),
              ),
            ),
            // Close stays PUT.
            //
            // It used to live inside the fading control layer with play and
            // expand, so three seconds after the window appeared the only
            // way to get rid of it vanished — you had to tap the video to
            // bring the controls back, and a tap that lands while they are
            // already up expands to full screen instead. That is a window
            // you cannot obviously dismiss, which is why it read as having
            // no exit button at all.
            //
            // Getting out of something must never be the control that hides
            // itself. It sits above the tap layer so it always wins the
            // gesture.
            Positioned(
              top: 1,
              right: 1,
              child: _glyph(
                icon: Icons.close_rounded,
                size: 16,
                tooltip: 'Close',
                onTap: widget.service.close,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _controls(bool playing) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.45),
            Colors.transparent,
            Colors.black.withValues(alpha: 0.45),
          ],
          stops: const [0, 0.5, 1],
        ),
      ),
      child: Stack(
        children: [
          Align(
            // heightFactor pins this to the glyph's own size. Inside a Stack
            // the constraints are tight rather than unbounded, and a bare
            // Align would happily take the whole window.
            alignment: Alignment.center,
            heightFactor: 1,
            widthFactor: 1,
            child: _glyph(
              icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              size: 26,
              tooltip: playing ? 'Pause' : 'Play',
              onTap: () {
                widget.service.togglePlay();
                _scheduleHide();
              },
            ),
          ),
          // Close is NOT here — it is pinned outside this fading layer so
          // it never disappears. See the note at the call site.
          Positioned(
            top: 1,
            left: 1,
            child: _glyph(
              icon: Icons.open_in_full_rounded,
              size: 14,
              tooltip: 'Back to full screen',
              onTap: _expand,
            ),
          ),
        ],
      ),
    );
  }

  Widget _glyph({
    required IconData icon,
    required double size,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: size + 6,
        child: Container(
          margin: const EdgeInsets.all(4),
          padding: EdgeInsets.all(size > 20 ? 8 : 5),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.5),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: AppColors.white, size: size),
        ),
      ),
    );
  }
}
