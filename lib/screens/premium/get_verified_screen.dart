import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/billing/premium_tier.dart';
import '../../services/billing/verified_plan_service.dart';
import '../../services/premium_service.dart';
import '../../services/verification_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/motion/brand_spinner.dart';
import '../../widgets/screen_shell.dart';
import '../../widgets/verified_tick.dart';

/// Apply for the gold tick (owner, 29 Oct 2026: "the first premium feature
/// … getting a verified golden tick on your account").
///
/// The tick means "this is really them" — a pastor, a choir, a business
/// people can trust — so it takes an ID check, not just a payment. The
/// member sends their legal name, a photo of their ID and a selfie; a super
/// admin compares them (Admin → Verification) and the tick appears while
/// they hold any paid level. Paying alone never shows it, and an approval
/// alone doesn't either.
///
/// Android only for now: hidden on iOS with every other payment entry
/// point (kHidePayments), and the route redirects there.
///
/// With [pageId] the same flow verifies a Page the member created; that
/// tick needs Business.
class GetVerifiedScreen extends StatefulWidget {
  const GetVerifiedScreen({super.key, this.pageId, this.pageName});

  final String? pageId;
  final String? pageName;

  @override
  State<GetVerifiedScreen> createState() => _GetVerifiedScreenState();
}

class _GetVerifiedScreenState extends State<GetVerifiedScreen> {
  final _name = TextEditingController();
  final _picker = ImagePicker();

  VerificationRequest? _request;
  bool _loading = true;
  bool _sending = false;
  bool _consent = false;
  bool _reapplying = false;
  VerifyCategory _category = VerifyCategory.member;
  Uint8List? _idPhoto;
  Uint8List? _selfie;
  String? _error;

  bool get _isPage => widget.pageId != null;

  PremiumTier get _neededTier =>
      _isPage ? PremiumTier.business : PremiumTier.plus;

