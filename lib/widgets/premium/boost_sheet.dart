import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../config/platform_flags.dart';
import '../../services/billing/boost_catalog.dart';
import '../../services/billing/boost_service.dart';
import '../../services/billing/premium_tier.dart';
import '../../services/premium_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../motion/brand_spinner.dart';
import '../screen_shell.dart';

/// Pay to put one listing or job in front of more people (patch 289).
///
/// Business members spend a monthly credit; everyone can buy one through
/// Google Play. Returns true when a boost landed. Never shown on iOS —
/// callers check [kHidePayments], and this refuses too.
Future<bool> showBoostSheet(
  BuildContext context, {
  required BoostKind kind,
  required int targetId,
  required String targetTitle,
}) async {
  if (kHidePayments) return false;
  final landed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.palette.scaffoldBg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => BoostSheet(
      kind: kind,
      targetId: targetId,
      targetTitle: targetTitle,
    ),
  );
  return landed ?? false;
}

class BoostSheet extends StatefulWidget {
  const BoostSheet({
    super.key,
    required this.kind,
    required this.targetId,
    required this.targetTitle,
  });

  final BoostKind kind;
  final int targetId;
  final String targetTitle;

  @override
  State<BoostSheet> createState() => _BoostSheetState();
}

class _BoostSheetState extends State<BoostSheet> {
  DateTime? _activeUntil;
  BoostCredits? _credits;
  bool _loading = true;
  bool _spending = false;
  String? _error;

  BoostKind get _kind => widget.kind;

  int get _creditsLeft => _credits == null
      ? 0
      : (_kind == BoostKind.job ? _credits!.job : _credits!.listing);

  @override
  void initState() {
    super.initState();
    BoostService.resetFlow();
    BoostService.state.addListener(_onFlow);
    _load();
  }

  @override
  void dispose() {
    BoostService.state.removeListener(_onFlow);
    super.dispose();
  }

  Future<void> _load() async {
    final results = await Future.wait<Object?>([
      BoostService.activeUntil(_kind, widget.targetId),
      PremiumService.tier == PremiumTier.business
          ? BoostService.creditsLeft()
          : Future<BoostCredits?>.value(null),
      BoostService.loadOffer(_kind),
    ]);
    if (!mounted) return;
    setState(() {
      _activeUntil = results[0] as DateTime?;
      _credits = results[1] as BoostCredits?;
      _loading = false;
    });
  }

  void _onFlow() {
    if (!mounted) return;
    if (BoostService.state.value == BoostFlow.success) {
      final messenger = ScaffoldMessenger.maybeOf(context);
      Navigator.of(context).pop(true);
      _toast(messenger, BoostService.lastEndsAt);
      return;
    }
    setState(() {});
  }

  void _toast(ScaffoldMessengerState? messenger, DateTime? ends) {
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          ends == null
              ? 'Boosted.'
              : 'Boosted until ${_date(ends)}. It is labelled "Promoted".',
        ),
      ),
    );
  }

  Future<void> _useCredit() async {
    setState(() {
      _spending = true;
      _error = null;
    });
    try {
      final ends = await BoostService.useCredit(_kind, widget.targetId);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      Navigator.of(context).pop(true);
      _toast(messenger, ends);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _spending = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final flow = BoostService.state.value;
    final offer = BoostService.offerFor(_kind);
    final busy = _spending ||
        flow == BoostFlow.purchasing ||
        flow == BoostFlow.verifying;
    final isBusiness = PremiumService.tier == PremiumTier.business;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: palette.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.trending_up_rounded, color: palette.brandBlue),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _kind.title,
                    style: AppTextStyles.titleMedium.copyWith(
                      color: palette.text,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              widget.targetTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodySmall.copyWith(color: palette.textMuted),
            ),
            const SizedBox(height: 12),
            Text(
              '${_kind.blurb} People see it marked "Promoted", so it stays '
              'honest. It does not change who can contact you or the price.',
              style: AppTextStyles.bodySmall.copyWith(
                color: palette.textMuted,
                height: 1.45,
              ),
            ),
            if (_activeUntil != null) ...[
              const SizedBox(height: 10),
              InfoBanner(
                message:
                    'Promoted until ${_date(_activeUntil!)}. Boosting again '
                    'adds ${_kind.days} more days.',
              ),
            ],
            const SizedBox(height: 16),
            if (_loading)
              const Center(child: BrandSpinner(size: 26))
            else ...[
              if (isBusiness)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: PrimaryGradientButton(
                    key: const Key('boost-use-credit'),
                    label: _creditsLeft > 0
                        ? 'Use a monthly boost ($_creditsLeft left)'
                        : 'Monthly boosts used up',
                    icon: Icons.bolt_rounded,
                    busy: _spending,
                    onTap: _creditsLeft > 0 && !busy ? _useCredit : null,
                  ),
                ),
              if (offer != null)
                SizedBox(
                  width: double.infinity,
                  child: isBusiness
                      ? OutlinedButton(
                          key: const Key('boost-buy'),
                          onPressed: busy
                              ? null
                              : () => BoostService.buy(_kind, widget.targetId),
                          style: _outlined,
                          child: Text('Buy a boost · ${offer.price}'),
                        )
                      : PrimaryGradientButton(
                          key: const Key('boost-buy'),
                          label: flow == BoostFlow.verifying
                              ? 'Confirming payment…'
                              : 'Boost for ${offer.price}',
                          busy: busy,
                          onTap: busy
                              ? null
                              : () => BoostService.buy(_kind, widget.targetId),
                        ),
                )
              else if (!isBusiness)
                InfoBanner(
                  message: BoostService.message ??
                      "Paid boosts aren't on sale yet.",
                ),
              if (!isBusiness) ...[
                const SizedBox(height: 10),
                Center(
                  child: TextButton(
                    onPressed: () {
                      Navigator.of(context).pop(false);
                      context.pushNamed('premium');
                    },
                    child: Text(
                      'Business includes ${TierBenefits.business.listingBoostsPerMonth} '
                      'listing boosts and ${TierBenefits.business.jobBoostsPerMonth} '
                      'featured jobs every month',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
              if (flow == BoostFlow.pendingPayment ||
                  flow == BoostFlow.failed ||
                  _error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error ?? BoostService.message ?? '',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: flow == BoostFlow.pendingPayment
                        ? palette.textMuted
                        : AppColors.red,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  static final _outlined = OutlinedButton.styleFrom(
    foregroundColor: AppColors.primaryBlue,
    side: const BorderSide(color: AppColors.primaryBlue),
    minimumSize: const Size.fromHeight(48),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
  );
}

String _date(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${d.day} ${months[d.month - 1]}';
}
