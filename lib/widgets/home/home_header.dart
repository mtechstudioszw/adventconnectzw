import 'dart:ui' show ImageFilter, lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show FloatingHeaderSnapConfiguration;
import 'package:flutter/services.dart' show SystemUiOverlayStyle;

import '../../services/sabbath_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';
import '../cached_image.dart';
import '../motion/pressable.dart';

/// Set false if the frosted header ever janks on low-end hardware.
///
/// True device-tier detection needs a plugin we don't ship, so the blur is
/// gated on two cheap proxies instead: it only composites once the header is
/// actually collapsing (at rest it costs nothing), and it turns itself off
/// when the OS "remove animations" flag is set.
const bool kHomeHeaderBlur = true;

/// What the header's status line is currently saying.
enum SabbathPhase { inSabbath, approaching, ordinary }

/// Sabbath state resolved once per build, so the header isn't recomputing
/// a NOAA sunset equation inside three different widgets.
@immutable
class SabbathStatus {
  const SabbathStatus({
    required this.phase,
    this.until,
    this.sundown,
  });

  final SabbathPhase phase;

  /// Time remaining until the phase flips (Sabbath starts, or ends).
  final Duration? until;

  /// The actual sundown instant, for showing a real clock time.
  final DateTime? sundown;

  bool get isSabbath => phase == SabbathPhase.inSabbath;

  /// Resolves the current phase.
  ///
  /// The celebration ("Sabata yakanaka") always shows — being inside the
  /// Sabbath is the app acknowledging the day, not a widget. The COUNTDOWN
  /// stays gated on the user's Settings opt-in, because that genuinely is
  /// the countdown feature they may have switched off.
  factory SabbathStatus.resolve() {
    final now = DateTime.now().toUtc();
    final end = SabbathService.currentSabbathEnd();
    if (end != null) {
      return SabbathStatus(
        phase: SabbathPhase.inSabbath,
        until: end.difference(now),
        sundown: end,
      );
    }
    if (SabbathService.isEnabled()) {
      final start = SabbathService.nextSabbathStart();
      if (start != null && !start.difference(now).isNegative) {
        return SabbathStatus(
          phase: SabbathPhase.approaching,
          until: start.difference(now),
          sundown: start,
        );
      }
    }
    return const SabbathStatus(phase: SabbathPhase.ordinary);
  }
}

/// Home's collapsing "sanctuary" header.
///
/// Everything animates as a pure function of [shrinkOffset] rather than
/// flipping at a threshold, so the header tracks the finger and reverses
/// exactly when you scroll back up.
///
/// On Sabbath (Friday sundown → Saturday sundown) the whole bar adopts a
/// warm sundown gradient and the greeting becomes "Sabata yakanaka". That is
/// the ONE gold moment on this screen — see CLAUDE.md's one-highlight rule.
class HomeHeaderDelegate extends SliverPersistentHeaderDelegate {
  HomeHeaderDelegate({
    required this.topInset,
    required this.greeting,
    required this.firstName,
    required this.initials,
    required this.photoUrl,
    required this.unreadNotifications,
    required this.sabbath,
    required this.onAvatarTap,
    required this.onSearchTap,
    required this.onBellTap,
    this.branded = false,
    this.snapConfiguration,
  });

  /// Scrolled far enough that the greeting is no longer the point.
  ///
  /// The header then becomes a compact branded bar — "Advent Connect ZW"
  /// plus search and notifications — the way Facebook's does. "Hello
  /// Tanatswa" is a greeting; it only makes sense on arrival, and it read
  /// as clutter for the rest of the feed.
  ///
  /// The flip is driven by scroll OFFSET from the screen, not by
  /// [shrinkOffset], because a floating header re-enters fully expanded:
  /// shrinkOffset is 0 again the moment it comes back, and can't tell
  /// "at the top" from "returning at post 40".
  final bool branded;

  final double topInset;
  final String greeting;
  final String firstName;
  final String initials;
  final String? photoUrl;
  final int unreadNotifications;
  final SabbathStatus sabbath;
  final VoidCallback onAvatarTap;
  final VoidCallback onSearchTap;
  final VoidCallback onBellTap;

  /// Snap-back animation for the floating header, so a small scroll-up
  /// settles it fully open or fully away instead of leaving it half in.
  /// Needs a TickerProvider, so the screen supplies it.
  @override
  final FloatingHeaderSnapConfiguration? snapConfiguration;

