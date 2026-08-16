import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../../screens/onboarding/widgets/film_scenes.dart' show AmbientPainter;
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';
import '../motion/pressable.dart';

/// Everything a member can put into the app from Home.
enum CreateKind { post, story, event, prayer, news, notice, job, product }

/// Facebook-style "what do you want to share?" chooser, as a full screen.
///
/// The composer row used to go straight to a text post, which quietly hid
/// seven other things a member can create — events, prayer requests, news
/// submissions, notices, jobs and marketplace listings all lived behind
/// separate tabs most people never opened.
///
/// Presented as a blurred full-screen overlay rather than a bottom sheet so
/// it reads as a deliberate moment: Home stays visible but recedes behind the
/// blur, the tiles spring in on a stagger, and the whole thing reverses on
/// the way out. Every animation is driven by the route's own animation, so
/// dismissing plays the entrance backwards instead of cutting.
///
/// Styled to match [TranslationPicker], the Bible version switcher: navy
/// scrim, gold overline, and glass cards rather than opaque white tiles. The
/// white-card version read as a different app's component dropped onto a navy
/// backdrop — light-mode cards carrying dark text over a dark scrim.
///
/// Returns the chosen kind, or null if dismissed. Deliberately presentational
/// — the caller owns navigation, because posts and stories come back with a
/// value the feed needs and the rest are plain route pushes.
Future<CreateKind?> showCreateSheet(BuildContext context) {
  return showGeneralDialog<CreateKind>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close create menu',
    // We paint our own scrim so it can fade in step with the blur.
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 420),
    pageBuilder: (context, animation, _) =>
        _CreateScreen(animation: animation),
  );
}

@immutable
class _Option {
  const _Option(this.kind, this.icon, this.title, this.subtitle);
  final CreateKind kind;
  final IconData icon;
  final String title;
  final String subtitle;
}

class _CreateScreen extends StatefulWidget {
  const _CreateScreen({required this.animation});

  final Animation<double> animation;

  @override
  State<_CreateScreen> createState() => _CreateScreenState();
}

