import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../../screens/onboarding/widgets/film_scenes.dart'
    show AmbientPainter, byBrightness;
import '../../theme/app_palette.dart';
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
    pageBuilder: (context, animation, _) => _CreateScreen(animation: animation),
  );
}

@immutable
class _Option {
  const _Option(this.kind, this.icon, this.title, this.subtitle, this.lands);
  final CreateKind kind;
  final IconData icon;
  final String title;
  final String subtitle;

  /// Where the thing ends up once it's made — the studio's "output" label.
  final String lands;
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

  /// ## A studio, not a menu (28 Oct 2026)
  ///
  /// The last version was a ranked list: two cards and five rows. Correct
  /// hierarchy, but it read as a settings page — "generic", in the
  /// founder's word. A studio shows you the FORMATS you can make and what
  /// each one turns into, so the redesign is built around that:
  ///
  /// - **Formats** — Post and Story, each with a small live-drawn preview of
  ///   what it becomes (a feed card, a 9:16 frame). Nobody has to read the
  ///   label to know which is which.
  /// - **Tools** — the five occasional ones, as a two-across grid of tool
  ///   cards, each stamped with where it lands (Events, Marketplace…).
  ///   The grid falls back to one column at large text sizes or on narrow
  ///   phones; the long labels ("Reviewed before it goes live") must never
  ///   truncate or overflow, which is why the old version used rows.
  ///
  /// Still palette-only: blue carries the hierarchy, the screen's single
  /// gold moment stays on the overline.
  static const _post = _Option(
    CreateKind.post,
    Icons.edit_note_rounded,
    'Post',
    'Words and photos',
    'Home feed',
  );

  static const _story = _Option(
    CreateKind.story,
    Icons.auto_awesome_outlined,
    'Story',
    'Gone in 24 hours',
    'Stories',
  );

