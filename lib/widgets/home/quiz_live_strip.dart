import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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
/// This renders nothing at all unless somebody has challenged you or
/// somebody is actually sitting in the live-match queue. That restraint is
/// the point: the lobby tile used to promise "head to head, same clock" at
/// 3am to an empty arena, so members tapped it, waited out a search, found
/// no one, and concluded the feature was broken. An empty arena is the
/// COMMON case here, not the edge one.
///
/// ## The number is the QUEUE, never presence
///
/// Founder, 18 Aug 2026: *"the quiz live banner is lying tt some people
/// online to play quiz live when one will be in the lobby"*.
///
/// This strip used to appear whenever anyone had the app open, and say "N
/// members in the app · challenge one". Every word of that was literally
/// true and the whole thing still lied, because a green bolt on a strip
/// that only shows up when people are around reads as *there is a game
/// here* — and then the arena was empty. Softening the copy had already
/// been tried twice and could not fix it; the strip was appearing on the
/// wrong signal.
///
/// So it now counts open queue entries ([QuizHomeSignal.waiting],
/// patch_212) — the exact rows `quiz_match_find` would pair you with. When
/// nobody is queued, Home says nothing at all about live match rather than
/// advertising a room with nobody in it.
class QuizLiveStrip extends StatelessWidget {
  const QuizLiveStrip({super.key, this.viewerId});

  /// The signed-in member's id.
  ///
  /// Kept for the caller's convenience and for tests; the queue count is
  /// filtered server-side by `auth.uid()`, so nothing here has to subtract
  /// the viewer any more — which is where the old count went wrong twice.
  final String? viewerId;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: QuizHomeSignal.invites,
      builder: (context, invites, _) {
        return ValueListenableBuilder<int>(
          valueListenable: QuizHomeSignal.waiting,
          builder: (context, queued, _) {
            if (invites < 1 && queued < 1) return const SizedBox.shrink();
            return _strip(context, invites: invites, queued: queued);
          },
        );
      },
    );
  }

  Widget _strip(
    BuildContext context, {
    required int invites,
    required int queued,
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
                      // "waiting in the arena" is now literally what the
                      // number is — an open queue entry that a tap will be
                      // paired with. It may only ever say this because it
                      // no longer comes from presence.
                      waiting
                          ? 'Tap to join before it expires'
                          : queued == 1
                          ? '1 player waiting in the arena · tap to play'
                          : '$queued players waiting in the arena',
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