class _CreateScreenState extends State<_CreateScreen>
    with SingleTickerProviderStateMixin {
  /// The same slow ambient drift the splash, onboarding film, auth shell
  /// and maintenance screen run on. Reused rather than reinvented: this
  /// is the app's own background, so Create now reads as part of Advent
  /// Connect instead of a dark rectangle that could belong to anything.
  late final AnimationController _ambient;

  @override
  void initState() {
    super.initState();
    _ambient = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Honour "remove animations": hold the field still rather than
    // spinning a controller nobody can see.
    if (AppMotion.enabled(context)) {
      if (!_ambient.isAnimating) _ambient.repeat();
    } else {
      _ambient
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _ambient.dispose();
    super.dispose();
  }

  Animation<double> get animation => widget.animation;

  /// ## Why this is two lists and not one grid
  ///
  /// It was eight identical glass rectangles, two across, each with the same
  /// blue gradient icon chip. Every option looked exactly as important as
  /// every other one, which is both untrue and the thing that made the
  /// screen read as generated rather than designed: a uniform grid is what
  /// you get when nobody decided what matters.
  ///
  /// Post and Story are what people open this screen to do. The other six
  /// are real but occasional — most members will list a job or submit news
  /// once, if ever. So the two get cards with room to breathe and the six
  /// get quiet rows underneath.
  ///
  /// The hierarchy is carried by WEIGHT, not colour: a filled gradient chip
  /// for primary, a flat outlined glyph for secondary. The palette allows
  /// exactly one gold moment per screen (already spent on the CREATE
  /// overline) and forbids anything outside the scheme, so giving each of
  /// eight options its own accent colour was never available — and would
  /// have been noise rather than hierarchy anyway.
  static const _primary = <_Option>[
    _Option(CreateKind.post, Icons.edit_outlined, 'Post', 'Share an update'),
    _Option(
      CreateKind.story,
      Icons.auto_awesome_outlined,
      'Story',
      'Gone in 24 hours',
    ),
  ];

  static const _secondary = <_Option>[
    _Option(
      CreateKind.event,
      Icons.event_outlined,
      'Event',
      'Invite people along',
    ),
    _Option(
      CreateKind.prayer,
      Icons.volunteer_activism_outlined,
      'Prayer request',
      'Ask for prayer',
    ),
    _Option(
      CreateKind.notice,
      Icons.campaign_outlined,
      'Church notice',
      'Tell your local church',
    ),
    _Option(
      CreateKind.news,
      Icons.newspaper_outlined,
      'Advent News',
      'Reviewed before it goes live',
    ),
    _Option(
      CreateKind.product,
      Icons.storefront_outlined,
      'Sell something',
      'List on the marketplace',
    ),
    _Option(
      CreateKind.job,
      Icons.work_outline_rounded,
      'Job opening',
      'Post an opportunity',
    ),
  ];

  /// Per-tile progress: tile [i] starts [i * 0.05] into the route animation
  /// and takes 55% of it to land. Capped so the last tile isn't still
  /// arriving after the route has settled.
  double _tileT(int i) {
    final start = (i * 0.05).clamp(0.0, 0.40);
    return ((animation.value - start) / 0.55).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final animate = AppMotion.enabled(context);

    // Scaffold, not a bare Stack. A `showGeneralDialog` page has no Material
    // ancestor, so every Text here inherited Flutter's missing-Material error
    // style — black glyphs with a double YELLOW underline — and no amount of
    // palette work could fix it. This is the transparent-Material fix.
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          final t = animate
              ? Curves.easeOutCubic.transform(animation.value.clamp(0.0, 1.0))
              : 1.0;

          return Stack(
            children: [
              // Scrim + blur. Tapping anywhere off the tiles closes.
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(context).pop(),
                  // This used to be one flat ColoredBox of navy at 82%. Over
                  // a blurred feed that is a dead, evenly-lit slab with no
                  // light source and no depth — and below the last row it
                  // became a large rectangle of nothing, which is where the
                  // screen stopped looking designed.
                  //
                  // Three layers now: the blur, a vertical gradient so light
                  // falls from the top the way it does everywhere else in the
                  // app, and the app's own AmbientPainter drifting over it.
                  // The ambient field is what fills the space under the last
                  // row, so the foot of the screen is lit rather than empty.
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 18 * t, sigmaY: 18 * t),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            // Lifted where the title sits, settling deeper at
                            // the foot. One hue throughout — this is a light
                            // source, not a second colour.
                            const Color(0xFF16233F).withValues(alpha: 0.86 * t),
                            AppColors.darkNavy.withValues(alpha: 0.94 * t),
                          ],
                        ),
                      ),
                      child: Opacity(
                        opacity: t,
                        child: AnimatedBuilder(
                          animation: _ambient,
                          builder: (context, _) => CustomPaint(
                            painter: AmbientPainter(
                              loop: _ambient.value,
                              film: 0,
                            ),
                            size: Size.infinite,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Opacity(
                      opacity: t,
                      child: Transform.translate(
                        offset: Offset(0, -16 * (1 - t)),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpace.xl,
                            AppSpace.lg,
                            AppSpace.lg,
                            AppSpace.sm,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'CREATE',
                                      style: AppTextStyles.labelSmall.copyWith(
                                        // The screen's one gold moment, in the
                                        // same slot the Bible switcher uses it.
                                        color: AppColors.goldAccent,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 1.8,
                                      ),
                                    ),
                                    const SizedBox(height: AppSpace.xs),
                                    Text(
                                      'What would you\nlike to share?',
                                      style: AppTextStyles.displayMedium
                                          .copyWith(
                                        color: AppColors.white,
                                        height: 1.15,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: AppSpace.md),
                              _CloseButton(
                                onTap: () => Navigator.of(context).pop(),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpace.lg,
                          AppSpace.md,
                          AppSpace.lg,
                          AppSpace.xl,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // The two everyone actually came for, given the
                            // room to say so.
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (var i = 0; i < _primary.length; i++) ...[
                                  if (i > 0) const SizedBox(width: AppSpace.md),
                                  Expanded(
                                    child: _PrimaryTile(
                                      option: _primary[i],
                                      t: animate ? _tileT(i) : 1.0,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: AppSpace.xl),
                            Opacity(
                              opacity: animate ? _tileT(2) : 1.0,
                              child: Text(
                                'MORE WAYS TO CONTRIBUTE',
                                style: AppTextStyles.labelSmall.copyWith(
                                  color: AppColors.white.withValues(alpha: 0.5),
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.4,
                                  fontSize: 10.5,
                                ),
                              ),
                            ),
                            const SizedBox(height: AppSpace.md),
                            // Rows, not a tighter grid. These labels are long
                            // ("Reviewed before it goes live") and they scale
                            // with the system font; a three-across grid would
                            // either truncate them or overflow at a large text
                            // size. A row gives the text the full width and
                            // cannot run out of it.
                            for (var i = 0; i < _secondary.length; i++)
                              Padding(
                                padding: const EdgeInsets.only(
                                  bottom: AppSpace.sm,
                                ),
                                child: _SecondaryRow(
                                  option: _secondary[i],
                                  t: animate ? _tileT(i + 2) : 1.0,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Shared entrance: springs up and settles rather than simply fading.
class _Enter extends StatelessWidget {
  const _Enter({required this.t, required this.child});

  final double t;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final clamped = t.clamp(0.0, 1.0);
    final eased = Curves.easeOutBack.transform(clamped);
    return Opacity(
      opacity: clamped,
      child: Transform.translate(
        offset: Offset(0, 22 * (1 - clamped)),
        child: Transform.scale(scale: 0.92 + 0.08 * eased, child: child),
      ),
    );
  }
}

/// Post and Story — the two people came here for.
class _PrimaryTile extends StatelessWidget {
  const _PrimaryTile({required this.option, required this.t});

  final _Option option;
  final double t;

  @override
  Widget build(BuildContext context) {
    return _Enter(
      t: t,
      child: Pressable(
        haptics: true,
        pressedScale: 0.94,
        onTap: () {
          HapticFeedback.selectionClick();
          Navigator.of(context).pop(option.kind);
        },
        child: Container(
          padding: const EdgeInsets.all(AppSpace.lg),
          decoration: BoxDecoration(
            // Brighter glass than the rows below — the difference in fill is
            // half of what makes these read as the primary pair.
            color: AppColors.white.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: AppColors.white.withValues(alpha: 0.20),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(AppRadius.button),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryBlue.withValues(alpha: 0.32),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Icon(option.icon, size: 23, color: AppColors.white),
              ),
              const SizedBox(height: AppSpace.lg),
              Text(
                option.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.titleMedium.copyWith(
                  color: AppColors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                option.subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.white.withValues(alpha: 0.68),
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The occasional six — a quiet row each, full width for the label.
class _SecondaryRow extends StatelessWidget {
  const _SecondaryRow({required this.option, required this.t});

  final _Option option;
  final double t;

  @override
  Widget build(BuildContext context) {
    return _Enter(
      t: t,
      child: Pressable(
        haptics: true,
        pressedScale: 0.97,
        onTap: () {
          HapticFeedback.selectionClick();
          Navigator.of(context).pop(option.kind);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.md,
            vertical: AppSpace.md,
          ),
          decoration: BoxDecoration(
            color: AppColors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
              color: AppColors.white.withValues(alpha: 0.11),
            ),
          ),
          child: Row(
            children: [
              // Flat and outlined, not a filled gradient chip. This is the
              // other half of the hierarchy: same icon language, visibly
              // less weight.
              SizedBox(
                width: 34,
                height: 34,
                child: Icon(
                  option.icon,
                  size: 21,
                  color: AppColors.white.withValues(alpha: 0.85),
                ),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      option.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      option.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.white.withValues(alpha: 0.60),
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: AppColors.white.withValues(alpha: 0.35),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Close',
      child: Pressable(
        onTap: onTap,
        pressedScale: 0.88,
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: AppColors.white.withValues(alpha: 0.16),
            shape: BoxShape.circle,
            border: Border.all(
              color: AppColors.white.withValues(alpha: 0.24),
            ),
          ),
          alignment: Alignment.center,
          child: const Icon(
            Icons.close_rounded,
            color: AppColors.white,
            size: 21,
          ),
        ),
      ),
    );
  }
}
