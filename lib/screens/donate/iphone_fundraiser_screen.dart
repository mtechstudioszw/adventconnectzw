import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/fundraiser_model.dart';
import '../../services/fundraiser_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/home/iphone_fundraiser_card.dart';
import '../../widgets/motion/pressable.dart';
import '../../widgets/motion/staggered_reveal.dart';
import '../../widgets/screen_shell.dart';
import '../../widgets/support_sheet.dart';
import 'donate_screen.dart';

/// The iPhone fundraiser, in full: why we are asking, how far along we are,
/// and how to help if you want to.
///
/// ## Nothing is collected here
///
/// There is no card field, no Play Billing product, no StoreKit, no
/// "confirm payment" button that means anything. Money moves through
/// EcoCash — or through a WhatsApp/email conversation for anyone who does
/// not have EcoCash — exactly as [DonateScreen] already does, and for the
/// same two reasons:
///
///   * **Google Play** requires Play Billing for in-app digital purchases.
///     Donations sit outside that only while they unlock nothing.
///   * **App Store 3.2.1** permits collecting donations, but not through
///     in-app purchase, and they must not gate functionality.
///
/// So the invariant from the donate screen carries over verbatim: **a
/// contribution must never unlock a feature, a badge, or content.** If
/// donor perks are ever wanted they have to go through Play Billing /
/// StoreKit instead. Do not add them here.
///
/// ## "I have sent it" is a note, not a payment
///
/// Tapping it records a PENDING row. The server clamps it to pending
/// whatever this client sends, and it counts toward the total only once
/// the founder confirms the money actually arrived on the line. That is
/// the whole reason the progress bar can be trusted.
class IphoneFundraiserScreen extends StatefulWidget {
  const IphoneFundraiserScreen({super.key});

  @override
  State<IphoneFundraiserScreen> createState() => _IphoneFundraiserScreenState();
}

class _IphoneFundraiserScreenState extends State<IphoneFundraiserScreen> {
  /// The chosen amount in cents, or null for "hasn't decided yet". Nothing
  /// is preselected on purpose — a preselected amount is a nudge, and the
  /// brief is explicit that this must not pressure anyone.
  int? _amountCents;

