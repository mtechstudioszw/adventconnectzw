import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../config/router_config.dart';
import '../services/music_player_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';
import 'media/floating_dock.dart';

/// The app-wide Advent AI button.
///
/// # Why this one works when the last floating bubble did not
///
/// A floating chat bubble shipped on 2026-07-27 and was **unreachable**.
/// Two mechanical reasons, both fixed here rather than argued with:
///
///  1. It was mounted INSIDE the router's Navigator, so the floating
///     navigation island painted over it. This widget goes in the same
///     layer as [GlobalMediaBars] — `MaterialApp.builder`, ABOVE the
///     Navigator — which is exactly how the music card and the Watch
///     window already solve it.
///  2. It was wired to `HideOnScroll`, so it slid away with the island.
///     Nothing here listens to scroll. It is on a layer that does not
///     scroll.
///
/// The bubble is draggable and parks at the nearest of six edge slots,
/// for the same reason the founder gave twice about the music card: the
/// bottom edge is where this app puts its island, its snackbars and its
/// send buttons, so a fixed corner means "always in the way of the same
/// things". Move it once and it stays.
///
/// # Where it does NOT appear — [blockedPrefixes]
///
/// **Founder rule, 23 Aug 2026: nothing to do with messaging.** An AI
/// button floating over a private conversation reads as the app watching
/// it. It is not, and the architecture makes that true rather than
/// promising it — the bubble carries no screen content, and Advent AI
/// has no tool that can read a message — but a member cannot inspect an
/// architecture. They can only see what is on top of their chat. So it
/// is absent there, and `advent_ai_bubble_test.dart` pins that.
///
/// The other entries are not privacy; they are places a floating control
/// is simply wrong: pre-auth screens where there is no member yet,
/// app-replacement screens, and deliberately full-screen surfaces.
class AdventAiBubble extends StatelessWidget {
  const AdventAiBubble({super.key});

  /// Route prefixes where the bubble must never appear.
  static const List<String> blockedPrefixes = <String>[
    // ---- Privacy. Founder rule; do not add exceptions. --------------
    '/messages',

    // ---- No authenticated member yet --------------------------------
    '/splash',
    '/onboarding',
    '/login',
    '/signup',
    '/email-verification',
    '/profile-setup',
    '/forgot-password',
    '/reset-password',
    '/biometric-lock',

    // ---- The app is replaced by these -------------------------------
    '/maintenance',
    '/account-banned',
    '/update-required',

    // ---- Deliberately full-screen or self-contained ------------------
    '/advent-ai', // already there
    '/admin',
  ];

  static bool allowedOn(String location) =>
      !blockedPrefixes.any(location.startsWith);

  /// Clears the floating navigation island on the five tab destinations.
  /// Same figure as [GlobalMediaBars] — they share an edge and must not
  /// disagree about where it is.
  static const double _islandInset = 96;

  static const _tabPaths = {
    '/home',
    '/watch',
    '/messages',
    '/marketplace',
    '/profile',
  };

  static const double _size = 56;

  /// Parked slot, held statically so it survives route changes and the
  /// bubble being unmounted on a blocked route. Defaults to the right
  /// edge, above the island — clear of the composer on the feed and of
  /// the send button everywhere else.
  static final ValueNotifier<Alignment> anchor =
      ValueNotifier<Alignment>(const Alignment(1, 0.55));

  static final List<Alignment> _anchors = [
    for (final y in const [-0.6, 0.0, 0.55])
      for (final x in const [-1.0, 1.0]) Alignment(x, y),
  ];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: MusicPlayerService.fullPlayerOpen,
      builder: (context, fullPlayerOpen, _) {
        return AnimatedBuilder(
          animation: appRouter.routerDelegate,
          builder: (context, _) {
            final path = appRouter.routerDelegate.currentConfiguration.uri.path;
            if (!allowedOn(path)) return const SizedBox.shrink();

            // Nothing sits on top of a deliberately full-screen player.
            // The media bars already stand down here; a bubble that did
            // not would be the only thing left floating over a video.
            if (fullPlayerOpen) return const SizedBox.shrink();

            final inset = _tabPaths.contains(path)
                ? _islandInset
                : AppSpace.md + MediaQuery.paddingOf(context).bottom;

            return FloatingDock(
              size: const Size(_size, _size),
              anchors: _anchors,
              anchor: anchor,
              margin: EdgeInsets.fromLTRB(
                AppSpace.md,
                MediaQuery.paddingOf(context).top + AppSpace.xl,
                AppSpace.md,
                inset,
              ),
              child: const _BubbleButton(),
            );
          },
        );
      },
    );
  }
}

class _BubbleButton extends StatelessWidget {
  const _BubbleButton();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Advent AI',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          // Pushed on the ROOT navigator: this layer sits above the
          // shell, so a nested push would be swallowed by whichever tab
          // happened to be showing.
          onTap: () => rootNavigatorKey.currentContext?.push('/advent-ai'),
          child: Container(
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryBlue.withValues(alpha: 0.32),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Center(
              child: Icon(
                Icons.auto_awesome_rounded,
                color: Colors.white,
                size: 26,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