  // Body heights excluding the status-bar inset. Expanded carries the
  // greeting + status line; collapsed keeps the member's name.
  //
  // 108 → 96: the status line was boxed at 32dp for a row that is only ~17dp
  // tall (13dp icon, 11pt caption), so a dozen dead pixels sat between the
  // date and whatever came next. That was the gap under the date.
  static const double _expandedBody = 96;
  static const double _collapsedBody = 56;

  /// Height of the status ("Sabata in 2d…" / date) row when fully expanded.
  static const double _statusBody = 20;

  // Branded, the bar is a fixed compact height — there is no greeting left
  // to collapse. Safe to change the extents on the fly because `branded`
  // only flips well past the header's own range, by which point the header
  // is entirely off-screen and nobody can see it resize.
  @override
  double get maxExtent =>
      topInset + (branded ? _collapsedBody : _expandedBody);

  @override
  double get minExtent => topInset + _collapsedBody;

  @override
  bool shouldRebuild(covariant HomeHeaderDelegate old) =>
      old.branded != branded ||
      old.topInset != topInset ||
      old.greeting != greeting ||
      old.firstName != firstName ||
      old.initials != initials ||
      old.photoUrl != photoUrl ||
      old.unreadNotifications != unreadNotifications ||
      old.sabbath.phase != sabbath.phase ||
      old.sabbath.until != sabbath.until;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    final range = maxExtent - minExtent;
    final t = range <= 0 ? 0.0 : (shrinkOffset / range).clamp(0.0, 1.0);
    final palette = context.palette;
    final isSabbath = sabbath.isSabbath;

    // Sabbath sundown gradient, blended from two palette colours so we stay
    // inside the approved scheme rather than inventing a warm hue.
    final sundownEnd = Color.lerp(
      AppColors.darkNavy,
      AppColors.goldAccent,
      0.38,
    )!;
    final onHeader = isSabbath ? AppColors.white : palette.text;
    final onHeaderMuted = isSabbath
        ? AppColors.white.withValues(alpha: 0.78)
        : palette.textMuted;

    // Heights add up to exactly the current body height (4px slack when
    // expanded) so the header can never overflow mid-scroll. Branded, the
    // bar is already at its collapsed size, so nothing is animating and
    // t is pinned at 1.
    final tt = branded ? 1.0 : t;
    final rowHeight = lerpDouble(48, 40, tt)!;
    final gap = branded ? 0.0 : (1 - tt) * AppSpace.xs;
    final statusHeight = branded ? 0.0 : (1 - tt) * _statusBody;
    final bottomPad = lerpDouble(AppSpace.md, AppSpace.sm, tt)!;

    Widget header = Stack(
      fit: StackFit.expand,
      children: [
        _Background(
          t: tt,
          isSabbath: isSabbath,
          sundownEnd: sundownEnd,
          palette: palette,
        ),
        SafeArea(
          bottom: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpace.lg,
              AppSpace.sm,
              AppSpace.md,
              bottomPad,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: rowHeight,
                  child: Row(
                    children: [
                      // The avatar is part of the greeting, not the brand —
                      // it goes with it. Profile is one tap away on the nav.
                      if (!branded) ...[
                        _Avatar(
                          size: lerpDouble(44, 34, tt)!,
                          initials: initials,
                          photoUrl: photoUrl,
                          highlight: isSabbath,
                          onTap: onAvatarTap,
                        ),
                        const SizedBox(width: AppSpace.md),
                      ],
                      Expanded(
                        child: branded
                            ? _BrandTitle(onHeader: onHeader)
                            : _TitleBlock(
                                t: tt,
                                greeting: greeting,
                                firstName: firstName,
                                onHeader: onHeader,
                                onHeaderMuted: onHeaderMuted,
                              ),
                      ),
                      _HeaderIcon(
                        icon: Icons.search_rounded,
                        onTap: onSearchTap,
                        isSabbath: isSabbath,
                        tooltip: 'Search',
                      ),
                      const SizedBox(width: AppSpace.sm),
                      _HeaderIcon(
                        icon: Icons.notifications_none_rounded,
                        onTap: onBellTap,
                        isSabbath: isSabbath,
                        badge: unreadNotifications,
                        tooltip: 'Notifications',
                      ),
                    ],
                  ),
                ),
                SizedBox(height: gap),
                SizedBox(
                  height: statusHeight,
                  child: ClipRect(
                    child: OverflowBox(
                      alignment: Alignment.topLeft,
                      minHeight: 0,
                      maxHeight: _statusBody,
                      child: Opacity(
                        opacity: (1 - t * 1.8).clamp(0.0, 1.0),
                        child: _StatusLine(
                          sabbath: sabbath,
                          color: onHeaderMuted,
                          accent: isSabbath
                              ? AppColors.goldAccent
                              : AppColors.primaryBlue,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );

    // Status-bar icons must flip to light over the Sabbath gradient.
    final dark = Theme.of(context).brightness == Brightness.dark;
    final lightIcons = isSabbath || dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness:
            lightIcons ? Brightness.light : Brightness.dark,
        statusBarBrightness: lightIcons ? Brightness.dark : Brightness.light,
      ),
      child: header,
    );
  }
}

class _Background extends StatelessWidget {
  const _Background({
    required this.t,
    required this.isSabbath,
    required this.sundownEnd,
    required this.palette,
  });

  final double t;
  final bool isSabbath;
  final Color sundownEnd;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final blurring = kHomeHeaderBlur && t > 0.05 && AppMotion.enabled(context);

    Widget surface = DecoratedBox(
      decoration: BoxDecoration(
        color: isSabbath ? null : palette.scaffoldBg.withValues(alpha: 0.86),
        gradient: isSabbath
            ? LinearGradient(
                colors: [AppColors.darkNavy, sundownEnd],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
      ),
    );

    if (blurring) {
      surface = BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18 * t, sigmaY: 18 * t),
        child: surface,
      );
    }

    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          surface,
          // Soft top-left bloom — reads as depth without adding a colour.
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-0.7, -0.9),
                  radius: 1.1,
                  colors: [
                    AppColors.white.withValues(alpha: isSabbath ? 0.12 : 0.06),
                    AppColors.white.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          // Hairline that fades in only once the bar is fully collapsed, so
          // the content below reads as scrolling *under* the header.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Opacity(
              opacity: ((t - 0.7) / 0.3).clamp(0.0, 1.0),
              child: Container(height: 1, color: palette.divider),
            ),
          ),
        ],
      ),
    );
  }
}