  final _customController = TextEditingController();
  final _referenceController = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    FundraiserService.hydrate();
    // Forced: this is the one screen where the number on the bar is the
    // thing the member came to look at.
    FundraiserService.refresh(force: true);
  }

  @override
  void dispose() {
    _customController.dispose();
    _referenceController.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------
  //  Handoffs — every one of these leaves the app
  // -------------------------------------------------------------------

  void _snack(String message, {bool good = true}) {
    if (!mounted) return;
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

  Future<void> _copyNumber() async {
    await Clipboard.setData(
      const ClipboardData(text: DonateScreen.ecoCashNumber),
    );
    HapticFeedback.selectionClick();
    _snack('EcoCash number copied — paste it in the EcoCash app.');
  }

  Future<void> _dialUssd() async {
    // *151# is the EcoCash menu on Econet lines. The # is percent-encoded
    // because some Android dialers refuse a raw # in a tel: URI. Opens the
    // dialer pre-filled; the member presses call themselves.
    try {
      final ok = await launchUrl(
        Uri.parse('tel:*151%23'),
        mode: LaunchMode.externalApplication,
      );
      if (!ok) throw Exception('launch failed');
    } catch (_) {
      _snack('Could not open the dialer. Dial *151# manually.', good: false);
    }
  }

  /// For members with no EcoCash: talk to the founder and work something
  /// out. Bank transfer, cash, a different wallet, another country's
  /// mobile money — all of it is a conversation, not a form.
  Future<void> _arrangeAnotherWay(FundraiserCampaign campaign) async {
    final amount = _amountCents;
    final intro = amount == null
        ? 'Hi, I would like to help with the iPhone fundraiser but I do not '
            'have EcoCash. What is the best way to send it?'
        : 'Hi, I would like to help with the iPhone fundraiser with '
            '${campaign.formatCents(amount)}, but I do not have EcoCash. '
            'What is the best way to send it?';
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ArrangeSheet(message: intro),
    );
  }

  // -------------------------------------------------------------------
  //  The pledge
  // -------------------------------------------------------------------

  /// A tapped chip wins; otherwise whatever was typed in the custom field.
  int? _resolveAmount() {
    final chosen = _amountCents;
    if (chosen != null && chosen > 0) return chosen;
    return FundraiserCampaign.parseAmountToCents(_customController.text);
  }

  Future<void> _confirmSent(FundraiserCampaign campaign) async {
    final amount = _resolveAmount();
    if (amount == null) {
      _snack('Choose an amount first, or type one in.', good: false);
      return;
    }

    setState(() => _busy = true);
    final result = await FundraiserService.recordPledge(
      amountCents: amount,
      method: 'ecocash',
      reference: _referenceController.text.trim().isEmpty
          ? null
          : _referenceController.text.trim(),
    );
    if (!mounted) return;
    setState(() => _busy = false);

    switch (result) {
      case PledgeResult.recorded:
        _referenceController.clear();
        _customController.clear();
        setState(() => _amountCents = null);
        await _showThankYou(campaign, amount);
      case PledgeResult.campaignClosed:
        _snack(
          'The goal has already been reached — thank you all the same.',
        );
      case PledgeResult.tooMany:
        _snack(
          'You already have contributions waiting to be checked. We will '
          'get to them shortly.',
          good: false,
        );
      case PledgeResult.invalidAmount:
        _snack('That amount does not look right. Try again.', good: false);
      case PledgeResult.signedOut:
        _snack('Sign in first so we can thank you properly.', good: false);
      case PledgeResult.failed:
        // Friendly and generic on purpose. No SQL text, no status code, no
        // row id — none of that helps a member and some of it is a leak.
        _snack(
          'We could not save that just now. Your transfer is safe — try '
          'again in a moment.',
          good: false,
        );
    }
  }

  Future<void> _showThankYou(FundraiserCampaign campaign, int amount) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.palette.sheet,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        title: Text(
          'Thank you',
          style: AppTextStyles.titleLarge.copyWith(fontWeight: FontWeight.w800),
        ),
        content: Text(
          'We have noted ${campaign.formatCents(amount)}. Once the transfer '
          'shows up on the line it will be added to the total. There is '
          'nothing else you need to do.',
          style: AppTextStyles.bodyMedium.copyWith(
            color: context.palette.textMuted,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Close',
              style: AppTextStyles.buttonText
                  .copyWith(color: AppColors.primaryBlue),
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          const ScreenHero(
            title: 'Bring the app to iPhone',
            tagline: 'Community project',
            subtitle: 'Optional, never required, and it unlocks nothing.',
            fallbackRoute: 'home',
          ),
          Expanded(
            child: ValueListenableBuilder<FundraiserCampaign?>(
              valueListenable: FundraiserService.campaign,
              builder: (context, campaign, _) {
                if (campaign == null) return const _LoadingBody();
                return _body(campaign);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(FundraiserCampaign campaign) {
    final done = !campaign.isActive;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        AppSpace.sm,
        AppSpace.lg,
        AppSpace.xxl,
      ),
      children: [
        StaggeredReveal(index: 0, child: _ProgressCard(campaign: campaign)),
        const SizedBox(height: AppSpace.lg),
        const StaggeredReveal(index: 1, child: _WhyCard()),
        if (done) ...[
          const SizedBox(height: AppSpace.lg),
          StaggeredReveal(index: 2, child: _ClosedNote(campaign: campaign)),
        ] else ...[
          const SizedBox(height: AppSpace.xl),
          StaggeredReveal(
            index: 2,
            child: _AmountPicker(
              campaign: campaign,
              selected: _amountCents,
              controller: _customController,
              onSelected: (cents) => setState(() {
                _amountCents = cents;
                if (cents != null) _customController.clear();
              }),
              onCustomChanged: () => setState(() => _amountCents = null),
            ),
          ),
          const SizedBox(height: AppSpace.xl),
          StaggeredReveal(
            index: 3,
            child: _HowToSendCard(
              onCopy: _copyNumber,
              onDial: _dialUssd,
              onNoEcoCash: () => _arrangeAnotherWay(campaign),
            ),
          ),
          const SizedBox(height: AppSpace.xl),
          StaggeredReveal(
            index: 4,
            child: _ConfirmBlock(
              controller: _referenceController,
              busy: _busy,
              onConfirm: () => _confirmSent(campaign),
            ),
          ),
        ],
        const SizedBox(height: AppSpace.xl),
        const StaggeredReveal(index: 5, child: _TransparencyNote()),
      ],
    );
  }
}

/// No spinner. The screen has nothing urgent to show and a throbber on an
/// optional ask reads as a load-bearing wait.
class _LoadingBody extends StatelessWidget {
  const _LoadingBody();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Text(
          'Loading the campaign...',
          style: AppTextStyles.bodyMedium
              .copyWith(color: context.palette.textMuted),
        ),
      ),
    );
  }
}

