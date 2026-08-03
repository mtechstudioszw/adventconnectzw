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

/// The docked music card.
///
/// ## Why this is a card and not a bar
///
/// It used to be a full-width strip: artwork at 44dp on the left, then title,
/// then four icon buttons, spanning the whole screen. The founder's note was
/// that "its shape is wrong — a long horizontal bar where it should read like
/// a small video card", and they were right about the cause as well as the
/// symptom. A full-width strip claims a whole edge of the screen, so it reads
/// as chrome the app has imposed; a card reads as an object, which is what
/// lets it be picked up and moved. The shape and the draggability are the
/// same design decision.
///
/// So: cover art at the top under a scrim, transport over the art, a two-line
/// caption below, and a hairline of progress across the seam. [MusicDock]
/// wraps it in the [FloatingDock] that gives it top / middle / bottom.
///
/// **Scope:** mounted app-wide by `GlobalMediaBars`, and stood down while the
/// full player is on screen (`MusicPlayerService.fullPlayerOpen`) so the two
/// never render at once. With the app in the background, controls come from
/// the Android media notification and the iOS lock screen.
class NowPlayingBar extends StatelessWidget {
  const NowPlayingBar({super.key});

  /// The card's footprint. Fixed rather than measured: the dock needs a size
  /// to position against before the child has laid out, and a card that
  /// changed size as titles changed would drift away from its anchor.
  static const Size cardSize = Size(190, 172);

  static const double _artHeight = 107; // 190 × 9/16, so the art is 16:9

  @override
  Widget build(BuildContext context) {
    final service = MusicPlayerService.instance;
    // Rebuild on both track changes AND queue teardown — stop() clears the
    // queue without emitting a new index, so the index stream alone would
    // leave the card on screen with nothing playing.
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
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.92, end: 1).animate(animation),
                  child: child,
                ),
              ),
              child: item == null
                  ? const SizedBox.shrink()
                  : _card(context, service, item),
            );
          },
        );
      },
    );
  }

  Widget _card(
    BuildContext context,
    MusicPlayerService service,
    LibraryItem item,
  ) {
    return Material(
      key: ValueKey(item.id),
      color: Colors.transparent,
      child: GestureDetector(
        // Kept from the bar: a flick up still opens the full player, which is
        // the gesture people try first.
        onVerticalDragEnd: (d) {
          if (d.velocity.pixelsPerSecond.dy < -420) _open(context);
        },
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
              _art(context, service, item),
              _progressLine(service),
              _caption(service, item),
            ],
          ),
        ),
      ),
    );
  }

  // ---- Art + transport ----------------------------------------------------

  Widget _art(
    BuildContext context,
    MusicPlayerService service,
    LibraryItem item,
  ) {
    return SizedBox(
      height: _artHeight,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Blurred fill behind the square cover, so 16:9 never letterboxes
          // a square image against flat navy.
          BlurredArtBackdrop(coverUrl: item.coverUrl),
          Center(
            // heightFactor is not needed here — StackFit.expand already gives
            // this a tight constraint — but the art is a fixed square either
            // way, so nothing can grow to fill.
            child: Hero(
              tag: 'now-playing-art',
              child: TrackArtwork(
                coverUrl: item.coverUrl,
                size: 78,
                radius: 10,
                icon: item.kind == 'audio_bible'
                    ? Icons.menu_book_rounded
                    : Icons.music_note_rounded,
              ),
            ),
          ),
          // Tap the art to open the full player. Sits under the buttons.
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(onTap: () => _open(context)),
            ),
          ),
          Positioned(
            top: 2,
            right: 2,
            child: _iconButton(
              icon: Icons.close_rounded,
              size: 17,
              tooltip: 'Stop',
              // Stop, not pause: pausing would leave the card sitting there
              // with nothing to dismiss it.
              onPressed: service.stop,
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 4,
            child: _transport(service),
          ),
        ],
      ),
    );
  }

  Widget _transport(MusicPlayerService service) {
    return StreamBuilder<PlayerState>(
      stream: service.player.playerStateStream,
      builder: (context, snap) {
        final state = snap.data;
        final playing = state?.playing ?? false;
        final loading =
            state?.processingState == ProcessingState.loading ||
                state?.processingState == ProcessingState.buffering;
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _iconButton(
              icon: Icons.skip_previous_rounded,
              size: 21,
              tooltip: 'Previous',
              onPressed: service.previous,
            ),
            SizedBox(
              width: 38,
              height: 38,
              child: loading
                  ? const Padding(
                      padding: EdgeInsets.all(11),
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
            ),
            _iconButton(
              icon: Icons.skip_next_rounded,
              size: 21,
              tooltip: 'Next',
              onPressed: service.next,
            ),
          ],
        );
      },
    );
  }

  /// Transport buttons sit on artwork, which can be any colour, so each one
  /// carries its own dark scrim rather than relying on the image being dark.
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
        child: Container(
          margin: const EdgeInsets.all(3),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: AppColors.darkNavy.withValues(alpha: 0.55),
            shape: BoxShape.circle,
          ),
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

  // ---- Caption ------------------------------------------------------------

  Widget _caption(MusicPlayerService service, LibraryItem item) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 9),
      child: Column(
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
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            (item.author?.isNotEmpty ?? false)
                ? item.author!
                : 'Advent Connect ZW',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.white.withValues(alpha: 0.62),
              fontSize: 10.5,
            ),
          ),
        ],
      ),
    );
  }

  /// Hairline progress on the seam between art and caption — the cheapest
  /// possible "where am I in this track" signal.
  Widget _progressLine(MusicPlayerService service) {
    return StreamBuilder<Duration>(
      stream: service.player.positionStream,
      builder: (context, snap) {
        final duration = service.player.duration ?? Duration.zero;
        final position = snap.data ?? Duration.zero;
        final value = duration.inMilliseconds <= 0
            ? 0.0
            : (position.inMilliseconds / duration.inMilliseconds)
                .clamp(0.0, 1.0);
        return SizedBox(
          height: 2,
          child: LinearProgressIndicator(
            value: value,
            minHeight: 2,
            backgroundColor: AppColors.white.withValues(alpha: 0.14),
            valueColor:
                const AlwaysStoppedAnimation<Color>(AppColors.goldAccent),
          ),
        );
      },
    );
  }

  void _open(BuildContext context) {
    // NOT Navigator.of(context): this card is mounted in an overlay above the
    // router's Navigator, so there is no Navigator to find and the lookup
    // throws. Push on the root navigator directly.
    final nav = rootNavigatorKey.currentState;
    if (nav == null) return;
    nav.push(
      PageRouteBuilder<void>(
        transitionDuration: AppMotion.entrance,
        reverseTransitionDuration: AppMotion.standard,
        opaque: false,
        pageBuilder: (_, _, _) => const FullPlayerScreen(),
        transitionsBuilder: (context, animation, _, child) {
          // Slide up from the card — the gesture and the transition agree.
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
    );
  }
}