  @override
  void initState() {
    super.initState();
    if (_isPage) _category = VerifyCategory.ministry;
    _load();
    // The $1 plan's price, in the member's own currency, for the copy.
    if (!_isPage) {
      VerifiedPlanService.loadOffer().then((_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final r = await VerificationService.mine(pageId: widget.pageId);
    if (!mounted) return;
    setState(() {
      _request = r;
      _loading = false;
    });
  }

  Future<void> _pick({required bool selfie}) async {
    final source = selfie
        ? ImageSource.camera
        : await _askSource();
    if (source == null) return;
    try {
      final file = await _picker.pickImage(
        source: source,
        preferredCameraDevice: selfie ? CameraDevice.front : CameraDevice.rear,
        // Readable, not huge: enough for a reviewer to read an ID number.
        maxWidth: 1600,
        imageQuality: 82,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() => selfie ? _selfie = bytes : _idPhoto = bytes);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = "Couldn't open the camera or gallery.");
    }
  }

  Future<ImageSource?> _askSource() => showModalBottomSheet<ImageSource>(
      useRootNavigator: true,
    context: context,
    backgroundColor: context.palette.scaffoldBg,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Take a photo'),
            onTap: () => Navigator.pop(context, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose from gallery'),
            onTap: () => Navigator.pop(context, ImageSource.gallery),
          ),
        ],
      ),
    ),
  );

  bool get _canSend =>
      !_sending &&
      _name.text.trim().length >= 2 &&
      _idPhoto != null &&
      _selfie != null &&
      _consent;

  Future<void> _send() async {
    if (!_canSend) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final r = await VerificationService.apply(
        legalName: _name.text,
        category: _category,
        idPhoto: _idPhoto!,
        selfie: _selfie!,
        pageId: widget.pageId,
      );
      if (!mounted) return;
      setState(() {
        _request = r;
        _sending = false;
        _reapplying = false;
        _idPhoto = null;
        _selfie = null;
      });
    } on VerificationException catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = e.message;
      });
    }
  }

  Future<void> _withdraw() async {
    final r = _request;
    if (r == null) return;
    try {
      await VerificationService.withdraw(r);
      if (!mounted) return;
      setState(() => _request = null);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = "Couldn't withdraw it. Try again.");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          ScreenHero(
            title: _isPage ? 'Verify your Page' : 'Get verified',
            tagline: 'Gold tick',
            subtitle: _isPage
                ? 'Show members ${widget.pageName ?? 'this Page'} is the real one.'
                : 'Show people it is really you.',
            fallbackRoute: 'premium',
          ),
          Expanded(
            child: _loading
                ? const Center(child: BrandSpinner(size: 30))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    children: [
                      _WhatItMeans(isPage: _isPage, tier: _neededTier),
                      const SizedBox(height: 16),
                      if (_request != null && !_reapplying)
                        // Rebuilds the moment a Verified plan lands, so
                        // "waiting for a plan" turns into "you are verified".
                        ValueListenableBuilder<bool>(
                          valueListenable: PremiumService.verifiedPlan,
                          builder: (context, _, _) => _StatusCard(
                            request: _request!,
                            tier: _neededTier,
                            onWithdraw: _withdraw,
                            onReapply: () =>
                                setState(() => _reapplying = true),
                          ),
                        )
                      else
                        _form(context),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        ErrorBanner(message: _error!),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _form(BuildContext context) {
    final palette = context.palette;
    return ScreenCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _isPage ? 'Your details (Page creator)' : 'Your details',
            style: AppTextStyles.titleSmall.copyWith(color: palette.text),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('verify-legal-name'),
            controller: _name,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Full name, exactly as on your ID',
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _isPage ? 'What is the Page?' : 'Which describes you?',
            style: AppTextStyles.bodySmall.copyWith(color: palette.textMuted),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in VerifyCategory.values)
                ChoiceChip(
                  label: Text(c.label),
                  selected: _category == c,
                  onSelected: (_) => setState(() => _category = c),
                ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _PhotoSlot(
                  key: const Key('verify-id-photo'),
                  label: 'Photo of your ID',
                  hint: 'National ID, passport or licence',
                  icon: Icons.badge_outlined,
                  bytes: _idPhoto,
                  onTap: () => _pick(selfie: false),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _PhotoSlot(
                  key: const Key('verify-selfie'),
                  label: 'A selfie',
                  hint: 'Face the camera, good light',
                  icon: Icons.face_retouching_natural_outlined,
                  bytes: _selfie,
                  onTap: () => _pick(selfie: true),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          CheckboxListTile(
            key: const Key('verify-consent'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _consent,
            onChanged: (v) => setState(() => _consent = v ?? false),
            title: Text(
              'I agree to my ID and selfie being used only to check who I '
              'am. Only the review team can see them, and they are deleted '
              'as soon as a decision is made.',
              style: AppTextStyles.bodySmall.copyWith(
                color: palette.textMuted,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 10),
          PrimaryGradientButton(
            label: _sending ? 'Sending…' : 'Send for review',
            icon: Icons.verified_outlined,
            busy: _sending,
            onTap: _canSend ? _send : null,
          ),
        ],
      ),
    );
  }
}

class _WhatItMeans extends StatelessWidget {
  const _WhatItMeans({required this.isPage, required this.tier});
  final bool isPage;
  final PremiumTier tier;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return ScreenCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const VerifiedTick(size: 26, leftGap: 0),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'What the gold tick means',
                  style: AppTextStyles.titleSmall.copyWith(color: palette.text),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final line in [
            'We checked an ID — this ${isPage ? 'Page belongs to a real, named person' : 'account is really the person it says'}.',
            'It shows beside ${isPage ? 'the Page' : 'your name'} everywhere: posts, comments, chats and search.',
            isPage
                ? 'It needs ${tier.label} to stay on. If the plan ends, the tick hides until you renew — no need to apply again.'
                : 'It needs the Verified plan (${VerifiedPlanService.priceLabel} a month) or any Premium plan to stay on. If the plan ends, the tick hides until you renew — no need to apply again.',
            'Fake accounts and scams get reported and the tick is removed.',
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 7, right: 8),
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration: const BoxDecoration(
                        color: AppColors.primaryBlue,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      line,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: palette.textMuted,
                        height: 1.4,
                      ),
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

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.request,
    required this.tier,
    required this.onWithdraw,
    required this.onReapply,
  });

  final VerificationRequest request;
  final PremiumTier tier;
  final VoidCallback onWithdraw;
  final VoidCallback onReapply;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    // A member's own tick (tier Plus) also stays on with the $1 Verified
    // plan (patch 309); a Page's needs Business.
    final paying = PremiumService.hasTier(tier) ||
        (tier == PremiumTier.plus && PremiumService.hasVerifiedPlan);
    final (IconData icon, Color tone, String title, String body) =
        switch (request.status) {
          VerifyStatus.pending => (
            Icons.hourglass_top_rounded,
            AppColors.primaryBlue,
            'We are checking your ID',
            'Usually within 3 days. We will send you a notification either '
                'way. Your photos are deleted once we decide.',
          ),
          VerifyStatus.approved when paying => (
            Icons.verified_rounded,
            AppColors.successGreen,
            'You are verified',
            'The gold tick is showing on your account.',
          ),
          VerifyStatus.approved => (
            Icons.verified_outlined,
            AppColors.primaryBlue,
            'Approved — waiting for a plan',
            'Your ID check passed. The tick shows as soon as you have '
                '${tier.label}${tier == PremiumTier.plus ? ' or above' : ''}.',
          ),
          VerifyStatus.rejected => (
            Icons.info_outline_rounded,
            AppColors.red,
            'Not approved this time',
            request.reason ?? 'The details could not be confirmed.',
          ),
          VerifyStatus.revoked => (
            Icons.remove_circle_outline_rounded,
            AppColors.red,
            'Tick removed',
            request.reason ?? 'The tick was removed by the review team.',
          ),
        };
    final reapplyAt = request.canReapplyAt;
    final canReapply = request.status == VerifyStatus.rejected &&
        (reapplyAt == null || DateTime.now().isAfter(reapplyAt));

    return ScreenCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: tone),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: AppTextStyles.titleSmall.copyWith(color: palette.text),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: AppTextStyles.bodySmall.copyWith(
              color: palette.textMuted,
              height: 1.45,
            ),
          ),
          if (request.status == VerifyStatus.rejected && !canReapply &&
              reapplyAt != null) ...[
            const SizedBox(height: 8),
            Text(
              'You can apply again from ${reapplyAt.day}/${reapplyAt.month}/${reapplyAt.year}.',
              style: AppTextStyles.bodySmall.copyWith(color: palette.textMuted),
            ),
          ],
          const SizedBox(height: 14),
          if (request.status == VerifyStatus.approved && !paying) ...[
            if (tier == PremiumTier.plus)
              ValueListenableBuilder<VerifiedPlanFlow>(
                valueListenable: VerifiedPlanService.state,
                builder: (context, flow, _) {
                  final busy = flow == VerifiedPlanFlow.purchasing ||
                      flow == VerifiedPlanFlow.verifying ||
                      flow == VerifiedPlanFlow.loading;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      PrimaryGradientButton(
                        label: busy
                            ? 'One moment…'
                            : 'Turn on my tick · ${VerifiedPlanService.priceLabel}/month',
                        icon: Icons.verified_rounded,
                        onTap: busy ? null : VerifiedPlanService.buy,
                      ),
                      if (VerifiedPlanService.message != null &&
                          (flow == VerifiedPlanFlow.failed ||
                              flow == VerifiedPlanFlow.unavailable ||
                              flow == VerifiedPlanFlow.pendingPayment))
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            VerifiedPlanService.message!,
                            style: AppTextStyles.bodySmall.copyWith(
                              color: context.palette.textMuted,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            TextButton(
              onPressed: () => context.pushNamed('premium'),
              child: Text(
                tier == PremiumTier.plus
                    ? 'Or get it with a Premium plan'
                    : 'See plans',
              ),
            ),
          ],
          if (request.status == VerifyStatus.pending)
            TextButton(
              onPressed: onWithdraw,
              child: const Text('Withdraw my request'),
            ),
          if (canReapply)
            PrimaryGradientButton(label: 'Apply again', onTap: onReapply),
        ],
      ),
    );
  }
}

class _PhotoSlot extends StatelessWidget {
  const _PhotoSlot({
    super.key,
    required this.label,
    required this.hint,
    required this.icon,
    required this.bytes,
    required this.onTap,
  });

  final String label;
  final String hint;
  final IconData icon;
  final Uint8List? bytes;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
        aspectRatio: 1,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: palette.chipBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: bytes != null ? AppColors.primaryBlue : palette.divider,
              width: bytes != null ? 2 : 1,
            ),
          ),
          child: bytes != null
              ? Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.memory(bytes!, fit: BoxFit.cover),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        width: double.infinity,
                        color: Colors.black54,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: const Text(
                          'Tap to change',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                )
              : Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, size: 30, color: palette.brandBlue),
                      const SizedBox(height: 8),
                      Text(
                        label,
                        textAlign: TextAlign.center,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: palette.text,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        hint,
                        textAlign: TextAlign.center,
                        style: AppTextStyles.caption.copyWith(
                          color: palette.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