/// Where we are. The one number people came for.
class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.campaign});
  final FundraiserCampaign campaign;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final done = campaign.isCompleted;
    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: palette.divider),
        boxShadow: AppShadows.card(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                campaign.raisedLabel,
                style: AppTextStyles.displayMedium.copyWith(
                  color: done ? AppColors.successGreen : AppColors.primaryBlue,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text(
                  'of ${campaign.goalLabel}',
                  style: AppTextStyles.titleMedium.copyWith(
                    color: palette.textMuted,
                  ),
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text(
                  '${campaign.percent}%',
                  style: AppTextStyles.titleMedium.copyWith(
                    color: palette.textMuted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          FundraiserProgressBar(
            progress: campaign.progress,
            complete: done,
            height: 10,
          ),
          const SizedBox(height: AppSpace.md),
          Text(
            done
                ? 'The goal has been reached. Thank you to everyone who '
                    'helped get us here.'
                : campaign.supporters == 0
                    ? '${campaign.remainingLabel} to go.'
                    : '${campaign.remainingLabel} to go, with '
                        '${campaign.supporters} '
                        '${campaign.supporters == 1 ? "person" : "people"} '
                        'helping so far.',
            style: AppTextStyles.bodySmall.copyWith(
              color: palette.textMuted,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Why we are asking. Plain, specific, and short.
class _WhyCard extends StatelessWidget {
  const _WhyCard();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Why we are raising this',
          style: AppTextStyles.titleMedium.copyWith(
            color: palette.text,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: AppSpace.md),
        Text(
          'Adventist Super App is on Android today. Plenty of members have '
          'asked for it on iPhone, and the app itself is ready for them — '
          'the one thing standing in the way is the Apple Developer Program '
          'membership, which Apple charges every year before an app can go '
          'on the App Store.\n\n'
          'That is what this is for. Nothing else. When we get there the '
          'iOS build goes up and the whole community can reach people who '
          'were previously left out.',
          style: AppTextStyles.bodySmall.copyWith(
            color: palette.textMuted,
            height: 1.6,
          ),
        ),
      ],
    );
  }
}

/// Shown once the campaign is funded or paused, in place of the whole
/// contribution flow. Section 10 of the brief: stop asking.
class _ClosedNote extends StatelessWidget {
  const _ClosedNote({required this.campaign});
  final FundraiserCampaign campaign;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final funded = campaign.isCompleted;
    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: palette.cardMuted,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: palette.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            funded ? Icons.check_circle_rounded : Icons.pause_circle_outline,
            size: 20,
            color: funded ? AppColors.successGreen : palette.textMuted,
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Text(
              funded
                  ? 'We are not collecting any more for this campaign. If you '
                      'still want to support the app in general there is a '
                      '"Support this ministry" page in Settings.'
                  : 'This campaign is paused right now. Nothing to do — we '
                      'will say so here when it opens again.',
              style: AppTextStyles.bodySmall.copyWith(
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

/// The amount chips + a custom field. Amounts come from the server so a
/// campaign can change them without a release.
class _AmountPicker extends StatelessWidget {
  const _AmountPicker({
    required this.campaign,
    required this.selected,
    required this.controller,
    required this.onSelected,
    required this.onCustomChanged,
  });

  final FundraiserCampaign campaign;
  final int? selected;
  final TextEditingController controller;
  final ValueChanged<int?> onSelected;
  final VoidCallback onCustomChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'How much would you like to give?',
          style: AppTextStyles.titleMedium.copyWith(
            color: palette.text,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Whatever you choose is welcome. Even the smallest amount moves '
          'the bar.',
          style: AppTextStyles.bodySmall.copyWith(color: palette.textMuted),
        ),
        const SizedBox(height: AppSpace.md),
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          children: [
            for (final cents in campaign.amountsCents)
              _AmountChip(
                label: campaign.formatCents(cents),
                selected: selected == cents,
                onTap: () => onSelected(selected == cents ? null : cents),
              ),
          ],
        ),
        const SizedBox(height: AppSpace.md),
        TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            LengthLimitingTextInputFormatter(9),
          ],
          onChanged: (_) => onCustomChanged(),
          style: AppTextStyles.bodyMedium.copyWith(color: palette.text),
          decoration: InputDecoration(
            filled: true,
            fillColor: palette.inputFill,
            hintText: 'Or type another amount',
            hintStyle:
                AppTextStyles.bodyMedium.copyWith(color: palette.textMuted),
            prefixText: campaign.currencySymbol,
            prefixStyle: AppTextStyles.bodyMedium.copyWith(
              color: palette.text,
              fontWeight: FontWeight.w700,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.button),
              borderSide: BorderSide(color: palette.divider),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.button),
              borderSide: BorderSide(color: palette.divider),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.button),
              borderSide: const BorderSide(color: AppColors.primaryBlue),
            ),
          ),
        ),
      ],
    );
  }
}

