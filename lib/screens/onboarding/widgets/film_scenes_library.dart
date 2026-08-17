import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../../theme/app_palette.dart';
import '../../../theme/app_text_styles.dart';
import 'film_scenes.dart';

/// Later acts of the onboarding film — the three chapters the original
/// cut left out entirely: the offline Library, the feed itself, and the
/// Quiz Arena.
///
/// Same rules as `film_scenes.dart`: every widget is driven by the one
/// master timeline value `t`, owns no controller, and animates only via
/// Transform/Opacity on small subtrees so there is no per-frame layout
/// and nothing needs a blur filter.

/// Opacity-safe read of a curved progress value.
///
/// `seg()` clamps its INPUT to 0..1 but then runs the curve, and the
/// `…Back` curves deliberately overshoot their output past 1.0 — that
/// overshoot is the pop. Feeding it straight to `Opacity` trips
/// `opacity >= 0.0 && opacity <= 1.0` and crashes a debug build. Scale
/// wants the overshoot; opacity never does.
double _op(double v) => v.clamp(0.0, 1.0);

// ---------------------------------------------------------------------------
// Scene 6 — the offline Library
// ---------------------------------------------------------------------------

/// The strongest reason to install the app rather than just open a
/// browser: the whole Bible, Sabbath School, ~995 hymns and EGW, bundled
/// and readable with no signal. The scene makes the point by cutting the
/// connection — the page keeps reading while an "Offline" badge appears.
class SceneLibrary extends StatelessWidget {
  const SceneLibrary({super.key, required this.t});
  final double t;

