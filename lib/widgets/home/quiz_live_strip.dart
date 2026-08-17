import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/presence_service.dart';
import '../../services/quiz_home_signal.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';
import '../motion/pressable.dart';

/// Live match, surfaced on Home.
///
/// The founder's sharpest point of 17 Aug: live match is the only
/// real-time, person-to-person feature in the whole app, and it sat two
/// taps deep behind a tile in the quiz lobby. That is most of why only
/// ~11 members have ever played one.
///
/// ## It only appears when it is TRUE
///
/// This renders nothing at all when nobody has challenged you and nobody
/// is online. That restraint is the point: the lobby tile used to promise
/// "head to head, same clock" at 3am to an empty arena, so members tapped
/// it, waited out a search, found no one, and concluded the feature was
/// broken. An empty arena is the COMMON case here, not the edge one.
///
/// So there are exactly two states worth a slot on Home:
///   * somebody has challenged you — notification-grade, unmissable;
///   * others are online now — a reason to tap that a static label can
///     never be.
/// Anything else, and Home says nothing.
class QuizLiveStrip extends StatelessWidget {
  const QuizLiveStrip({super.key, this.viewerId});

  /// The signed-in member's id, so they can be filtered out of the online
  /// roster. Passed in rather than read from [AuthService] here for the
  /// same reason `StoriesRail` takes one: reaching into Supabase from a
  /// leaf widget makes it untestable, and this is the exact number that
  /// was wrong.
  final String? viewerId;

  @override
  Widget build(BuildContext context) {
    // Two sources: the cached invite count and the live presence roster.
    return ValueListenableBuilder<int>(
      valueListenable: QuizHomeSignal.invites,
      builder: (context, invites, _) {
        return ValueListenableBuilder<Set<String>>(
          valueListenable: PresenceService.onChange,
          builder: (context, online, _) {
            final waiting = invites > 0;
            // Filter the viewer out by id rather than subtracting one.
            // Subtracting assumed you are always in the roster, but a
            // member who turned OFF "show me as online" never joins it —
            // so for them the count was one short, every time.
            final others = online.where((id) => id != viewerId).length;
            if (!waiting && others < 1) return const SizedBox.shrink();
            return _strip(context, invites: invites, others: others);
          },
        );
      },
    );
  }

  Widget _strip(
    BuildContext context, {
    required int invites,
    required int others,
  }) {
    final palette = context.palette;
    final waiting = invites > 0;
    // Green reads as "live" and matches the dot on the Quiz pill, so the
    // same signal looks the same wherever it appears.
    final accent = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF4CD964)
        : AppColors.successGreen;

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.lg, 0, AppSpace.lg, 12),
      child: Pressable(
        haptics: true,
        pressedScale: 0.98,
        onTap: () => context.pushNamed('quiz'),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: palette.card,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: waiting
                  ? accent.withValues(alpha: 0.55)
                  : palette.divider,
            ),
            boxShadow: AppShadows.card(context),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.bolt_rounded, color: accent, size: 21),
              ),
              const SizedBox(width: 12),
              // Expanded: these strings scale with the system font, and an
              // unflexed Text in a Row throws rather than clipping.
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      waiting
                          ? (invites == 1
                                ? 'Someone wants to play'
                                : '$invites people want to play')
                          : 'Live match',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.titleSmall.copyWith(
                        color: palette.text,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      // "in the app", not "in the arena". This count comes
                      // from the app-wide presence channel, so it includes
                      // members reading the feed or in a chat. Promising
                      // "play someone" told people an opponent was queued
                      // and waiting; they tapped, searched, found nobody,
                      // and decided live match was broken. Offering a
                      // challenge is a promise this number can keep.
                      waiting
                          ? 'Tap to join before it expires'
                          : others == 1
                          ? '1 member in the app · challenge them'
                          : '$others members in the app · challenge one',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.labelSmall.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w600,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (waiting)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    '$invites',
                    style: AppTextStyles.labelSmall.copyWith(
                      color: AppColors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                    ),
                  ),
                )
              else
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: palette.textMuted,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