class _AmountChip extends StatelessWidget {
  const _AmountChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Pressable(
      onTap: onTap,
      pressedScale: 0.95,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
        decoration: BoxDecoration(
          gradient: selected ? AppColors.primaryGradient : null,
          color: selected ? null : palette.chipBg,
          borderRadius: AppRadius.pillAll,
          border: Border.all(
            color: selected ? Colors.transparent : palette.divider,
          ),
        ),
        child: Text(
          label,
          style: AppTextStyles.buttonText.copyWith(
            color: selected ? AppColors.white : palette.text,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// The EcoCash handoff, plus the door for everyone who does not have it.
class _HowToSendCard extends StatelessWidget {
  const _HowToSendCard({
    required this.onCopy,
    required this.onDial,
    required this.onNoEcoCash,
  });

  final VoidCallback onCopy;
  final VoidCallback onDial;
  final VoidCallback onNoEcoCash;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'How to send it',
          style: AppTextStyles.titleMedium.copyWith(
            color: palette.text,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'The money goes through EcoCash, outside the app.',
          style: AppTextStyles.bodySmall.copyWith(color: palette.textMuted),
        ),
        const SizedBox(height: AppSpace.md),
        Pressable(
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
                        DonateScreen.ecoCashNumber,
                        style: AppTextStyles.headlineSmall.copyWith(
                          color: palette.text,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      // The registered account holder, said out loud before
                      // EcoCash says it. A member who was not told this name
                      // in advance reads the confirmation screen as "wrong
                      // number" and abandons the transfer.
                      Text(
                        DonateScreen.ecoCashName,
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: palette.text,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        DonateScreen.ecoCashNameNote,
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
        ),
        const SizedBox(height: AppSpace.md),
        PrimaryGradientButton(
          label: 'Open dialer  •  *151#',
          icon: Icons.dialpad_rounded,
          onTap: onDial,
        ),
        const SizedBox(height: AppSpace.sm),
        // The door for everyone outside Zimbabwe, or on a different
        // network, or simply without a wallet. Quiet, but always visible —
        // a member who cannot use the only method on screen and is offered
        // no alternative just leaves.
        Pressable(
          onTap: onNoEcoCash,
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
                Icon(Icons.forum_outlined, size: 18, color: palette.text),
                const SizedBox(width: AppSpace.sm),
                Flexible(
                  child: Text(
                    'I do not have EcoCash',
                    style: AppTextStyles.buttonText.copyWith(
                      color: palette.text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// "I have sent it" — the note that puts a pending row in front of the
/// founder. Never a payment confirmation.
class _ConfirmBlock extends StatelessWidget {
  const _ConfirmBlock({
    required this.controller,
    required this.busy,
    required this.onConfirm,
  });

  final TextEditingController controller;
  final bool busy;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Already sent it?',
          style: AppTextStyles.titleMedium.copyWith(
            color: palette.text,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Let us know and we will match it against the line. The bar moves '
          'once the transfer is confirmed, not before.',
          style: AppTextStyles.bodySmall.copyWith(
            color: palette.textMuted,
            height: 1.5,
          ),
        ),
        const SizedBox(height: AppSpace.md),
        TextField(
          controller: controller,
          maxLength: 200,
          style: AppTextStyles.bodyMedium.copyWith(color: palette.text),
          decoration: InputDecoration(
            filled: true,
            fillColor: palette.inputFill,
            counterText: '',
            hintText: 'EcoCash reference (optional)',
            hintStyle:
                AppTextStyles.bodyMedium.copyWith(color: palette.textMuted),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.button),
              borderSide: BorderSide(color: palette.divider),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.button),
              borderSide: BorderSide(color: palette.divider),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.button),
              borderSide: const BorderSide(color: AppColors.primaryBlue),
            ),
          ),
        ),
        const SizedBox(height: AppSpace.sm),
        PrimaryGradientButton(
          label: 'I have sent my contribution',
          icon: Icons.favorite_rounded,
          busy: busy,
          onTap: busy ? null : onConfirm,
        ),
      ],
    );
  }
}

/// WhatsApp or email, for anyone who cannot use EcoCash. Reuses the app's
/// existing support contacts rather than introducing a second pair that
/// could drift out of sync.
class _ArrangeSheet extends StatelessWidget {
  const _ArrangeSheet({required this.message});
  final String message;

  Future<void> _whatsApp() async {
    final uri = Uri.parse(
      'https://wa.me/$kSupportWhatsApp?text=${Uri.encodeComponent(message)}',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _email() async {
    final uri = Uri.parse(
      'mailto:$kSupportEmail'
      '?subject=${Uri.encodeComponent("iPhone fundraiser")}'
      '&body=${Uri.encodeComponent(message)}',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: palette.sheet,
          borderRadius: AppRadius.sheetTop,
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
            const SizedBox(height: 18),
            Text(
              'Let us sort it out together',
              style: AppTextStyles.headlineSmall
                  .copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              'Message us and we will find a way that works where you are — '
              'bank transfer, another mobile wallet, or something else.',
              style:
                  AppTextStyles.bodyMedium.copyWith(color: palette.textMuted),
            ),
            const SizedBox(height: 18),
            _ArrangeTile(
              icon: Icons.chat_rounded,
              iconColor: AppColors.successGreen,
              title: 'WhatsApp us',
              subtitle: '+$kSupportWhatsApp',
              onTap: () {
                Navigator.pop(context);
                _whatsApp();
              },
            ),
            const SizedBox(height: 10),
            _ArrangeTile(
              icon: Icons.mail_outline_rounded,
              iconColor: AppColors.primaryBlue,
              title: 'Email us',
              subtitle: kSupportEmail,
              onTap: () {
                Navigator.pop(context);
                _email();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ArrangeTile extends StatelessWidget {
  const _ArrangeTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Pressable(
      onTap: onTap,
      pressedScale: 0.98,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: palette.card,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: palette.divider),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTextStyles.titleMedium.copyWith(
                      color: palette.text,
                      fontWeight: FontWeight.w700,
                      fontSize: 14.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: palette.textMuted,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: palette.textMuted,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

/// The sentence that keeps this a donation rather than a purchase. It must
/// stay true — see the class doc at the top of this file.
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
          Icon(Icons.info_outline_rounded, size: 17, color: palette.textMuted),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Text(
              'Contributing is entirely optional. Every feature of Adventist '
              'Super App stays free and fully available whether or not you '
              'give — a contribution unlocks nothing, earns no badge, and is '
              'separate from Premium, so it does not remove ads. Money is '
              'sent directly through EcoCash, outside the app, to the account '
              'named above, and only counts toward the total once we have '
              'confirmed it arrived. Adventist Super App is not a registered '
              'charity, so a contribution is not a tax-deductible donation '
              'and is not tithe — give your tithe to your local church.',
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
