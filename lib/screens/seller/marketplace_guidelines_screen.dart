import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';

/// Marketplace Code of Conduct gate. Replaces the old admin-approval
/// step — anyone authenticated can now open a storefront, but they
/// must explicitly accept the code first. The version string lives
/// here so a future tightening can force re-acceptance by bumping it.
///
/// Routes to /seller/setup with the acceptance carried via `extra`.
class MarketplaceGuidelinesScreen extends StatefulWidget {
  const MarketplaceGuidelinesScreen({super.key});

  /// Current code version. If we ever tighten the rules, bump this —
  /// the sellers table stores which version each user accepted, so
  /// the app can require re-acceptance for outdated entries.
  static const String codeVersion = 'v1-2026-05';

  @override
  State<MarketplaceGuidelinesScreen> createState() =>
      _MarketplaceGuidelinesScreenState();
}

class _MarketplaceGuidelinesScreenState
    extends State<MarketplaceGuidelinesScreen> {
  bool _accepted = false;

  static const _rules = <_Rule>[
    _Rule(
      icon: Icons.handshake_outlined,
      title: 'Christian honesty',
      body:
          'Real photos. Honest descriptions. Fair, transparent pricing. '
          'No bait-and-switch, no inflated claims, no fake reviews.',
    ),
    _Rule(
      icon: Icons.brightness_3_outlined,
      title: 'Respect the Sabbath',
      body:
          'No deliveries, sales pushes, or scheduled transactions from '
          'Friday sundown to Saturday sundown. Buyers will be patient '
          'with you — extend the same.',
    ),
    _Rule(
      icon: Icons.eco_outlined,
      title: 'Adventist-values products only',
      body:
          'Sell things that align with our beliefs — wholesome food, '
          'modest clothing, Christian books and music, health products, '
          'craftwork, services. Use good judgement.',
    ),
    _Rule(
      icon: Icons.block,
      title: 'What is NOT allowed',
      body:
          '• Alcohol, tobacco, vapes, recreational drugs\n'
          '• Pork, shellfish, or unclean meats per Lev 11\n'
          '• Gambling, lotteries, betting\n'
          '• Immodest clothing, intimate apparel\n'
          '• Occult / horoscope / divination items\n'
          '• Violent or sexually explicit media\n'
          '• Counterfeit / pirated / stolen goods\n'
          '• Anything illegal under Zimbabwean law',
    ),
    _Rule(
      icon: Icons.security_outlined,
      title: 'Protect the community',
      body:
          'No spam, no harassment, no scams, no impersonation. Treat '
          'every buyer like a fellow believer — because they are.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.scaffoldBg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHero(context),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildBanWarning(),
                    const SizedBox(height: 16),
                    for (final r in _rules) ...[
                      _RuleCard(rule: r),
                      const SizedBox(height: 12),
                    ],
                    const SizedBox(height: 8),
                    _AcceptanceTile(
                      accepted: _accepted,
                      onChanged: (v) => setState(() => _accepted = v),
                    ),
                  ],
                ),
              ),
            ),
            _buildFooter(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHero(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(gradient: AppColors.appBarGradient),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => context.canPop()
                      ? context.pop()
                      : context.goNamed('marketplace'),
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.white.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppColors.white.withValues(alpha: 0.10),
                      ),
                    ),
                    child: const Icon(
                      Icons.arrow_back,
                      color: AppColors.white,
                      size: 18,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MARKETPLACE',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.white.withValues(alpha: 0.55),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.8,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Code of Conduct',
                  style: AppTextStyles.displayMedium.copyWith(
                    color: AppColors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Read this carefully. Selling here means agreeing to it.',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.white.withValues(alpha: 0.78),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBanWarning() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.red.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.red.withValues(alpha: 0.30)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.red.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.gavel_outlined,
              color: AppColors.red,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Violations = permanent ban',
                  style: AppTextStyles.titleMedium.copyWith(
                    color: AppColors.red,
                    fontWeight: FontWeight.w800,
                    fontSize: 14.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'If we (or the community via Report) find you breaking '
                  'these guidelines, your store will be taken down, your '
                  'products removed, and your account permanently banned '
                  'from selling. No second chances on serious breaches.',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: const Color.fromRGBO(26, 26, 46, 0.78),
                    height: 1.5,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Container(
      color: context.palette.card,
      padding: EdgeInsets.fromLTRB(
        20,
        14,
        20,
        14 + MediaQuery.of(context).viewPadding.bottom,
      ),
      child: Row(
        children: [
          Expanded(
            flex: 1,
            child: OutlinedButton(
              onPressed: () => context.canPop()
                  ? context.pop()
                  : context.goNamed('marketplace'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                side: const BorderSide(
                  color: Color.fromRGBO(26, 26, 46, 0.18),
                ),
              ),
              child: Text(
                'Not now',
                style: AppTextStyles.buttonText.copyWith(
                  color: AppColors.textDark,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: Opacity(
              opacity: _accepted ? 1.0 : 0.55,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: _accepted
                      ? [
                          BoxShadow(
                            color:
                                AppColors.primaryBlue.withValues(alpha: 0.28),
                            blurRadius: 14,
                            offset: const Offset(0, 6),
                          ),
                        ]
                      : null,
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _accepted ? () => _continue(context) : null,
                    borderRadius: BorderRadius.circular(14),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      child: Center(
                        child: Text(
                          'Continue to setup',
                          style: AppTextStyles.buttonText.copyWith(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _continue(BuildContext context) {
    HapticFeedback.mediumImpact();
    // We pass the accepted version forward via `extra` so the setup
    // screen can stamp it onto the sellers row at insert time.
    context.pushNamed(
      'setup_store',
      extra: MarketplaceGuidelinesScreen.codeVersion,
    );
  }
}

class _Rule {
  const _Rule({
    required this.icon,
    required this.title,
    required this.body,
  });
  final IconData icon;
  final String title;
  final String body;
}

class _RuleCard extends StatelessWidget {
  const _RuleCard({required this.rule});
  final _Rule rule;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(rule.icon, color: AppColors.primaryBlue, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rule.title,
                  style: AppTextStyles.titleMedium.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 14.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  rule.body,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: const Color.fromRGBO(26, 26, 46, 0.72),
                    height: 1.55,
                    fontSize: 12.8,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AcceptanceTile extends StatelessWidget {
  const _AcceptanceTile({required this.accepted, required this.onChanged});

  final bool accepted;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: accepted
          ? AppColors.primaryBlue.withValues(alpha: 0.08)
          : context.palette.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => onChanged(!accepted),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: accepted
                  ? AppColors.primaryBlue
                  : const Color.fromRGBO(26, 26, 46, 0.10),
              width: accepted ? 1.5 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color:
                      accepted ? AppColors.primaryBlue : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: accepted
                        ? AppColors.primaryBlue
                        : const Color.fromRGBO(26, 26, 46, 0.30),
                    width: 1.5,
                  ),
                ),
                child: accepted
                    ? const Icon(
                        Icons.check,
                        size: 16,
                        color: AppColors.white,
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'I have read and agree to the Marketplace Code of '
                  'Conduct. I understand that violations result in '
                  'permanent removal from the marketplace.',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textDark,
                    height: 1.5,
                    fontSize: 13.5,
                    fontWeight:
                        accepted ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
