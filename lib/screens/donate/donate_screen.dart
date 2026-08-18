import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/motion/pressable.dart';
import '../../widgets/motion/staggered_reveal.dart';
import '../../widgets/screen_shell.dart';

/// "Support this ministry" — a voluntary EcoCash gift.
///
/// ## Why this collects nothing in-app
///
/// The screen deliberately has no payment form, no amount field and no
/// purchase flow. It hands the member off to EcoCash (tap-to-copy the number,
/// or `*151#` in the system dialer) and the money moves entirely outside the
/// app. That is what keeps the build shippable on both stores:
///
/// * **Google Play** — Play Billing is required for in-app digital purchases.
///   Donations are explicitly outside that, and nothing here unlocks content.
/// * **App Store** — 3.2.1 allows collecting donations, but they must not go
///   through in-app purchase and must not gate any functionality.
///
/// The hard rule that keeps both true: **a gift must never unlock a feature,
/// a badge, or content.** The moment donating buys something, this stops being
/// a donation and becomes an unbilled in-app purchase on both stores. If you
/// ever want donor perks, they have to go through Play Billing / StoreKit
/// instead — do not add them here.
class DonateScreen extends StatelessWidget {
  const DonateScreen({super.key});

  /// The ministry's EcoCash line. Mirrors the number Settings has used since
  /// the first release — change it in both places, or neither.
  static const String ecoCashNumber = '0778 092 494';

  /// **The name EcoCash itself will show.**
  ///
  /// This used to read "Adventist Super App", which is the name of the app and
  /// NOT the name the line is registered to. EcoCash displays the registered
  /// account holder at the confirmation step, so a member following these
  /// instructions saw a personal name appear where the app had promised an
  /// organisation — at the exact moment they were about to part with money.
  ///
  /// That is a trust problem before it is anything else: the natural reading
  /// is "I have the wrong number", and the transfer gets abandoned. It is
  /// also the one thing on this screen that could be called misleading, and
  /// Play's Deceptive Behavior policy is about claims that do not match
  /// reality — not about who happens to hold the account.
  ///
  /// So the app now says the true name up front and explains the
  /// relationship. Honest is also higher-converting here: nobody hesitates
  /// at a confirmation screen that says exactly what they were told it would.
  static const String ecoCashName = 'Tanatswa Michael Mikuwa';

  /// Why that name and not the app's.
  static const String ecoCashNameNote =
      'EcoCash will show this name when you confirm — it is the personal '
      'line of the developer who builds and pays for Adventist Super App.';

