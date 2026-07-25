import 'package:flutter/material.dart';

import '../../../../models/quiz_round.dart';
import '../../../../theme/app_motion.dart';
import '../../../../theme/app_text_styles.dart';
import '../arena_theme.dart';

/// Level + XP progress.
///
/// Two jobs: in the lobby it shows where you stand; on the results screen
/// it *fills* from the XP you had to the XP you just earned, which is the
/// moment that makes a round feel like it counted for something. Pass
/// [fromXp] to animate, leave it null for the static form.
class XpBar extends StatelessWidget {
  const XpBar({
    super.key,
    required this.xp,
    this.fromXp,
    this.showRank = true,
    this.compact = false,
  });

  final int xp;

  /// Animate the bar from this XP up to [xp].
  final int? fromXp;
  final bool showRank;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final start = (fromXp ?? xp).toDouble();
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: start, end: xp.toDouble()),
      duration: AppMotion.maybe(
        context,
        fromXp == null ? Duration.zero : const Duration(milliseconds: 1100),
      ),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) {
        final current = value.round();
        final level = QuizScoring.levelForXp(current);
        final progress = QuizScoring.levelProgress(current);
        final toNext = QuizScoring.xpToNextLevel(current);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _LevelBadge(level: level, compact: compact),
                const SizedBox(width: 10),
                if (showRank)
                  Expanded(
                    child: Text(
                      QuizScoring.rankForLevel(level),
                      style: AppTextStyles.titleSmall.copyWith(
                        color: ArenaTheme.textOnNavy,
                        fontWeight: FontWeight.w800,
                        fontSize: compact ? 14 : 16,
                      ),
                    ),
                  )
                else
                  const Spacer(),
                Text(
                  '$toNext XP to go',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: ArenaTheme.textFaintOnNavy,
                    fontSize: compact ? 11 : 12,
                  ),
                ),
              ],
            ),
            SizedBox(height: compact ? 7 : 9),
            ClipRRect(
              borderRadius: BorderRadius.circular(ArenaTheme.radiusPill),
              child: Stack(
                children: [
                  Container(
                    height: compact ? 6 : 8,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius:
                          BorderRadius.circular(ArenaTheme.radiusPill),
                    ),
                  ),
                  FractionallySizedBox(
                    widthFactor: progress.clamp(0.0, 1.0),
                    child: Container(
                      height: compact ? 6 : 8,
                      decoration: BoxDecoration(
                        gradient: ArenaTheme.goldGradient,
                        borderRadius:
                            BorderRadius.circular(ArenaTheme.radiusPill),
                        boxShadow:
                            ArenaTheme.glow(ArenaTheme.gold, strength: 0.4),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _LevelBadge extends StatelessWidget {
  const _LevelBadge({required this.level, required this.compact});

  final int level;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 28.0 : 34.0;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: ArenaTheme.goldGradient,
        shape: BoxShape.circle,
        boxShadow: ArenaTheme.glow(ArenaTheme.gold, strength: 0.6),
      ),
      child: Text(
        '$level',
        style: AppTextStyles.labelMedium.copyWith(
          color: ArenaTheme.canvasTop,
          fontWeight: FontWeight.w800,
          fontSize: compact ? 12 : 14,
        ),
      ),
    );
  }
}
