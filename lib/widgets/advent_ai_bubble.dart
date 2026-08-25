import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../config/router_config.dart';
import '../screens/library/widgets/now_playing_bar.dart';
import '../services/music_player_service.dart';
import '../theme/app_tokens.dart';
import 'advent_ai_mark.dart';
import 'global_media_bars.dart';
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
    //
    // The INBOX carries its own Advent AI button above the compose
    // button (see conversations_screen.dart) — asked for on 25 Aug 2026.
    // That is a deliberate, stationary entry point on a list of chats,
    // not a control floating over somebody's open conversation, and the
    // rule this line enforces is about the second thing.
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

    // ---- Founder call, 25 Aug 2026 -----------------------------------
    // Both are screens a member is working THROUGH rather than reading:
    // Settings is a long list of controls the bubble lands on top of,
    // and the Quiz is timed — a floating button over a question someone
    // is racing to answer is a mis-tap waiting to happen.
    '/settings',
    '/quiz',
  ];

  static bool allowedOn(String location) =>
      !blockedPrefixes.any(location.startsWith);

  /// Held up while an Advent AI screen is mounted.
  ///
  /// [blockedPrefixes] already refuses `/advent-ai`, and that should be
  /// enough — but it is a check on the router's *reported* location, and
  /// the founder reported seeing the bubble on the AI screen anyway
  /// (25 Aug 2026). A screen that knows it is open is a fact rather than
  /// an inference, so it gets to say so directly. A counter, not a bool,
  /// so an AI screen pushed over an AI screen still leaves it suppressed
  /// on the way back out.
  static final ValueNotifier<int> suppressed = ValueNotifier<int>(0);

  /// Call from `initState` / `dispose` of any screen that must not have
  /// the bubble floating over it.
  static void suppress() => suppressed.value++;
  static void unsuppress() =>
      suppressed.value = (suppressed.value - 1).clamp(0, 1 << 30);

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

  /// Clearance from the bottom on screens that have no island. The
  /// island's own 96 is too much where there is no island, but the bare
  /// `AppSpace.md` this used to fall back to put the bubble level with
  /// send buttons and bottom sheets' handles. This clears them without
  /// leaving it stranded halfway up the screen.
  static const double _plainInset = 40;

  /// Parked slot, held statically so it survives route changes and the
  /// bubble being unmounted on a blocked route.
  ///
  /// **Defaults to the LOWEST slot on the right** (founder call, 25 Aug
  /// 2026: "it's a bit high, lower it down in all screens"). At y = 1 the
  /// bubble rests directly on whichever bottom margin the screen resolves
  /// below — the island on the five tab destinations, [_plainInset]
  /// everywhere else — so on Home it sits just above the tabs, which is
  /// where it was asked for.
  static final ValueNotifier<Alignment> anchor =
      ValueNotifier<Alignment>(const Alignment(1, 1));

  /// Six parking slots. The whole ladder moved down with the default: the
  /// old top slot (-0.6) put the bubble level with a screen's header, and
  /// nobody drags a button UP into a title bar on purpose.
  static final List<Alignment> _anchors = [
    for (final y in const [-0.1, 0.5, 1.0])
      for (final x in const [-1.0, 1.0]) Alignment(x, y),
  ];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: suppressed,
      builder: (context, held, _) {
        if (held > 0) return const SizedBox.shrink();
        return _build(context);
      },
    );
  }

  Widget _build(BuildContext context) {
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
                : _plainInset + MediaQuery.paddingOf(context).bottom;

            return _MusicAware(
              builder: (context, musicInset) => FloatingDock(
                size: const Size(_size, _size),
                anchors: _anchors,
                anchor: anchor,
                margin: EdgeInsets.fromLTRB(
                  AppSpace.md,
                  MediaQuery.paddingOf(context).top + AppSpace.xl,
                  AppSpace.md,
                  inset + musicInset,
                ),
                child: const _BubbleButton(),
              ),
            );
          },
        );
      },
    );
  }
}

/// Hands its builder however much extra bottom clearance the docked
/// music card needs, or zero.
///
/// # Why this exists
///
/// The bubble's resting slot moved to the bottom edge on 25 Aug 2026,
/// and the music card's default slot is bottom-CENTRE — a card up to
/// 380dp wide against a 56dp button on the same line. They shared the
/// same bottom inset (96, the island), so the bubble came to rest
/// squarely on top of the now-playing card whenever anything was
/// playing. Lowering the button was the founder's call; landing it on
/// the music player was not.
///
/// The card only ever moves along its own six slots, so "is it on the
/// bottom row" is the whole question — `anchor.y == 1`. A card parked
/// anywhere else is not in this button's way and gets no clearance.
///
/// The nesting mirrors [NowPlayingBar] exactly, and for its reason:
/// `MusicPlayerService.instance` constructs an AudioPlayer at the call
/// site, so it must not be touched until `ready` is true. This widget is
/// mounted in `MaterialApp.builder` and paints on the first frame, over
/// the splash.
class _MusicAware extends StatelessWidget {
  const _MusicAware({required this.builder});

  final Widget Function(BuildContext, double) builder;

  /// The card's height plus a gap, so the two do not merely touch.
  static const double _clearance = NowPlayingBar.barHeight + 4 + AppSpace.sm;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Alignment>(
      valueListenable: GlobalMediaBars.musicAnchor,
      builder: (context, musicAnchor, _) {
        if (musicAnchor.y != 1.0) return builder(context, 0);

        return ValueListenableBuilder<bool>(
          valueListenable: MusicPlayerService.ready,
          builder: (context, ready, _) {
            if (!ready) return builder(context, 0);

            final service = MusicPlayerService.instance;
            return ValueListenableBuilder<int>(
              valueListenable: service.revision,
              builder: (context, _, _) => builder(
                context,
                service.current == null ? 0 : _clearance,
              ),
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
      label: AdventAiBrand.name,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          // Pushed on the ROOT navigator: this layer sits above the
          // shell, so a nested push would be swallowed by whichever tab
          // happened to be showing.
          onTap: () => rootNavigatorKey.currentContext?.push('/advent-ai'),
          child: const AdventAiMark(),
        ),
      ),
    );
  }
}
