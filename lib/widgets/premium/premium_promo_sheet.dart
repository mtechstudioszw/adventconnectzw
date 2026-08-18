import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/ads/ad_impression_counter.dart';
import '../../services/premium_promo_service.dart';
import '../../services/premium_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../motion/motion.dart';

/// The once-a-fortnight ask.
///
/// Short on purpose. Its whole job is to make one true, personal point —
/// how many ads this person has actually sat through — and offer the way
/// out. The full argument lives on the Premium screen; a bottom sheet
/// that tries to make it all is a wall the user swipes away.
class PremiumPromoSheet extends StatelessWidget {
  const PremiumPromoSheet({super.key});

  /// Show it, if [PremiumPromoService] allows. Returns true if shown.
  ///
  /// The caller passes the CURRENT route and whether a text field has
  /// focus — both are checked at the last possible moment, because the
  /// user may have started typing since the trigger was scheduled.
  static Future<bool> maybeShow(BuildContext context) async {
    // Something else is already on top — the update nudge, the signup
    // survey, a dialog. Never stack a sales pitch on another prompt;
    // the 14-day rule means we can simply wait.
    if (ModalRoute.of(context)?.isCurrent != true) return false;

    final route = GoRouter.of(context)
        .routerDelegate
        .currentConfiguration
        .uri
        .path;
    final isTyping = FocusManager.instance.primaryFocus?.hasFocus == true &&
        // A focused *text* field means a keyboard; a focused button
        // doesn't, and shouldn't block the promo forever.
        FocusManager.instance.primaryFocus?.context?.widget is! ButtonStyleButton;

    final allowed = await PremiumPromoService.canShowNow(
      route: route,
      isTyping: isTyping,
    );
    if (!allowed) return false;
    if (!context.mounted) return false;

    await PremiumPromoService.markShown();
    if (!context.mounted) return false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const PremiumPromoSheet(),
    );
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final seen = AdImpressionCounter.count;

    return Container(
      decoration: BoxDecoration(
        color: palette.sheet,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: palette.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              const Icon(Icons.star_rounded,
                  color: AppColors.goldAccent, size: 30),
              const SizedBox(height: 12),
              Text(
                seen >= 10
                    ? "You've seen $seen ads in Adventist Super App"
                    : 'Adventist Super App without the ads',
                style: TextStyle(
                  fontSize: 22,
                  height: 1.2,
                  fontWeight: FontWeight.w800,
                  color: palette.text,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                seen >= 10
                    ? 'Premium switches off every one of them — and stops the '
                        'app asking for them at all, so it uses less data and '
                        'less battery.'
                    : 'Premium removes every ad in the app, and stops it even '
                        'requesting them — less data, less battery.',
                style: TextStyle(
                  fontSize: 15,
                  height: 1.45,
                  color: palette.textMuted,
                ),
              ),
              const SizedBox(height: 20),
              LoadingButton(
                label: 'See Premium',
                icon: Icons.star_rounded,
                onPressed: () {
                  Navigator.of(context).pop();
                  context.pushNamed('premium');
                },
              ),
              const SizedBox(height: 2),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style:
                      TextButton.styleFrom(foregroundColor: palette.textMuted),
                  // Honest about what happens next, and about the fact
                  // that we won't nag: that promise is why the 14-day
                  // rule exists at all.
                  child: const Text("Not now — I'll keep the ads"),
                ),
              ),
              ValueListenableBuilder<bool>(
                valueListenable: PremiumService.isPremium,
                builder: (context, isPremium, _) {
                  // Belt and braces: if a purchase lands while this is
                  // open, get out of the way immediately.
                  if (isPremium) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (Navigator.of(context).canPop()) {
                        Navigator.of(context).pop();
                      }
                    });
                  }
                  return const SizedBox.shrink();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
