import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/fundamental_beliefs.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/motion/pressable.dart';
import '../../widgets/screen_shell.dart';
import 'library_open.dart';

/// The 28 Fundamental Beliefs, grouped under the official six headings.
///
/// Summaries are the app's own (see [kFundamentalBeliefs]); the official
/// statement is one tap away on every screen, and each Bible text opens the
/// reader. Bundled, so it works offline.
class BeliefsScreen extends StatelessWidget {
  const BeliefsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final children = <Widget>[
      Text(
        'Short summaries written for this app, with key Bible texts. '
        'Read the official statement at adventist.org.',
        style: AppTextStyles.bodySmall.copyWith(color: palette.textMuted),
      ),
      const SizedBox(height: AppSpace.sm),
      const _OfficialLink(),
    ];
    String? group;
    for (final b in kFundamentalBeliefs) {
      if (b.group != group) {
        group = b.group;
        children.add(
          Padding(
            padding: const EdgeInsets.only(
              top: AppSpace.xl,
              bottom: AppSpace.sm,
            ),
            child: Text(
              group.toUpperCase(),
              style: AppTextStyles.overline.copyWith(
                color: palette.textMuted,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      }
      children.add(
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.sm),
          child: _BeliefRow(belief: b),
        ),
      );
    }
    return FlatStatusBar(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          title: Text(
            '28 Fundamental Beliefs',
            style: AppTextStyles.appBarTitleFlat.copyWith(fontSize: 19),
          ),
        ),
        body: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.lg,
              AppSpace.sm,
              AppSpace.lg,
              AppSpace.xxl,
            ),
            children: children,
          ),
        ),
      ),
    );
  }
}

class _BeliefRow extends StatelessWidget {
  const _BeliefRow({required this.belief});
  final FundamentalBelief belief;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Semantics(
      button: true,
      label: 'Belief ${belief.number}: ${belief.title}',
      excludeSemantics: true,
      child: Pressable(
        onTap: () => Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => BeliefDetailScreen(belief: belief),
          ),
        ),
        child: Container(
          padding: const EdgeInsets.all(AppSpace.md),
          decoration: BoxDecoration(
            color: palette.card,
            borderRadius: BorderRadius.circular(AppRadius.card),
            boxShadow: AppShadows.card(context),
          ),
          child: Row(
            children: [
              _NumberBadge(number: belief.number),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Text(
                  belief.title,
                  style: AppTextStyles.labelLarge.copyWith(
                    color: palette.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: palette.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _NumberBadge extends StatelessWidget {
  const _NumberBadge({required this.number});
  final int number;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.primaryBlue.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        '$number',
        style: AppTextStyles.labelLarge.copyWith(
          color: context.palette.brandBlue,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _OfficialLink extends StatelessWidget {
  const _OfficialLink();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () => launchUrl(
          Uri.parse(kBeliefsOfficialUrl),
          mode: LaunchMode.externalApplication,
        ),
        icon: const Icon(Icons.open_in_new_rounded, size: 16),
        label: const Text('Official statement — adventist.org'),
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primaryBlue,
          padding: EdgeInsets.zero,
          textStyle: AppTextStyles.labelMedium.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// One belief: summary, key texts (each opens the Bible), official link,
/// and previous / next.
class BeliefDetailScreen extends StatelessWidget {
  const BeliefDetailScreen({super.key, required this.belief});
  final FundamentalBelief belief;

  void _go(BuildContext context, int number) {
    final next = kFundamentalBeliefs.firstWhere((b) => b.number == number);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => BeliefDetailScreen(belief: next)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return FlatStatusBar(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          title: Text(
            'Belief ${belief.number} of 28',
            style: AppTextStyles.appBarTitleFlat.copyWith(fontSize: 19),
          ),
        ),
        body: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.lg,
              AppSpace.sm,
              AppSpace.lg,
              AppSpace.xxl,
            ),
            children: [
              Text(
                belief.group.toUpperCase(),
                style: AppTextStyles.overline.copyWith(
                  color: palette.textMuted,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpace.xs),
              Text(
                belief.title,
                style: AppTextStyles.headlineSmall.copyWith(
                  color: palette.text,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpace.lg),
              ScreenCard(
                child: Text(
                  belief.summary,
                  style: AppTextStyles.bodyLarge.copyWith(
                    color: palette.text,
                    height: 1.6,
                  ),
                ),
              ),
              const SizedBox(height: AppSpace.xl),
              Text(
                'KEY BIBLE TEXTS',
                style: AppTextStyles.overline.copyWith(
                  color: palette.textMuted,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpace.sm),
              Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.sm,
                children: [
                  for (final ref in belief.texts)
                    ActionChip(
                      avatar: Icon(
                        Icons.menu_book_rounded,
                        size: 16,
                        color: palette.brandBlue,
                      ),
                      label: Text(ref),
                      labelStyle: AppTextStyles.labelMedium.copyWith(
                        color: palette.text,
                        fontWeight: FontWeight.w600,
                      ),
                      backgroundColor: palette.card,
                      side: BorderSide(color: palette.divider),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      onPressed: () async {
                        final ok = await LibraryOpen.reference(context, ref);
                        if (!ok && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text("Couldn't open $ref.")),
                          );
                        }
                      },
                    ),
                ],
              ),
              const SizedBox(height: AppSpace.lg),
              Text(
                'This is a summary written for this app, not the official '
                'wording.',
                style: AppTextStyles.caption.copyWith(color: palette.textMuted),
              ),
              const _OfficialLink(),
              const SizedBox(height: AppSpace.lg),
              Row(
                children: [
                  if (belief.number > 1)
                    TextButton.icon(
                      onPressed: () => _go(context, belief.number - 1),
                      icon: const Icon(Icons.chevron_left_rounded),
                      label: Text('${belief.number - 1}'),
                    ),
                  const Spacer(),
                  if (belief.number < kFundamentalBeliefs.length)
                    TextButton.icon(
                      onPressed: () => _go(context, belief.number + 1),
                      iconAlignment: IconAlignment.end,
                      icon: const Icon(Icons.chevron_right_rounded),
                      label: Text('Next: ${belief.number + 1}'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
