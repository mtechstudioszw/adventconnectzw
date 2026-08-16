import 'package:flutter/material.dart';
import '../../widgets/screen_shell.dart';
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
                    // Order matters here, and it used to be backwards.
                    //
                    // The screen opened on a red "Violations = permanent ban"
                    // panel — the first thing a member saw when they offered
                    // to open a shop was a threat, before a single word about
                    // what we actually ask of them. It also meant the page
                    // led at its loudest and got quieter, so nothing after it
                    // registered.
                    //
                    // Now it reads the way an agreement reads: what this is,
                    // the five commitments, what happens if you break them,
                    // then the commitment itself. The consequence is no
                    // softer — it just comes after the terms it applies to,
                    // and directly above the box you tick.
                    _buildIntro(context),
                    const SizedBox(height: 18),
                    for (var i = 0; i < _rules.length; i++) ...[
                      _RuleCard(rule: _rules[i], index: i + 1),
                      const SizedBox(height: 12),
                    ],
                    const SizedBox(height: 8),
                    _buildBanWarning(),
                    const SizedBox(height: 18),
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
    return const ScreenHero(
      title: 'Code of Conduct',
      tagline: 'Marketplace',
      subtitle: 'Read this carefully. Selling here means agreeing to it.',
      fallbackRoute: 'marketplace',
    );
  }

  /// Says what the document is before it starts making demands, and names
  /// the number of commitments so the page has a knowable length. A wall of
  /// five unnumbered cards gives no sense of how far in you are.
  Widget _buildIntro(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primaryBlue.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.primaryBlue.withValues(alpha: 0.16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.storefront_outlined,
                size: 17,
                color: AppColors.primaryBlue,
              ),
              const SizedBox(width: 8),
              // Flexible, not bare. This is a letter-spaced label at a fixed
              // 10.5px that still scales with the system font — at 2.5x it
              // overflowed the row by 14px, which is a red-and-yellow stripe
              // across the top of the agreement rather than a quiet clip.
              Flexible(
                child: Text(
                  'FIVE COMMITMENTS',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.primaryBlue,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.3,
                    fontSize: 10.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Advent Marketplace runs on trust between members — there is no '
            'middleman holding your money or checking your parcels. These are '
            'what make that work.',
            style: AppTextStyles.bodySmall.copyWith(
              color: context.palette.text,
              height: 1.55,
              fontSize: 12.8,
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
                    color: context.palette.text,
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
                side: BorderSide(
                  color: context.palette.divider,
                ),
              ),
              child: Text(
                'Not now',
                style: AppTextStyles.buttonText.copyWith(
                  color: context.palette.text,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            // The disabled state used to be `Opacity(0.55)` over the live
            // gradient: a faded blue button that still looked like a button
            // and gave no reason for not working. Tapping it did nothing and
            // said nothing.
            //
            // Now the two states are genuinely different surfaces — a flat
            // tonal fill with no shadow when it is inert, the gradient and
            // its glow only once the box is ticked — and the label itself
            // carries the instruction. The member is never left guessing
            // which of the things on this page they still have to do.
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              decoration: BoxDecoration(
                gradient: _accepted ? AppColors.primaryGradient : null,
                color: _accepted
                    ? null
                    : context.palette.divider.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(14),
                boxShadow: _accepted
                    ? [
                        BoxShadow(
                          color: AppColors.primaryBlue.withValues(alpha: 0.28),
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
                        _accepted ? 'Continue to setup' : 'Tick to agree',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.buttonText.copyWith(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: _accepted
                              ? AppColors.white
                              : context.palette.textMuted,
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

/// One commitment.
///
/// Numbered, because five identical cards read as a list of suggestions
/// rather than the terms of an agreement — and because a member scrolling
/// a page of consequences deserves to know where they are in it.
///
/// The prohibition card is the one exception to the shared treatment. It is
/// the only rule that is a list of things you may NOT do, it is three times
/// the length of any other, and giving it the same blue chip as "Christian
/// honesty" flattened the one item most likely to get someone banned into
/// the middle of the stack. It keeps the same shape and the same number —
/// it is still commitment four, not a warning panel — but its glyph and rule
/// carry the palette's red so the eye stops there.
class _RuleCard extends StatelessWidget {
  const _RuleCard({required this.rule, required this.index});
  final _Rule rule;
  final int index;

  @override
  Widget build(BuildContext context) {
    final isProhibition = rule.icon == Icons.block;
    final accent = isProhibition ? AppColors.red : AppColors.primaryBlue;

    return Container(
      padding: const EdgeInsets.fromLTRB(0, 16, 16, 16),
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
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // A hairline rule down the card's leading edge, tinted to the
            // accent. Cheaper than a coloured card and it survives dark mode.
            Container(
              width: 3,
              margin: const EdgeInsets.only(right: 13),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: isProhibition ? 0.55 : 0.30),
                borderRadius: const BorderRadius.horizontal(
                  right: Radius.circular(3),
                ),
              ),
            ),
            Column(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(rule.icon, color: accent, size: 18),
                ),
                const SizedBox(height: 6),
                Text(
                  index.toString().padLeft(2, '0'),
                  style: AppTextStyles.labelSmall.copyWith(
                    color: context.palette.textMuted,
                    fontWeight: FontWeight.w800,
                    fontSize: 10,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
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
                      color: context.palette.text,
                      height: 1.55,
                      fontSize: 12.8,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
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
                  : context.palette.divider,
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
                        : context.palette.divider,
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
                    color: context.palette.text,
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
