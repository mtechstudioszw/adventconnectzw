import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/fundraiser_model.dart';
import '../../services/fundraiser_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';
import '../motion/pressable.dart';

/// "Help us reach iPhone" — an optional, dismissible card in the home feed.
///
/// ## What it is, and what it is deliberately not
///
/// It is a card in the feed, the same shape and weight as
/// [InviteFriendsCard] two slots away. It is NOT a popup, an interstitial,
/// a paywall or a subscription pitch: it never covers the screen, never
/// blocks anything, never returns after it is closed, and never sends a
/// notification. Everything in the app stays free whether or not anyone
/// gives a cent — the moment that stops being true this becomes an
/// unbilled in-app purchase under both stores' rules.
///
/// ## It self-hides
///
/// The parent drops in `const IphoneFundraiserCard()` and thinks about it
/// no further. The card renders nothing at all when:
///
///   * the campaign has not loaded yet (no spinner, no placeholder — a
///     skeleton for an optional ask is worse than nothing);
///   * the member closed it, on this or any of their devices;
///   * the founder set the campaign to `paused`;
///   * the app is running on iOS, where the pitch is nonsense.
///
/// A [FundraiserCampaign] that is `completed` still renders, once: the
/// thank-you. That is the only state that asks for nothing.
class IphoneFundraiserCard extends StatefulWidget {
  const IphoneFundraiserCard({super.key, this.horizontalMargin = 16});

  /// Outer horizontal margin. Set to 0 when the parent already supplies
  /// edge padding, so the card does not double-indent — same contract as
  /// [InviteFriendsCard].
  final double horizontalMargin;

  @override
  State<IphoneFundraiserCard> createState() => _IphoneFundraiserCardState();
}

class _IphoneFundraiserCardState extends State<IphoneFundraiserCard> {
  @override
  void initState() {
    super.initState();
    // Cached value first (synchronous, no frame cost), then a throttled
    // refresh that usually decides it has nothing to do.
    FundraiserService.hydrate();
    FundraiserService.refresh();
  }

  @override
  Widget build(BuildContext context) {
    // Asking an iPhone user to fund the iPhone build is nonsense, and one
    // day this app will run there. Reading it off the Theme rather than
    // dart:io keeps it settable in a widget test.
    final platform = Theme.of(context).platform;
    if (platform == TargetPlatform.iOS || platform == TargetPlatform.macOS) {
      return const SizedBox.shrink();
    }

    return ValueListenableBuilder<FundraiserCampaign?>(
      valueListenable: FundraiserService.campaign,
      builder: (context, campaign, _) {
        if (campaign == null || !campaign.canShowCard) {
          return const SizedBox.shrink();
        }
        FundraiserService.noteCardShown(campaign);
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: widget.horizontalMargin),
          child: FundraiserCardBody(
            campaign: campaign,
            onDismiss: FundraiserService.dismiss,
            onSupport: () {
              FundraiserService.noteSupportTapped();
              context.pushNamed('iphone_fundraiser');
            },
          ),
        );
      },
    );
  }
}

/// The card itself, with no service coupling and no routing, so every
/// campaign state can be pumped directly in a widget test.
class FundraiserCardBody extends StatelessWidget {
  const FundraiserCardBody({
    super.key,
    required this.campaign,
    required this.onDismiss,
    required this.onSupport,
  });

