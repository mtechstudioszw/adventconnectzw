import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../../../config/router_config.dart';
import '../../../models/library_item_model.dart';
import '../../../services/music_player_service.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_text_styles.dart';
import '../../../theme/app_tokens.dart';
import 'full_player_screen.dart';
import 'music_visuals.dart';

/// The music mini player: a bar you can move.
///
/// ## The shape and the movement are separate questions
///
/// It has been a full-width strip, then a draggable 190×172 card ("its shape
/// is wrong — it should read like a small video card"), then a docked bar
/// again ("don't make the mini player a card, make it like others e.g.
/// YouTube Music"), and it is now a **bar that drags** (9 Aug 2026).
///
/// That is not indecision, it is two separate calls that got conflated. The
/// card lost on SHAPE: 172dp tall, it covered content wherever it sat. Being
/// docked was never the ask — and pinning it to the bottom edge put it on the
/// one edge this app already crowds with a navigation island, snackbars and
/// send buttons, so the fixed position created the very problem the fixed
/// position was meant to avoid.
///
/// So: bar proportions, one row — artwork, title, artist, play/pause, dismiss
/// and a hairline of progress — and `GlobalMediaBars` wraps it in a
/// `FloatingDock` that parks it at any of nine slots.
///
/// **This widget must not claim drag gestures.** A vertical-drag recogniser
/// here beats the dock's pan recogniser and silently kills the dragging; see
/// the note in [_bar].
///
/// **Scope:** mounted app-wide by `GlobalMediaBars`, and stood down while the
/// full player is on screen (`MusicPlayerService.fullPlayerOpen`) so the two
/// never render at once. With the app in the background, controls come from
/// the Android media notification and the iOS lock screen.
class NowPlayingBar extends StatelessWidget {
  const NowPlayingBar({super.key});

  /// The bar's height, excluding the progress hairline. Fixed so callers can
  /// reserve space for it before the child has laid out.
  static const double barHeight = 62;

  @override
  Widget build(BuildContext context) {
    // Nothing here may touch `service.player` until the media session has
    // finished booting.
    //
    // `main()` no longer awaits `ensureInitialized()` — that 15-second
    // foreground-service bind was most of the launch time — and this widget
    // is mounted in the MaterialApp builder, so it renders on the very first
    // frame, over the splash. Reading `player` there would construct an
    // AudioPlayer in the middle of the platform swap, which is the
    // `_audioHandler has not been initialized` crash that got background
    // playback removed once before. Nothing can be playing this early
    // anyway, so waiting costs nothing.
    return ValueListenableBuilder<bool>(
      valueListenable: MusicPlayerService.ready,
      builder: (context, ready, _) {
        if (!ready) return const SizedBox.shrink();
        return _build(context);
      },
    );
  }

