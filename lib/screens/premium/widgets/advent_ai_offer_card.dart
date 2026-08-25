import 'package:flutter/material.dart';

import '../../../services/ai/ai_balance_service.dart';
import '../../../services/ai/ai_tiers.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_palette.dart';
import '../../../theme/app_text_styles.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/advent_ai_mark.dart';

/// The hero of the Premium offer.
///
/// # Why this card exists, and why it sits FIRST
///
/// Premium used to sell one thing: the absence of advertising. Every
/// line on the screen was about something being switched off, the button
/// said "Switching ads off", and declining meant tapping "Keep watching
/// ads for now".
///
/// That is a negative benefit — you are asked to pay so the app will
/// stop doing something to you — and in a church app it reads as being
/// squeezed. It also gave the member nothing to look forward to.
///
/// Advent AI is the first genuinely POSITIVE thing Premium has ever had
/// to offer, so it leads. Ads move to one supporting line, reframed as
/// what it actually is: who pays for the app, members or advertisers.
///
/// # The sample exchange is the whole design
///
/// Everything else on a paywall is a claim. A worked example is
/// evidence. Someone who reads these three lines knows what they would
/// be buying better than any bullet list could tell them, and the
/// example chosen is deliberately a real pastoral question rather than a
/// party trick — it shows the assistant answering the kind of thing this
/// congregation actually asks.
///
/// The verse shown is quoted exactly (KJV, Matthew 11:28) because that
/// is what the real feature does. A paywall that misquotes scripture to
/// sell a Bible assistant would deserve everything it got.
class AdventAiOfferCard extends StatelessWidget {
  const AdventAiOfferCard({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.goldAccent.withValues(alpha: 0.35)),
        boxShadow: AppShadows.card(context),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(),
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpace.lg, 0, AppSpace.lg, AppSpace.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SampleExchange(),
                const SizedBox(height: AppSpace.lg),
                _AllowanceLine(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
          AppSpace.lg, AppSpace.lg, AppSpace.lg, AppSpace.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: const Icon(AdventAiBrand.icon,
                color: Colors.white, size: 20),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Advent AI',
                    style: AppTextStyles.titleMedium
                        .copyWith(color: palette.text)),
                const SizedBox(height: 2),
                Text(
                  'Study the Word with a helper that knows your Bible',
                  style: AppTextStyles.bodySmall
                      .copyWith(color: palette.textMuted, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A worked example, styled as the real transcript is.
///
/// Not a screenshot: a screenshot goes stale the first time the chat
/// screen changes, and cannot be read by a screen reader. This is the
/// same widgets the real screen uses, so it ages with the app.
class _SampleExchange extends StatelessWidget {
  const _SampleExchange();

  static const _question = 'I feel worn out. What does Jesus say to that?';

  static const _answer =
      'He speaks to exactly that in Matthew 11:28 — "Come unto me, all '
      'ye that labour and are heavy laden, and I will give you rest."\n\n'
      'The invitation is not to try harder first. It is to come as you '
      'are, tired, and let Him carry it.';

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: palette.chipBg,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The member's turn, right-aligned exactly as in the real chat.
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              margin: const EdgeInsets.only(left: 32, bottom: AppSpace.md),
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpace.md, vertical: AppSpace.sm),
              decoration: BoxDecoration(
                color: AppColors.primaryBlue,
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
              child: Text(
                _question,
                style: AppTextStyles.bodySmall
                    .copyWith(color: Colors.white, height: 1.4),
              ),
            ),
          ),
          Row(
            children: [
              Icon(AdventAiBrand.icon,
                  size: 13, color: AppColors.goldAccent),
              const SizedBox(width: AppSpace.xs),
              Text('Advent AI',
                  style: AppTextStyles.labelSmall
                      .copyWith(color: palette.textMuted)),
            ],
          ),
          const SizedBox(height: AppSpace.xs),
          Text(
            _answer,
            style: AppTextStyles.bodySmall
                .copyWith(color: palette.text, height: 1.5),
          ),
        ],
      ),
    );
  }
}

/// What the member has now, and what Premium changes.
///
/// # Why the plan figure and the live figure are two separate lines
///
/// This used to show ONE value that swapped between them: the member's
/// remaining questions when the balance had loaded, and "10 a month"
/// when it had not. Both are true, and showing them in the same slot
/// made them look like the same number changing.
///
/// The founder read it exactly that way on 25 Aug 2026 — "when the user
/// signs in again, if they were left with 2 messages it restarts to 10".
/// Nothing had been re-granted; `ai_accounts` is per member and only
/// rolls over on the 1st (verified against the live rows). What reset
/// was this label, because signing in again empties the client's balance
/// cache for a moment and the fallback copy is the plan's headline
/// number.
///
/// So: the plan figure is stated as the plan, permanently, and the
/// member's own standing appears beneath it as its own line when it is
/// actually known. Neither can now be mistaken for the other.
class _AllowanceLine extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return ValueListenableBuilder<AiBalance>(
      valueListenable: AiBalanceService.balance,
      builder: (context, balance, _) {
        final known = balance.grant > 0 || balance.remaining > 0;
        final n = balance.remaining;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _Step(
                label: 'Free',
                value: '${AiTiers.free.monthlyMessages} a month',
                note: known && !balance.isPremium
                    ? '$n left this month'
                    : null,
                muted: true,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
              child: Icon(Icons.arrow_forward_rounded,
                  size: 16, color: palette.textMuted),
            ),
            Expanded(
              child: _Step(
                label: 'Premium',
                value: '${AiTiers.premium.monthlyMessages} a month',
                muted: false,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.label,
    required this.value,
    required this.muted,
    this.note,
  });

  final String label;
  final String value;
  final bool muted;

  /// The member's own standing, under the plan's figure. Null when it is
  /// not known — never substituted for [value]. See [_AllowanceLine].
  final String? note;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: AppTextStyles.labelSmall.copyWith(
            color: palette.textMuted,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: AppTextStyles.titleSmall.copyWith(
            color: muted ? palette.textMuted : AppColors.primaryBlue,
          ),
        ),
        if (note != null) ...[
          const SizedBox(height: 2),
          Text(
            note!,
            style: AppTextStyles.labelSmall.copyWith(color: palette.textMuted),
          ),
        ],
      ],
    );
  }
}