  static const _tools = <_Option>[
    _Option(
      CreateKind.event,
      Icons.event_outlined,
      'Event',
      'Invite people along',
      'Events',
    ),
    _Option(
      CreateKind.prayer,
      Icons.volunteer_activism_outlined,
      'Prayer request',
      'Ask for prayer',
      'Prayer',
    ),
    // REMOVED 23 Aug 2026 — "Church notice / Tell your local church".
    //
    // It promised something the schema cannot deliver: `notices` has no
    // church_id column, so a "church notice" was never attached to a church
    // at all, and `notices_select_all` shows every notice to every
    // authenticated member. There was also no admin gate on either side —
    // any active member could publish what reads as official church
    // communication, to everybody.
    //
    // Nobody ever did: the table holds 0 rows from 0 posters since launch.
    // So this removes a live permissions hole and a misleading label at
    // zero cost to anyone.
    //
    // The route, screen, model and service are deliberately LEFT IN PLACE
    // (post_notice / PostNoticeScreen / NoticeService). Nothing links to
    // them now, so they are unreachable, and that is the cheap half to undo
    // if the feature is built properly later — the expensive half is the
    // migration that gives notices a church_id and an
    // is_approved_church_admin() policy.
    _Option(
      CreateKind.news,
      Icons.newspaper_outlined,
      'Advent News',
      'Reviewed before it goes live',
      'News',
    ),
    _Option(
      CreateKind.product,
      Icons.storefront_outlined,
      'Sell something',
      'List on the marketplace',
      'Marketplace',
    ),
    _Option(
      CreateKind.job,
      Icons.work_outline_rounded,
      'Job opening',
      'Post an opportunity',
      'Jobs',
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
                            // White in LIGHT mode, on the founder's call
                            // (17 Aug 2026) — and still a gradient rather
                            // than one flat fill, because pure #FFFFFF edge
                            // to edge is what made the navy version read as
                            // a dead slab. The fault was the flatness, not
                            // the hue.
                            //
                            // Dark mode keeps that intent instead of the
                            // literal colour: a white sheet under
                            // palette-aware dark cards was the whole of the
                            // "create sheet is white in dark mode" report
                            // (founder, 17 Aug). Same shape — lifted at the
                            // top, falling to the app's own floor — so the
                            // sheet still has a light source.
                            byBrightness(
                              context,
                              light: AppColors.white.withValues(
                                alpha: 0.97 * t,
                              ),
                              dark: context.palette.cardMuted.withValues(
                                alpha: 0.97 * t,
                              ),
                            ),
                            byBrightness(
                              context,
                              light: AppColors.lightGrey.withValues(
                                alpha: 0.99 * t,
                              ),
                              dark: context.palette.scaffoldBg.withValues(
                                alpha: 0.99 * t,
                              ),
                            ),
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
                              dark:
                                  Theme.of(context).brightness ==
                                  Brightness.dark,
                              quiet: true,
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
                child: LayoutBuilder(
                  builder: (context, box) {
                    // Two-across only while it can't overflow: a narrow
                    // phone or a large system font gets one column.
                    final scale =
                        MediaQuery.textScalerOf(context).scale(14) / 14;
                    final roomy = box.maxWidth >= 340 && scale <= 1.3;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Opacity(
                          opacity: t,
                          child: Transform.translate(
                            offset: Offset(0, -16 * (1 - t)),
                            child: _Header(
                              onClose: () => Navigator.of(context).pop(),
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
                                _SectionLabel(
                                  'FORMATS',
                                  t: animate ? _tileT(0) : 1.0,
                                ),
                                const SizedBox(height: AppSpace.md),
                                _pair(
                                  roomy: roomy,
                                  flex: const [3, 2],
                                  children: [
                                    _FormatCard(
                                      option: _post,
                                      t: animate ? _tileT(0) : 1.0,
                                      preview: const _FeedPreview(),
                                    ),
                                    _FormatCard(
                                      option: _story,
                                      t: animate ? _tileT(1) : 1.0,
                                      preview: _StoryPreview(
                                        progress: _ambient,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: AppSpace.xl),
                                _SectionLabel(
                                  'TOOLS',
                                  t: animate ? _tileT(2) : 1.0,
                                ),
                                const SizedBox(height: AppSpace.md),
                                for (var i = 0; i < _tools.length; i += 2)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      bottom: AppSpace.md,
                                    ),
                                    child: _pair(
                                      roomy: roomy,
                                      flex: const [1, 1],
                                      children: [
                                        for (
                                          var j = i;
                                          j < i + 2 && j < _tools.length;
                                          j++
                                        )
                                          _ToolCard(
                                            option: _tools[j],
                                            t: animate ? _tileT(j + 2) : 1.0,
                                            // The odd one out spans the row
                                            // and lies flat instead.
                                            wide:
                                                !roomy ||
                                                (j == i &&
                                                    j == _tools.length - 1),
                                          ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Side by side at equal height when [roomy], else stacked.
  Widget _pair({
    required bool roomy,
    required List<int> flex,
    required List<Widget> children,
  }) {
    if (children.length == 1) return children.first;
    if (!roomy) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpace.md),
            children[i],
          ],
        ],
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: AppSpace.md),
            Expanded(flex: flex[i], child: children[i]),
          ],
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.xl,
        AppSpace.lg,
        AppSpace.lg,
        AppSpace.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'CREATE',
                  style: AppTextStyles.labelSmall.copyWith(
                    // The screen's one gold moment, in the same slot the
                    // Bible switcher uses it.
                    color: AppColors.goldAccent,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.8,
                  ),
                ),
                const SizedBox(height: AppSpace.xs),
                Text(
                  'Your studio',
                  style: AppTextStyles.displayMedium.copyWith(
                    color: context.palette.text,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: AppSpace.xs),
                Text(
                  'Pick a format or a tool to start.',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: context.palette.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpace.md),
          _CloseButton(onTap: onClose),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label, {required this.t});

  final String label;
  final double t;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: t.clamp(0.0, 1.0),
      child: Row(
        children: [
          Text(
            label,
            style: AppTextStyles.labelSmall.copyWith(
              color: context.palette.textMuted,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
              fontSize: 10.5,
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(child: Container(height: 1, color: context.palette.divider)),
        ],
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

/// The tappable card every option sits on — one surface recipe so formats
/// and tools differ by content, not by chrome.
class _StudioSurface extends StatelessWidget {
  const _StudioSurface({
    required this.option,
    required this.t,
    required this.padding,
    required this.child,
    this.pressedScale = 0.96,
  });

  final _Option option;
  final double t;
  final EdgeInsets padding;
  final double pressedScale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return _Enter(
      t: t,
      child: Semantics(
        button: true,
        label: '${option.title}. ${option.subtitle}',
        excludeSemantics: true,
        child: Pressable(
          haptics: true,
          pressedScale: pressedScale,
          onTap: () {
            HapticFeedback.selectionClick();
            Navigator.of(context).pop(option.kind);
          },
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: context.palette.card,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: context.palette.divider),
              boxShadow: AppShadows.card(context),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// "→ Marketplace" — where the thing you make ends up.
class _LandsTag extends StatelessWidget {
  const _LandsTag(this.lands);

  final String lands;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: context.palette.chipBg,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.north_east_rounded,
            size: 11,
            color: context.palette.brandBlue,
          ),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              lands,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.caption.copyWith(
                color: context.palette.brandBlue,
                fontWeight: FontWeight.w700,
                fontSize: 10.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GradientChip extends StatelessWidget {
  const _GradientChip(this.icon, {this.size = 40});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(AppRadius.button),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryBlue.withValues(alpha: 0.30),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: size * 0.5, color: AppColors.white),
    );
  }
}

/// Post and Story: a preview of what you'll make, then its name.
class _FormatCard extends StatelessWidget {
  const _FormatCard({
    required this.option,
    required this.t,
    required this.preview,
  });

  final _Option option;
  final double t;
  final Widget preview;

  @override
  Widget build(BuildContext context) {
    return _StudioSurface(
      option: option,
      t: t,
      pressedScale: 0.95,
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // The "canvas": a stage the preview sits on, like an editor's
          // artboard.
          Container(
            height: 112,
            decoration: BoxDecoration(
              color: context.palette.scaffoldBg,
              borderRadius: BorderRadius.circular(AppRadius.card - 2),
            ),
            alignment: Alignment.center,
            child: ExcludeSemantics(child: preview),
          ),
          const SizedBox(height: AppSpace.md),
          Row(
            children: [
              _GradientChip(option.icon, size: 36),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Text(
                  option.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.titleMedium.copyWith(
                    color: context.palette.text,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          Text(
            option.subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.caption.copyWith(
              color: context.palette.textMuted,
              height: 1.3,
            ),
          ),
          const Spacer(),
          const SizedBox(height: AppSpace.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: _LandsTag(option.lands),
          ),
        ],
      ),
    );
  }
}

/// A feed card in miniature: author, photo, a few lines of text.
class _FeedPreview extends StatelessWidget {
  const _FeedPreview();

  @override
  Widget build(BuildContext context) {
    final line = context.palette.divider;
    Widget bar(double w) => Container(
      width: w,
      height: 5,
      decoration: BoxDecoration(
        color: line,
        borderRadius: BorderRadius.circular(3),
      ),
    );
    return Container(
      width: 132,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: BorderRadius.circular(10),
        boxShadow: AppShadows.card(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withValues(alpha: 0.28),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              bar(44),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            height: 44,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.primaryBlue.withValues(alpha: 0.22),
                  AppColors.primaryBlue.withValues(alpha: 0.08),
                ],
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.image_outlined,
              size: 18,
              color: context.palette.brandBlue.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 6),
          bar(96),
          const SizedBox(height: 4),
          bar(64),
        ],
      ),
    );
  }
}

/// A 9:16 story frame whose first segment fills on the ambient loop —
/// the one moving part, so the studio feels live. Still when motion is
/// off (the loop then sits at 0, so the bar shows a fixed third).
class _StoryPreview extends StatelessWidget {
  const _StoryPreview({required this.progress});

  final Animation<double> progress;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 96,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryBlue.withValues(alpha: 0.28),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedBuilder(
            animation: progress,
            builder: (context, _) {
              // Seven seconds to fill, matching nothing in particular but
              // calm; the 14s loop runs it twice.
              final v = progress.value == 0 ? 0.33 : (progress.value * 2) % 1.0;
              return Row(
                children: [
                  Expanded(child: _Segment(fill: v)),
                  const SizedBox(width: 2),
                  const Expanded(child: _Segment(fill: 0)),
                ],
              );
            },
          ),
          const SizedBox(height: 4),
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: AppColors.white.withValues(alpha: 0.85),
              shape: BoxShape.circle,
            ),
          ),
          const Spacer(),
          Center(
            child: Text(
              'Aa',
              textScaler: TextScaler.noScaling,
              style: AppTextStyles.titleMedium.copyWith(
                color: AppColors.white,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({required this.fill});

  final double fill;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: SizedBox(
        height: 2.5,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: AppColors.white.withValues(alpha: 0.35)),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: fill.clamp(0.0, 1.0),
              child: const ColoredBox(color: AppColors.white),
            ),
          ],
        ),
      ),
    );
  }
}

/// The occasional five. Tall when two share a row; flat when one has the
/// row to itself, so it doesn't stand there half-empty.
class _ToolCard extends StatelessWidget {
  const _ToolCard({required this.option, required this.t, this.wide = false});

  final _Option option;
  final double t;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        // Tinted, not filled: the other half of the hierarchy — same icon
        // language as the formats, visibly less weight.
        color: AppColors.primaryBlue.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.button),
      ),
      alignment: Alignment.center,
      child: Icon(option.icon, size: 21, color: context.palette.brandBlue),
    );
    final title = Text(
      option.title,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: AppTextStyles.bodyMedium.copyWith(
        color: context.palette.text,
        fontWeight: FontWeight.w700,
      ),
    );
    final subtitle = Text(
      option.subtitle,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: AppTextStyles.caption.copyWith(
        color: context.palette.textMuted,
        height: 1.3,
      ),
    );

    if (wide) {
      return _StudioSurface(
        option: option,
        t: t,
        padding: const EdgeInsets.all(AppSpace.md),
        child: Row(
          children: [
            chip,
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  title,
                  const SizedBox(height: 1),
                  subtitle,
                  const SizedBox(height: AppSpace.sm),
                  _LandsTag(option.lands),
                ],
              ),
            ),
            const SizedBox(width: AppSpace.sm),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: context.palette.textMuted,
            ),
          ],
        ),
      );
    }

    return _StudioSurface(
      option: option,
      t: t,
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          chip,
          const SizedBox(height: AppSpace.md),
          title,
          const SizedBox(height: 2),
          subtitle,
          const Spacer(),
          const SizedBox(height: AppSpace.sm),
          _LandsTag(option.lands),
        ],
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
            color: context.palette.card,
            shape: BoxShape.circle,
            border: Border.all(color: context.palette.divider),
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.close_rounded,
            color: context.palette.text,
            size: 21,
          ),
        ),
      ),
    );
  }
}