  Widget _build(BuildContext context) {
    final service = MusicPlayerService.instance;
    // Rebuild on both track changes AND queue teardown — stop() clears the
    // queue without emitting a new index, so the index stream alone would
    // leave the bar on screen with nothing playing.
    return ValueListenableBuilder<int>(
      valueListenable: service.revision,
      builder: (context, _, _) {
        return StreamBuilder<int?>(
          stream: service.player.currentIndexStream,
          builder: (context, _) {
            final item = service.current;
            return AnimatedSwitcher(
              duration: AppMotion.maybe(context, AppMotion.standard),
              switchInCurve: AppMotion.easeOut,
              switchOutCurve: AppMotion.easeIn,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SizeTransition(
                  sizeFactor: animation,
                  axisAlignment: -1,
                  child: child,
                ),
              ),
              child: item == null
                  ? const SizedBox.shrink()
                  : _bar(context, service, item),
            );
          },
        );
      },
    );
  }

  Widget _bar(
    BuildContext context,
    MusicPlayerService service,
    LibraryItem item,
  ) {
    return Material(
      key: ValueKey(item.id),
      color: Colors.transparent,
      // NO vertical-drag handler here.
      //
      // There used to be one — flick up to open, flick down to dismiss. It
      // has to go now that the card is draggable, because a
      // VerticalDragGestureRecognizer on the child BEATS the
      // PanGestureRecognizer that `FloatingDock` puts on the ancestor: the
      // vertical recogniser claims the gesture as soon as the finger moves
      // on the Y axis, so the dock never saw the drag and the card could
      // only be moved sideways. That is the "mini player can't be dragged"
      // the founder reported on 9 Aug 2026.
      //
      // Nothing is lost. Tapping the card already opens the full player, and
      // the X button already dismisses it — the two flicks were shortcuts to
      // controls that are both still right there.
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.darkNavy,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.white.withValues(alpha: 0.12)),
          boxShadow: AppShadows.floating(context),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _progressLine(service),
            SizedBox(
              height: barHeight,
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => _open(context),
                      child: Row(
                        children: [
                          const SizedBox(width: 8),
                          Hero(
                            tag: 'now-playing-art',
                            child: TrackArtwork(
                              coverUrl: item.coverUrl,
                              size: 46,
                              radius: 8,
                              icon: item.kind == 'audio_bible'
                                  ? Icons.menu_book_rounded
                                  : Icons.music_note_rounded,
                            ),
                          ),
                          const SizedBox(width: 11),
                          Expanded(child: _caption(item)),
                        ],
                      ),
                    ),
                  ),
                  _playButton(service),
                  _iconButton(
                    icon: Icons.close_rounded,
                    size: 20,
                    tooltip: 'Stop',
                    // Stop, not pause: pausing would leave the bar sitting
                    // there with nothing to dismiss it.
                    onPressed: service.stop,
                  ),
                  const SizedBox(width: 6),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _caption(LibraryItem item) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          item.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.labelMedium.copyWith(
            color: AppColors.white,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          (item.author?.isNotEmpty ?? false)
              ? item.author!
              : 'Adventist Super App',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.labelSmall.copyWith(
            color: AppColors.white.withValues(alpha: 0.62),
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  /// Play/pause only.
  ///
  /// Previous and next are deliberately not here — they are in the full
  /// player, one tap away. A 62dp bar that has to hold artwork, two lines of
  /// text and five controls gives each of them a target too small to hit,
  /// and skip is not what anyone reaches for from another screen.
  Widget _playButton(MusicPlayerService service) {
    return StreamBuilder<PlayerState>(
      stream: service.player.playerStateStream,
      builder: (context, snap) {
        final state = snap.data;
        final playing = state?.playing ?? false;
        final loading =
            state?.processingState == ProcessingState.loading ||
            state?.processingState == ProcessingState.buffering;
        return SizedBox(
          width: 44,
          height: 44,
          child: loading
              ? const Padding(
                  padding: EdgeInsets.all(13),
                  child: CircularProgressIndicator(
                    color: AppColors.white,
                    strokeWidth: 2.2,
                  ),
                )
              : _iconButton(
                  icon: playing
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  size: 27,
                  tooltip: playing ? 'Pause' : 'Play',
                  animateSwap: true,
                  onPressed: service.togglePlayPause,
                ),
        );
      },
    );
  }

  Widget _iconButton({
    required IconData icon,
    required double size,
    required String tooltip,
    required VoidCallback onPressed,
    bool animateSwap = false,
  }) {
    final glyph = Icon(icon, color: AppColors.white, size: size);
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onPressed,
        radius: size,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: animateSwap
              ? AnimatedSwitcher(
                  duration: AppMotion.quick,
                  transitionBuilder: (child, anim) =>
                      ScaleTransition(scale: anim, child: child),
                  child: KeyedSubtree(key: ValueKey(icon), child: glyph),
                )
              : glyph,
        ),
      ),
    );
  }

  /// Hairline progress along the top edge — the cheapest possible "where am
  /// I in this track" signal.
  Widget _progressLine(MusicPlayerService service) {
    return StreamBuilder<Duration>(
      stream: service.player.positionStream,
      builder: (context, snap) {
        final duration = service.player.duration ?? Duration.zero;
        final position = snap.data ?? Duration.zero;
        final value = duration.inMilliseconds <= 0
            ? 0.0
            : (position.inMilliseconds / duration.inMilliseconds).clamp(
                0.0,
                1.0,
              );
        return SizedBox(
          height: 2,
          child: LinearProgressIndicator(
            value: value,
            minHeight: 2,
            backgroundColor: AppColors.white.withValues(alpha: 0.14),
            valueColor: const AlwaysStoppedAnimation<Color>(
              AppColors.goldAccent,
            ),
          ),
        );
      },
    );
  }

  void _open(BuildContext context) {
    // NOT Navigator.of(context): this bar is mounted in an overlay above the
    // router's Navigator, so there is no Navigator to find and the lookup
    // throws. Push on the root navigator directly.
    final nav = rootNavigatorKey.currentState;
    if (nav == null) return;

    // Stand the bar down HERE, at the push, rather than relying on
    // FullPlayerScreen.initState to do it.
    //
    // The flag used to be raised only once the pushed route built its State.
    // That is a frame or more after the push, it is skipped entirely if the
    // route is built lazily or replaced, and `dispose()` — the only thing
    // that lowered it — runs on a teardown we do not control the timing of.
    // The result the founder saw was the bar still sitting on top of the
    // full player. Owning the flag at the call site makes it exact: down
    // before the route exists, up again when the route has actually gone.
    MusicPlayerService.fullPlayerOpen.value = true;

    nav
        .push(
          PageRouteBuilder<void>(
            transitionDuration: AppMotion.entrance,
            reverseTransitionDuration: AppMotion.standard,
            opaque: false,
            pageBuilder: (_, _, _) => const FullPlayerScreen(),
            transitionsBuilder: (context, animation, _, child) {
              // Slide up from the bar — gesture and transition agree.
              final curved = CurvedAnimation(
                parent: animation,
                curve: AppMotion.easeOut,
                reverseCurve: AppMotion.easeIn,
              );
              return SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 1),
                  end: Offset.zero,
                ).animate(curved),
                child: child,
              );
            },
          ),
        )
        // Fires once the route is genuinely off the stack, however it left —
        // chevron, back button, or the drag-down dismiss.
        .whenComplete(() => MusicPlayerService.fullPlayerOpen.value = false);
  }
}
