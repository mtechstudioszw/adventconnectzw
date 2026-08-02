import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/church_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_motion.dart';
import '../theme/app_palette.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_tokens.dart';

/// The four faces a member can leave on a church announcement.
///
/// Presentation only — the owner holds the [AnnouncementReactionState] and
/// applies the optimistic update, because the announcements screen fetches
/// every card's reactions in ONE batched call and has to reconcile them in
/// one place.
///
/// Tapping the face you already left clears it, which is what the RPC does
/// server-side too: `set_announcement_reaction` treats a repeat of your
/// current reaction as "un-react". So this bar never needs a separate
/// remove affordance.
class AnnouncementReactionBar extends StatelessWidget {
  const AnnouncementReactionBar({
    super.key,
    required this.state,
    required this.onReact,
  });

  final AnnouncementReactionState state;
  final ValueChanged<AnnouncementReaction> onReact;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    // Wrap, not Row. Four chips, their counts and the tally are all text
    // that grows with the system font, and at 2.5x on a 360dp phone a Row
    // overflowed by 144px — caught by the text-scale sweep in
    // test/announcement_reactions_test.dart. Wrap reflows instead; the
    // tally drops to a second line when the faces fill the first.
    return Wrap(
      spacing: AppSpace.xs,
      runSpacing: AppSpace.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final kind in AnnouncementReaction.values)
          _ReactionChip(
            kind: kind,
            count: state.counts[kind] ?? 0,
            selected: state.mine == kind,
            onTap: () => onReact(kind),
          ),
        // The tally reads as "how the church received this", so it earns a
        // place even before anyone taps — but only once there IS one.
        if (state.total > 0)
          Padding(
            padding: const EdgeInsets.only(left: AppSpace.xs),
            child: Text(
              state.total == 1 ? '1 response' : '${state.total} responses',
              style: AppTextStyles.bodySmall.copyWith(color: palette.textMuted),
            ),
          ),
      ],
    );
  }
}

class _ReactionChip extends StatelessWidget {
  const _ReactionChip({
    required this.kind,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final AnnouncementReaction kind;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final accent = AppColors.primaryBlue;

    return Semantics(
      button: true,
      selected: selected,
      // The chip itself is an emoji and a number, which a screen reader
      // would read as neither. The enum already carries the word.
      label: count == 0 ? kind.label : '${kind.label}, $count',
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        // Transparent rather than deferToChild so the gap inside the chip's
        // padding still counts as a tap — these are small targets.
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: AppMotion.quick,
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.sm,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: 0.12)
                : palette.cardMuted.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(
              color: selected ? accent : Colors.transparent,
              width: 1.2,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // The emoji pops when it becomes yours. Scale only — a curve
              // that overshoots past 1.0 asserts inside Opacity, and this
              // one is meant to overshoot.
              TweenAnimationBuilder<double>(
                key: ValueKey(selected),
                tween: Tween(begin: selected ? 0.7 : 1, end: 1),
                duration: selected ? AppMotion.standard : Duration.zero,
                curve: AppMotion.spring,
                builder: (context, v, child) =>
                    Transform.scale(scale: v, child: child),
                child: Text(kind.emoji, style: const TextStyle(fontSize: 15)),
              ),
              if (count > 0) ...[
                const SizedBox(width: 4),
                Text(
                  '$count',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: selected ? accent : palette.textMuted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