  static const _tiles = <(String, IconData)>[
    ('Bible', Icons.menu_book_rounded),
    ('Sabbath', Icons.school_rounded),
    ('Hymnal', Icons.queue_music_rounded),
    ('EGW', Icons.auto_stories_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final (a, b) = FilmTimeline.s6;
    final pageIn = seg(t, a, a + 0.028, Curves.easeOutBack);
    final versesIn = seg(t, a + 0.020, a + 0.062, Curves.easeOutCubic);
    // The beat the scene exists for: signal drops, scripture stays.
    final offlineIn = seg(t, a + 0.052, a + 0.074, Curves.easeOutBack);
    final tilesIn = seg(t, a + 0.062, a + 0.098, Curves.easeOutBack);
    final lineIn = seg(t, a + 0.030, a + 0.066, Curves.easeOutCubic);
    final exit = seg(t, b - 0.020, b, Curves.easeInCubic);

    if (pageIn == 0) return const SizedBox.shrink();

    return Opacity(
      opacity: (pageIn * (1 - exit)).clamp(0.0, 1.0),
      child: Transform.translate(
        offset: Offset(0, 64 * (1 - pageIn) - 56 * exit),
        child: Transform.scale(
          scale: (0.95 + 0.05 * pageIn) * (1 - 0.14 * exit),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 268,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                decoration: BoxDecoration(
                  color: context.palette.card,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: byBrightness(
                        context,
                        light: AppColors.darkNavy.withValues(alpha: 0.12),
                        dark: Colors.black.withValues(alpha: 0.46),
                      ),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'JOHN 3',
                          style: AppTextStyles.labelSmall.copyWith(
                            color: context.palette.textMuted,
                            fontSize: 9.5,
                            letterSpacing: 1.3,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const Spacer(),
                        Opacity(
                          opacity: _op(offlineIn),
                          child: Transform.scale(
                            scale: 0.8 + 0.2 * offlineIn,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.successGreen.withValues(
                                  alpha: 0.12,
                                ),
                                borderRadius: BorderRadius.circular(100),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.signal_cellular_off_rounded,
                                    size: 11,
                                    color: AppColors.successGreen,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Offline',
                                    style: AppTextStyles.labelSmall.copyWith(
                                      color: AppColors.successGreen,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Verse lines write themselves in, one after another.
                    for (var i = 0; i < 4; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 7),
                        child: Opacity(
                          opacity: seg(
                            versesIn,
                            i * 0.18,
                            i * 0.18 + 0.40,
                          ).clamp(0.0, 1.0),
                          child: Container(
                            height: 7,
                            width: const [206.0, 224.0, 192.0, 146.0][i] *
                                (0.45 +
                                    0.55 *
                                        seg(
                                          versesIn,
                                          i * 0.18,
                                          i * 0.18 + 0.55,
                                        )),
                            decoration: BoxDecoration(
                              color: ink(context, i == 0 ? 0.30 : 0.16),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              // The four library tiles fan up under the page.
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _tiles.length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Transform.translate(
                        offset: Offset(
                          0,
                          26 *
                              (1 -
                                  seg(
                                    tilesIn,
                                    i * 0.14,
                                    i * 0.14 + 0.60,
                                    Curves.easeOutBack,
                                  )),
                        ),
                        child: Opacity(
                          opacity: seg(
                            tilesIn,
                            i * 0.14,
                            i * 0.14 + 0.50,
                          ).clamp(0.0, 1.0),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              // Library tile pills — these sit on the
                              // scaffold, not on a card, so they use the
                              // card tone to lift off it in both modes.
                              color: context.palette.card,
                              borderRadius: BorderRadius.circular(100),
                              boxShadow: [
                                BoxShadow(
                                  color: byBrightness(
                                    context,
                                    light: AppColors.darkNavy.withValues(
                                      alpha: 0.10,
                                    ),
                                    dark: Colors.black.withValues(alpha: 0.40),
                                  ),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _tiles[i].$2,
                                  size: 16,
                                  color: AppColors.primaryBlue,
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  _tiles[i].$1,
                                  style: AppTextStyles.labelSmall.copyWith(
                                    color: context.palette.text,
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              SceneLine(
                text: 'Scripture that works\nwith no signal',
                enter: lineIn,
                exit: exit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Scene 7 — the feed + stories
// ---------------------------------------------------------------------------

/// The room itself: a story rail whose rings sweep closed, and a post
/// that collects an Amen. Where members actually spend their time — and
/// the original cut never showed it once.
class SceneFeed extends StatelessWidget {
  const SceneFeed({super.key, required this.t});
  final double t;

  @override
  Widget build(BuildContext context) {
    final (a, b) = FilmTimeline.s7;
    final railIn = seg(t, a, a + 0.030, Curves.easeOutBack);
    final cardIn = seg(t, a + 0.022, a + 0.056, Curves.easeOutBack);
    final amenIn = seg(t, a + 0.055, a + 0.078, Curves.easeOutBack);
    final countIn = seg(t, a + 0.070, a + 0.088, Curves.easeOutCubic);
    final lineIn = seg(t, a + 0.036, a + 0.070, Curves.easeOutCubic);
    final exit = seg(t, b - 0.020, b, Curves.easeInCubic);

    if (railIn == 0) return const SizedBox.shrink();

    return Opacity(
      opacity: (railIn * (1 - exit)).clamp(0.0, 1.0),
      child: Transform.translate(
        offset: Offset(0, 62 * (1 - railIn) - 54 * exit),
        child: Transform.scale(
          scale: (0.95 + 0.05 * railIn) * (1 - 0.14 * exit),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Story rail — each ring sweeps closed in turn.
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < 5; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      child: Transform.scale(
                        scale: 0.6 +
                            0.4 *
                                seg(
                                  railIn,
                                  i * 0.12,
                                  i * 0.12 + 0.60,
                                  Curves.easeOutBack,
                                ),
                        child: SizedBox(
                          width: 44,
                          height: 44,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              CustomPaint(
                                size: const Size(44, 44),
                                painter: GoldRingPainter(
                                  sweep: seg(
                                    t,
                                    a + 0.018 + i * 0.010,
                                    a + 0.046 + i * 0.010,
                                    Curves.easeOutCubic,
                                  ),
                                  strokeWidth: 2.4,
                                ),
                              ),
                              Container(
                                width: 33,
                                height: 33,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: AppColors.primaryGradient,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Opacity(
                opacity: _op(cardIn),
                child: Transform.translate(
                  offset: Offset(0, 22 * (1 - cardIn)),
                  child: Container(
                    width: 268,
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                    decoration: BoxDecoration(
                      color: context.palette.card,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: byBrightness(
                            context,
                            light: AppColors.darkNavy.withValues(alpha: 0.12),
                            dark: Colors.black.withValues(alpha: 0.46),
                          ),
                          blurRadius: 22,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 28,
                              height: 28,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: AppColors.primaryGradient,
                              ),
                            ),
                            const SizedBox(width: 9),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 96,
                                  height: 7,
                                  decoration: BoxDecoration(
                                    color: ink(context, 0.28),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Container(
                                  width: 58,
                                  height: 5,
                                  decoration: BoxDecoration(
                                    color: ink(context, 0.14),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        for (final w in const [220.0, 194.0])
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Container(
                              width: w,
                              height: 6,
                              decoration: BoxDecoration(
                                color: ink(context, 0.14),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            // The Amen pill pops, then the count ticks up.
                            Transform.scale(
                              scale: 0.7 + 0.3 * amenIn,
                              child: Opacity(
                                opacity: _op(amenIn),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 11,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryBlue.withValues(
                                      alpha: 0.10,
                                    ),
                                    borderRadius: BorderRadius.circular(100),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.volunteer_activism_rounded,
                                        size: 13,
                                        color: AppColors.primaryBlue,
                                      ),
                                      const SizedBox(width: 5),
                                      Text(
                                        'Amen',
                                        style: AppTextStyles.labelSmall
                                            .copyWith(
                                          color: AppColors.primaryBlue,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Opacity(
                              opacity: _op(countIn),
                              child: Text(
                                '${(12 + 30 * countIn).round()}',
                                style: AppTextStyles.labelSmall.copyWith(
                                  color: context.palette.textMuted,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SceneLine(
                text: 'Your congregation,\nevery day',
                enter: lineIn,
                exit: exit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Scene 8 — the Quiz Arena
// ---------------------------------------------------------------------------

/// Bible quiz with streaks and a leaderboard — the app's most
/// habit-forming screen, and invisible in the original pitch.
class SceneQuiz extends StatelessWidget {
  const SceneQuiz({super.key, required this.t});
  final double t;

  @override
  Widget build(BuildContext context) {
    final (a, b) = FilmTimeline.s8;
    final cardIn = seg(t, a, a + 0.026, Curves.easeOutBack);
    final optionsIn = seg(t, a + 0.020, a + 0.056, Curves.easeOutCubic);
    // The right answer lights green, then the streak flares gold.
    final correctIn = seg(t, a + 0.050, a + 0.068, Curves.easeOutBack);
    final streakIn = seg(t, a + 0.062, a + 0.086, Curves.easeOutBack);
    final lineIn = seg(t, a + 0.032, a + 0.062, Curves.easeOutCubic);
    final exit = seg(t, b - 0.018, b, Curves.easeInCubic);

    if (cardIn == 0) return const SizedBox.shrink();

    return Opacity(
      opacity: (cardIn * (1 - exit)).clamp(0.0, 1.0),
      child: Transform.translate(
        offset: Offset(0, 60 * (1 - cardIn) - 52 * exit),
        child: Transform.scale(
          scale: (0.95 + 0.05 * cardIn) * (1 - 0.14 * exit),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 264,
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                decoration: BoxDecoration(
                  gradient: AppColors.appBarGradient,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      // The quiz card keeps its navy gradient in both
                      // modes (it reads as the arena), but its shadow has
                      // to go deeper to separate from a dark scaffold.
                      color: byBrightness(
                        context,
                        light: AppColors.darkNavy.withValues(alpha: 0.22),
                        dark: Colors.black.withValues(alpha: 0.52),
                      ),
                      blurRadius: 26,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.emoji_events_rounded,
                          size: 15,
                          color: AppColors.goldAccent,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'QUESTION 4 OF 10',
                          style: AppTextStyles.labelSmall.copyWith(
                            color: AppColors.white.withValues(alpha: 0.72),
                            fontSize: 9,
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const Spacer(),
                        Opacity(
                          opacity: _op(streakIn),
                          child: Transform.scale(
                            scale: 0.7 + 0.5 * streakIn,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.local_fire_department_rounded,
                                  size: 14,
                                  color: AppColors.goldAccent,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  '4',
                                  style: AppTextStyles.labelSmall.copyWith(
                                    color: AppColors.goldAccent,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    for (final w in const [198.0, 130.0])
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Container(
                          width: w,
                          height: 7,
                          decoration: BoxDecoration(
                            color: AppColors.white.withValues(alpha: 0.32),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    // Answer chips slide in; the second turns green.
                    for (var i = 0; i < 3; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 7),
                        child: Opacity(
                          opacity: seg(
                            optionsIn,
                            i * 0.16,
                            i * 0.16 + 0.50,
                          ).clamp(0.0, 1.0),
                          child: Transform.translate(
                            offset: Offset(
                              18 *
                                  (1 -
                                      seg(
                                        optionsIn,
                                        i * 0.16,
                                        i * 0.16 + 0.60,
                                        Curves.easeOutCubic,
                                      )),
                              0,
                            ),
                            child: Container(
                              height: 26,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              alignment: Alignment.centerLeft,
                              decoration: BoxDecoration(
                                color: i == 1
                                    ? Color.lerp(
                                        AppColors.white.withValues(
                                          alpha: 0.14,
                                        ),
                                        AppColors.successGreen,
                                        _op(correctIn),
                                      )
                                    : AppColors.white.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(9),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: i == 1 ? 84 : 96,
                                    height: 5,
                                    decoration: BoxDecoration(
                                      color: AppColors.white.withValues(
                                        alpha: 0.55,
                                      ),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                  const Spacer(),
                                  if (i == 1)
                                    Opacity(
                                      opacity: _op(correctIn),
                                      child: const Icon(
                                        Icons.check_rounded,
                                        size: 15,
                                        color: AppColors.white,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SceneLine(
                text: 'Know your Bible\nbetter every week',
                enter: lineIn,
                exit: exit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