  final FundraiserCampaign campaign;
  final VoidCallback onDismiss;
  final VoidCallback onSupport;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final done = campaign.isCompleted;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 14),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: palette.divider),
        boxShadow: AppShadows.card(context),
      ),
      child: Column(
        // Sized to its content, not to whatever it is dropped into. It
        // lives in an unbounded feed today; a card that silently becomes
        // full-height in a constrained parent is exactly the takeover
        // this feature must never be.
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Mark(done: done),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  // Optically centres the title against the 40px mark
                  // without a Center, which would push the subtitle around
                  // as it wraps.
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    // Server copy, for BOTH states: fundraiser_status()
                    // hands back the thank-you as title/body once the
                    // campaign is funded (patch_256), so there is no
                    // branch here and no wording to keep in step with the
                    // database. `done` still drives the colour and icon.
                    campaign.title,
                    style: AppTextStyles.titleMedium.copyWith(
                      color: palette.text,
                      fontWeight: FontWeight.w700,
                      fontSize: 14.5,
                    ),
                  ),
                ),
              ),
              // The close affordance. Small, quiet, and always present —
              // including on the thank-you, where it is the only control.
              _CloseButton(onTap: onDismiss),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            campaign.body,
            style: AppTextStyles.bodySmall.copyWith(
              color: palette.textMuted,
              fontSize: 11.5,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 12),
          _ProgressBlock(campaign: campaign),
          if (!done) ...[
            const SizedBox(height: 12),
            _SupportButton(onTap: onSupport),
            const SizedBox(height: 8),
            // The sentence that keeps this a community message rather than
            // a pitch. It is also the compliance line: giving unlocks
            // nothing, so it is not a purchase.
            Text(
              'Completely optional. Everything in the app stays free either way.',
              style: AppTextStyles.caption.copyWith(
                color: palette.textMuted,
                fontSize: 10.5,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The 40px mark. Gradient blue for the ask, green for the finish — green
/// is a status colour in this app and "funded" is exactly a status.
class _Mark extends StatelessWidget {
  const _Mark({required this.done});
  final bool done;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        gradient: done ? null : AppColors.primaryGradient,
        color: done ? AppColors.successGreen : null,
        borderRadius: BorderRadius.circular(AppRadius.button),
      ),
      child: Icon(
        // Material's own Apple glyph rather than an emoji: emoji render
        // differently on every Android skin and would be the only one in
        // the whole feed.
        done ? Icons.check_rounded : Icons.apple,
        color: AppColors.white,
        size: 21,
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
      label: 'Dismiss the iPhone fundraiser card',
      child: InkResponse(
        onTap: onTap,
        radius: 20,
        // A 36px target inside a 20px glyph: reachable by thumb without
        // making "close" the loudest thing on the card.
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(
            Icons.close_rounded,
            size: 17,
            color: context.palette.textMuted,
          ),
        ),
      ),
    );
  }
}

/// "$42 raised of $99" + the bar.
class _ProgressBlock extends StatelessWidget {
  const _ProgressBlock({required this.campaign});
  final FundraiserCampaign campaign;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final done = campaign.isCompleted;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: campaign.raisedLabel,
                      style: AppTextStyles.titleMedium.copyWith(
                        color: done
                            ? AppColors.successGreen
                            : AppColors.primaryBlue,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    TextSpan(
                      text: ' raised of ${campaign.goalLabel}',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: palette.textMuted,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Text(
              '${campaign.percent}%',
              style: AppTextStyles.labelSmall.copyWith(
                color: palette.textMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        FundraiserProgressBar(
          progress: campaign.progress,
          complete: done,
        ),
        if (campaign.myPending > 0) ...[
          const SizedBox(height: 8),
          Text(
            // Reassurance, not a status log. Someone who told us they were
            // sending money and then saw the bar not move would reasonably
            // assume it was lost.
            campaign.myPending == 1
                ? 'Your contribution is being checked. Thank you.'
                : 'Your contributions are being checked. Thank you.',
            style: AppTextStyles.caption.copyWith(
              color: palette.textMuted,
              fontSize: 10.5,
            ),
          ),
        ],
      ],
    );
  }
}

/// The bar. Shared with the fundraiser screen so the two can never drift.
class FundraiserProgressBar extends StatelessWidget {
  const FundraiserProgressBar({
    super.key,
    required this.progress,
    this.complete = false,
    this.height = 8,
  });

  /// 0.0 – 1.0, already clamped by [FundraiserCampaign.progress].
  final double progress;
  final bool complete;
  final double height;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: Container(
        height: height,
        color: palette.cardMuted,
        child: Align(
          alignment: Alignment.centerLeft,
          // One short fill on first paint, then nothing. Enough to read as
          // progress; not enough to be a moving thing on a feed the user
          // is trying to scroll.
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: progress.clamp(0.0, 1.0)),
            duration: AppMotion.celebrate,
            curve: AppMotion.easeOut,
            builder: (context, value, _) => FractionallySizedBox(
              widthFactor: value <= 0 ? 0 : value,
              child: Container(
                decoration: BoxDecoration(
                  gradient: complete ? null : AppColors.primaryGradient,
                  color: complete ? AppColors.successGreen : null,
                  borderRadius: BorderRadius.circular(height),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SupportButton extends StatelessWidget {
  const _SupportButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      pressedScale: 0.98,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.volunteer_activism_rounded,
              size: 17,
              color: AppColors.white,
            ),
            const SizedBox(width: 8),
            Text(
              'Support the project',
              style: AppTextStyles.buttonText.copyWith(
                color: AppColors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