  void _snack(BuildContext context, String message, {bool good = true}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: good ? AppColors.successGreen : AppColors.red,
        content: Text(
          message,
          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
        ),
      ),
    );
  }

  Future<void> _copyNumber(BuildContext context) async {
    await Clipboard.setData(const ClipboardData(text: ecoCashNumber));
    if (!context.mounted) return;
    HapticFeedback.selectionClick();
    _snack(context, 'EcoCash number copied — paste it in the EcoCash app.');
  }

  Future<void> _dialUssd(BuildContext context) async {
    // *151# is the EcoCash menu shortcut on Econet lines. The # is encoded as
    // %23 because some Android dialers refuse a raw # in a tel: URI. This
    // opens the dialer pre-filled; the member presses call themselves.
    final uri = Uri.parse('tel:*151%23');
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) throw Exception('launch failed');
    } catch (_) {
      if (!context.mounted) return;
      _snack(
        context,
        'Could not open the dialer. Dial *151# manually.',
        good: false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          const ScreenHero(
            title: 'Support this ministry',
            tagline: 'Give',
            subtitle: 'Voluntary, never required, and it unlocks nothing — '
                'it just keeps the app alive.',
            fallbackRoute: 'home',
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.lg,
                AppSpace.sm,
                AppSpace.lg,
                AppSpace.xxl,
              ),
              children: [
                const StaggeredReveal(index: 0, child: _GiftHero()),
                const SizedBox(height: AppSpace.lg),
                StaggeredReveal(
                  index: 1,
                  child: _NumberCard(
                    number: ecoCashNumber,
                    name: ecoCashName,
                    nameNote: ecoCashNameNote,
                    onCopy: () => _copyNumber(context),
                  ),
                ),
                const SizedBox(height: AppSpace.md),
                StaggeredReveal(
                  index: 2,
                  child: PrimaryGradientButton(
                    label: 'Open dialer  •  *151#',
                    icon: Icons.dialpad_rounded,
                    onTap: () => _dialUssd(context),
                  ),
                ),
                const SizedBox(height: AppSpace.sm),
                StaggeredReveal(
                  index: 3,
                  child: _SecondaryButton(
                    label: 'Copy number',
                    icon: Icons.copy_rounded,
                    onTap: () => _copyNumber(context),
                  ),
                ),
                const SizedBox(height: AppSpace.xl),
                const StaggeredReveal(index: 4, child: _HowToSend()),
                const SizedBox(height: AppSpace.lg),
                const StaggeredReveal(index: 5, child: _TransparencyNote()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The emotional beat: what a gift actually pays for.
class _GiftHero extends StatelessWidget {
  const _GiftHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.darkNavy, Color(0xFF1A2F5A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: AppShadows.card(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppRadius.button),
                  border: Border.all(color: AppColors.goldAccent, width: 1.4),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.favorite_rounded,
                  color: AppColors.goldAccent,
                  size: 22,
                ),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Text(
                  'Help keep it running',
                  style: AppTextStyles.titleLarge.copyWith(
                    color: AppColors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          // Concrete, not abstract. "Support us" asks for charity; naming
          // the actual bills asks for a share of something real, and the
          // things named here are the ones members can see for themselves.
          Text(
            'Adventist Super App is built and paid for by one person, and every '
            'feature stays free for everyone. There are real bills behind it: '
            'the servers that carry your posts and messages, the storage that '
            'keeps the Bible, the hymnal and Sabbath School working offline, '
            'and the hours that go into what comes next.',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.white.withValues(alpha: 0.80),
              height: 1.55,
            ),
          ),
          const SizedBox(height: AppSpace.md),
          Text(
            'If the app has been a blessing to you, a gift of any size helps '
            'carry it for the next person. Nothing is too small.',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.goldAccent,
              height: 1.55,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _NumberCard extends StatelessWidget {
  const _NumberCard({
    required this.number,
    required this.name,
    required this.nameNote,
    required this.onCopy,
  });

  final String number;
  final String name;
  final String nameNote;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Pressable(
      onTap: onCopy,
      pressedScale: 0.985,
      child: Container(
        padding: const EdgeInsets.all(AppSpace.lg),
        decoration: BoxDecoration(
          color: palette.card,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: palette.divider),
          boxShadow: AppShadows.card(context),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ECOCASH NUMBER',
                    style: AppTextStyles.labelSmall.copyWith(
                      color: palette.textMuted,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    number,
                    style: AppTextStyles.headlineSmall.copyWith(
                      color: palette.text,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // The registered account holder, given real weight rather
                  // than muted footnote styling — this is the name the
                  // member is about to see in EcoCash, and matching it is
                  // what stops them abandoning the transfer.
                  Text(
                    name,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: palette.text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    nameNote,
                    style: AppTextStyles.caption.copyWith(
                      color: palette.textMuted,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpace.md),
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.primaryBlue.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.copy_rounded,
                size: 19,
                color: AppColors.primaryBlue,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Pressable(
      onTap: onTap,
      pressedScale: 0.97,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: palette.card,
          borderRadius: BorderRadius.circular(AppRadius.button),
          border: Border.all(color: palette.divider),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: palette.text),
            const SizedBox(width: AppSpace.sm),
            Text(
              label,
              style: AppTextStyles.buttonText.copyWith(
                color: palette.text,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HowToSend extends StatelessWidget {
  const _HowToSend();

  static const _steps = [
    'Dial *151# (or open the EcoCash app)',
    'Choose "Send Money" → "To Mobile"',
    'Enter the number above',
    'Enter any amount you would like to give',
    // Named explicitly at the step where it appears, so the confirmation
    // screen holds no surprises. A member who was not told this hesitates
    // here and cancels.
    'Check the name shown is $_holder, then confirm with your PIN',
  ];

  static const String _holder = DonateScreen.ecoCashName;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'How to send',
          style: AppTextStyles.titleMedium.copyWith(
            color: palette.text,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: AppSpace.md),
        for (var i = 0; i < _steps.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: AppColors.primaryBlue.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${i + 1}',
                    style: AppTextStyles.labelSmall.copyWith(
                      color: AppColors.primaryBlue,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      _steps[i],
                      style: AppTextStyles.bodySmall.copyWith(
                        color: palette.textMuted,
                        height: 1.45,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// States plainly that a gift buys nothing. This is not boilerplate — it is
/// the sentence that makes the screen compliant, and it must stay true.
class _TransparencyNote extends StatelessWidget {
  const _TransparencyNote();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: palette.cardMuted,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: palette.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 17,
            color: palette.textMuted,
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Text(
              'Giving is entirely voluntary. Every feature of Adventist Super App '
              'ZW stays free and fully available whether or not you give — a '
              'gift unlocks nothing, earns no badge, and is separate from '
              'Premium, so it does not remove ads. Money is sent directly '
              'through EcoCash, outside the app, to the account named above. '
              'Adventist Super App is not a registered charity, so a gift is '
              'not a tax-deductible donation and is not tithe — give your '
              'tithe to your local church.',
              style: AppTextStyles.caption.copyWith(
                color: palette.textMuted,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