/// The member's name is the constant; only the greeting eyebrow above it
/// comes and goes.
///
/// This used to crossfade the name out and an "Advent Connect" wordmark in as
/// you scrolled. That was wrong twice over: it took the member's own name off
/// their own home screen the moment they touched it, and it spent the header
/// telling people which app they had just opened. The name now stays put and
/// simply settles down a type size as the eyebrow collapses.
/// The app's own name, shown once the greeting has scrolled away.
///
/// Gets the gold full stop the Watch header uses, so the two branded bars
/// in the app read as the same wordmark rather than two different ideas.
class _BrandTitle extends StatelessWidget {
  const _BrandTitle({required this.onHeader});

  final Color onHeader;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              'Advent Connect ZW',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.titleLarge.copyWith(
                color: onHeader,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
              ),
            ),
          ),
          Text(
            '.',
            style: AppTextStyles.titleLarge.copyWith(
              color: AppColors.goldAccent,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _TitleBlock extends StatelessWidget {
  const _TitleBlock({
    required this.t,
    required this.greeting,
    required this.firstName,
    required this.onHeader,
    required this.onHeaderMuted,
  });

  final double t;
  final String greeting;
  final String firstName;
  final Color onHeader;
  final Color onHeaderMuted;

  @override
  Widget build(BuildContext context) {
    // Greeting fades over the first ~55% of the collapse, then its row
    // collapses to zero height so the name rises to fill the bar rather than
    // leaving a hole where the eyebrow was.
    final eyebrowOpacity = (1 - t * 1.8).clamp(0.0, 1.0);
    final eyebrowExtent = (1 - t * 1.5).clamp(0.0, 1.0);

    return ClipRect(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.topLeft,
            heightFactor: eyebrowExtent,
            child: Opacity(
              opacity: eyebrowOpacity,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  greeting.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.labelSmall.copyWith(
                    color: onHeaderMuted,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.6,
                  ),
                ),
              ),
            ),
          ),
          Text(
            firstName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.headlineMedium.copyWith(
              color: onHeader,
              fontWeight: FontWeight.w700,
              height: 1.1,
              // 20pt expanded → 17pt pinned. Tracks the finger like the rest
              // of the header instead of snapping at a threshold.
              fontSize: lerpDouble(20, 17, t),
            ),
          ),
        ],
      ),
    );
  }
}

