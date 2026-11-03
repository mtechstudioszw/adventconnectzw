import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../config/platform_flags.dart';
import '../../../services/billing/call_pack_catalog.dart';
import '../../../services/billing/call_pack_service.dart';
import '../../../services/premium_service.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_palette.dart';
import '../../../theme/app_text_styles.dart';

/// "Get more call minutes" (owner, 3 Nov 2026): two one-off packs, plus the
/// Premium route for people who call every day. Android only — the
/// iPhone build sells nothing ([kHidePayments]), so [show] does nothing
/// there and callers don't need to check.
class CallPackSheet extends StatefulWidget {
  const CallPackSheet({super.key});

  static Future<void> show(BuildContext context) async {
    if (kHidePayments) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.palette.sheet,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const CallPackSheet(),
    );
  }

  @override
  State<CallPackSheet> createState() => _CallPackSheetState();
}

class _CallPackSheetState extends State<CallPackSheet> {
  @override
  void initState() {
    super.initState();
    CallPackService.loadOffers();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: ValueListenableBuilder<CallPackFlow>(
          valueListenable: CallPackService.state,
          builder: (context, flow, _) {
            final busy =
                flow == CallPackFlow.loading ||
                flow == CallPackFlow.purchasing ||
                flow == CallPackFlow.verifying;
            return Column(
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
                const SizedBox(height: 16),
                Text(
                  'Get more call minutes',
                  style: AppTextStyles.titleLarge.copyWith(
                    color: palette.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'A one-off top-up, no subscription. Used only after your '
                  "daily minutes run out, and it lasts ${CallPack.validDays} "
                  'days.',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: palette.textMuted,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 16),
                if (flow == CallPackFlow.success)
                  _Banner(
                    icon: Icons.check_circle_rounded,
                    color: AppColors.successGreen,
                    text:
                        '${CallPackService.lastMinutes ?? ''} minutes added. '
                        'Happy calling!',
                  )
                else if (flow == CallPackFlow.unavailable ||
                    flow == CallPackFlow.failed ||
                    flow == CallPackFlow.pendingPayment)
                  _Banner(
                    icon: flow == CallPackFlow.pendingPayment
                        ? Icons.hourglass_top_rounded
                        : Icons.info_outline_rounded,
                    color: flow == CallPackFlow.failed
                        ? AppColors.red
                        : AppColors.primaryBlue,
                    text: CallPackService.message ?? 'Please try again.',
                  ),
                for (final pack in CallPack.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _PackTile(
                      pack: pack,
                      price:
                          CallPackService.offerFor(pack)?.price ??
                          pack.fallbackPrice,
                      enabled: !busy && CallPackService.offerFor(pack) != null,
                      best: pack == CallPack.large,
                      onTap: () => CallPackService.buy(pack),
                    ),
                  ),
                if (busy)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 6),
                    child: LinearProgressIndicator(minHeight: 3),
                  ),
                if (!PremiumService.isActive) ...[
                  const SizedBox(height: 6),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      context.pushNamed('premium');
                    },
                    child: const Text(
                      'Call every day? Premium gives 6 hours a day →',
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PackTile extends StatelessWidget {
  const _PackTile({
    required this.pack,
    required this.price,
    required this.enabled,
    required this.best,
    required this.onTap,
  });

  final CallPack pack;
  final String price;
  final bool enabled;
  final bool best;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final hours = pack.minutes ~/ 60;
    return Material(
      color: palette.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: best ? AppColors.primaryBlue : palette.divider,
              width: best ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.call_rounded,
                  color: AppColors.primaryBlue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            pack.title,
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: palette.text,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (best) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primaryBlue,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Best value',
                              style: AppTextStyles.caption.copyWith(
                                color: AppColors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${pack.minutes} minutes ($hours hours) · '
                      '${CallPack.validDays} days',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: palette.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                price,
                style: AppTextStyles.titleSmall.copyWith(
                  color: enabled ? AppColors.primaryBlue : palette.textMuted,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.bodySmall.copyWith(
                color: context.palette.text,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
