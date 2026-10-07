import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../config/platform_flags.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_palette.dart';
import '../../../theme/app_text_styles.dart';
import '../../../theme/app_tokens.dart';
import '../ai_gate_copy.dart';

/// The sheet shown when Advent AI will not answer.
///
/// All five refusal states share this one surface, because they are the
/// same moment from the member's side — they asked and did not get an
/// answer. What differs is only the words, and those come from
/// [AiGateCopy], which is where the reasoning lives.
///
/// Two structural rules the sheet enforces regardless of copy:
///
///  * **The reassurance line always renders.** It is not optional and
///    not conditional. Without it a paywall in a church app reads as
///    the doors being locked.
///  * **The Premium button only exists when the copy provides one.**
///    Two states deliberately have nothing to sell — a subscriber who
///    has spent their allowance, and a service that is currently down —
///    and the sheet cannot invent a button for them.
Future<void> showAiGateSheet(BuildContext context, AiGateCopy copy) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.palette.sheet,
    shape: const RoundedRectangleBorder(
      borderRadius:
          BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
    ),
    builder: (context) => _GateSheet(copy: copy),
  );
}

class _GateSheet extends StatelessWidget {
  const _GateSheet({required this.copy});
  final AiGateCopy copy;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpace.xl, AppSpace.lg, AppSpace.xl, AppSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
            const SizedBox(height: AppSpace.xl),

            Text(
              copy.title,
              style: AppTextStyles.titleMedium.copyWith(color: palette.text),
            ),
            const SizedBox(height: AppSpace.sm),
            Text(
              copy.body,
              style: AppTextStyles.bodyMedium.copyWith(
                color: palette.textMuted,
                height: 1.5,
              ),
            ),

            if (copy.offersPremium) ...[
              const SizedBox(height: AppSpace.lg),
              Container(
                padding: const EdgeInsets.all(AppSpace.md),
                decoration: BoxDecoration(
                  color: palette.chipBg,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final b in copy.benefits)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpace.sm),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.check_rounded,
                                size: 16, color: AppColors.goldAccent),
                            const SizedBox(width: AppSpace.sm),
                            Expanded(
                              child: Text(
                                b,
                                style: AppTextStyles.bodySmall
                                    .copyWith(color: palette.text, height: 1.4),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: AppSpace.lg),

            // Never on iOS: this opens the Premium screen, and no
            // In-App Purchase is configured there.
            if (copy.primaryLabel != null && !kHidePayments)
              _PrimaryButton(
                label: copy.primaryLabel!,
                onTap: () {
                  Navigator.of(context).pop();
                  context.push('/premium');
                },
              ),

            if (copy.secondaryLabel != null)
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  copy.secondaryLabel!,
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: palette.textMuted),
                ),
              ),

            const SizedBox(height: AppSpace.sm),

            // Always. See the class doc — this is the line that stops a
            // paywall reading as a locked door, so it is not behind any
            // condition.
            Text(
              copy.reassurance,
              textAlign: TextAlign.center,
              style: AppTextStyles.labelSmall.copyWith(
                color: palette.textMuted,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.button),
        onTap: onTap,
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
          child: Center(
            child: Text(
              label,
              style: AppTextStyles.titleSmall.copyWith(color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}