/// The live line under the greeting. Always populated: Sabbath celebration,
/// then the opt-in countdown, then today's date as the resting state.
class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.sabbath,
    required this.color,
    required this.accent,
  });

  final SabbathStatus sabbath;
  final Color color;
  final Color accent;

  static const _weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  static String _clock(DateTime utc) {
    final local = utc.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  static String _remaining(Duration d) {
    if (d.inDays >= 1) return '${d.inDays}d ${d.inHours.remainder(24)}h';
    if (d.inHours >= 1) return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
    return '${d.inMinutes}m';
  }

  @override
  Widget build(BuildContext context) {
    final (IconData icon, String text) = switch (sabbath.phase) {
      SabbathPhase.inSabbath => (
          Icons.auto_awesome_rounded,
          sabbath.sundown == null
              ? 'Sabata yakanaka'
              : 'Sabata yakanaka · ends ${_clock(sabbath.sundown!)}',
        ),
      SabbathPhase.approaching => (
          Icons.brightness_3_rounded,
          sabbath.sundown == null
              ? 'Sabata soon'
              : 'Sabata in ${_remaining(sabbath.until!)}'
                  ' · sundown ${_clock(sabbath.sundown!)}',
        ),
      SabbathPhase.ordinary => (
          Icons.calendar_today_rounded,
          () {
            final now = DateTime.now();
            return '${_weekdays[now.weekday - 1]}, '
                '${now.day} ${_months[now.month - 1]}';
          }(),
        ),
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: accent),
        const SizedBox(width: AppSpace.xs + 2),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.caption.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.size,
    required this.initials,
    required this.photoUrl,
    required this.highlight,
    required this.onTap,
  });

  final double size;
  final String initials;
  final String? photoUrl;
  final bool highlight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final url = photoUrl;
    final fallback = Text(
      initials,
      style: AppTextStyles.titleMedium.copyWith(
        color: AppColors.white,
        fontWeight: FontWeight.w700,
        fontSize: size * 0.36,
      ),
    );
    return Semantics(
      button: true,
      label: 'Your profile',
      child: Pressable(
        onTap: onTap,
        pressedScale: 0.92,
        child: Container(
          width: size,
          height: size,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            // A gold ring on Sabbath, otherwise nothing — the avatar sits on
            // the flat scaffold and doesn't need a permanent ring.
            border: highlight
                ? Border.all(color: AppColors.goldAccent, width: 1.6)
                : null,
          ),
          child: Container(
            clipBehavior: Clip.antiAlias,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              gradient: AppColors.primaryGradient,
              shape: BoxShape.circle,
            ),
            child: url == null || url.isEmpty
                ? fallback
                : CachedImage(
                    url,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Center(child: fallback),
                  ),
          ),
        ),
      ),
    );
  }
}

class _HeaderIcon extends StatelessWidget {
  const _HeaderIcon({
    required this.icon,
    required this.onTap,
    required this.isSabbath,
    required this.tooltip,
    this.badge = 0,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool isSabbath;
  final String tooltip;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fg = isSabbath ? AppColors.white : palette.text;

    // A raised control rather than a flat grey disc. The old #E4E9F2 blob sat
    // *into* the background and read as a placeholder; a card-coloured face
    // with a hairline edge, a top sheen and a soft drop shadow reads as
    // something you can press. On Sabbath it becomes frosted white so it
    // still separates from the sundown gradient.
    final face = isSabbath
        ? AppColors.white.withValues(alpha: 0.18)
        : (dark ? palette.cardMuted : palette.card);
    final edge = isSabbath
        ? AppColors.white.withValues(alpha: 0.30)
        : (dark ? AppColors.white.withValues(alpha: 0.10) : palette.divider);

    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: badge > 0 ? '$tooltip, $badge unread' : tooltip,
        child: Pressable(
          onTap: onTap,
          pressedScale: 0.88,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: edge),
                  // Sheen is blended INTO the face colour rather than layered
                  // as a separate translucent gradient — BoxDecoration paints
                  // `gradient` as a shader and ignores `color` entirely when
                  // both are set, which would have left these discs white.
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color.alphaBlend(
                        AppColors.white.withValues(alpha: dark ? 0.06 : 0.5),
                        face,
                      ),
                      face,
                    ],
                  ),
                  boxShadow: isSabbath ? null : AppShadows.card(context),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: fg, size: 20),
              ),
              if (badge > 0)
                Positioned(
                  top: -2,
                  right: -2,
                  child: Container(
                    constraints: const BoxConstraints(
                      minWidth: 17,
                      minHeight: 17,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: AppColors.red,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(
                        color: isSabbath
                            ? AppColors.darkNavy
                            : context.palette.scaffoldBg,
                        width: 1.5,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      badge > 99 ? '99+' : '$badge',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: AppColors.white,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        height: 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
