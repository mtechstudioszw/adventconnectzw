import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/seller_model.dart';
import '../../services/seller_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

/// Super-admin queue of pending seller applications. Each row gives
/// the admin enough context to make a call (business name, contact,
/// description, photos, who applied) and surfaces Approve / Reject
/// actions backed by the patch_031 RPCs.
class SellerApprovalsScreen extends StatefulWidget {
  const SellerApprovalsScreen({super.key});

  @override
  State<SellerApprovalsScreen> createState() => _SellerApprovalsScreenState();
}

class _SellerApprovalsScreenState extends State<SellerApprovalsScreen> {
  bool _loading = true;
  String? _error;
  List<Seller> _pending = const [];
  final Set<String> _busyIds = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await SellerService.fetchPendingSellers();
      if (!mounted) return;
      setState(() {
        _pending = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _friendly(e);
      });
    }
  }

  String _friendly(Object error) {
    final raw = error.toString();
    if (raw.contains('Only super admins')) {
      return 'Only super admins can review pending sellers.';
    }
    return 'Could not load pending sellers. Pull to retry.';
  }

  Future<void> _approve(Seller seller) async {
    if (_busyIds.contains(seller.id)) return;
    setState(() => _busyIds.add(seller.id));
    try {
      await SellerService.approveSeller(seller.id);
      if (!mounted) return;
      setState(() => _pending.removeWhere((s) => s.id == seller.id));
      _showSnack('Approved · ${seller.businessName}', AppColors.successGreen);
    } catch (e) {
      if (!mounted) return;
      _showSnack(_friendly(e), AppColors.red);
    } finally {
      if (mounted) setState(() => _busyIds.remove(seller.id));
    }
  }

  Future<void> _reject(Seller seller) async {
    final reason = await _askReason(seller);
    if (reason == null) return;
    if (_busyIds.contains(seller.id)) return;
    setState(() => _busyIds.add(seller.id));
    try {
      await SellerService.rejectSeller(seller.id, reason: reason);
      if (!mounted) return;
      setState(() => _pending.removeWhere((s) => s.id == seller.id));
      _showSnack('Rejected · ${seller.businessName}', AppColors.red);
    } catch (e) {
      if (!mounted) return;
      _showSnack(_friendly(e), AppColors.red);
    } finally {
      if (mounted) setState(() => _busyIds.remove(seller.id));
    }
  }

  Future<String?> _askReason(Seller seller) async {
    // Previously this method owned the TextEditingController and
    // disposed it after showDialog returned. That triggered the
    // `_dependents.isEmpty` framework assertion intermittently: the
    // TextField widget hadn't finished detaching from the controller
    // by the time `.dispose()` ran in the parent's async frame.
    // Moving controller ownership into the dialog's own StatefulWidget
    // (whose dispose runs AFTER its TextField is removed from the
    // tree) is the standard fix and removes the race entirely.
    return showDialog<String?>(
      context: context,
      builder: (ctx) => _RejectReasonDialog(
        seller: seller,
        isFinal: seller.isFinalReviewPending,
      ),
    );
  }

  void _showSnack(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: color,
        content: Text(
          message,
          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightGrey,
      body: RefreshIndicator(
        color: AppColors.primaryBlue,
        onRefresh: _load,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              _buildHero(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                child: _buildBody(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 80),
        child: Center(
          child: CircularProgressIndicator(color: AppColors.primaryBlue),
        ),
      );
    }
    if (_error != null) {
      return _ErrorCard(message: _error!);
    }
    if (_pending.isEmpty) {
      return _EmptyCard();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${_pending.length} pending ${_pending.length == 1 ? 'application' : 'applications'}',
          style: AppTextStyles.bodySmall.copyWith(
            color: const Color.fromRGBO(26, 26, 46, 0.6),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        for (final seller in _pending)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _PendingCard(
              seller: seller,
              busy: _busyIds.contains(seller.id),
              onApprove: () => _approve(seller),
              onReject: () => _reject(seller),
            ),
          ),
      ],
    );
  }

  Widget _buildHero() {
    return ClipPath(
      clipper: _HeroClipper(),
      child: Container(
        width: double.infinity,
        decoration: const BoxDecoration(gradient: AppColors.appBarGradient),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 36),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _CircleIconButton(
                      icon: Icons.arrow_back_ios_new,
                      onTap: () => context.canPop()
                          ? context.pop()
                          : context.goNamed('settings'),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SUPER ADMIN',
                        style: AppTextStyles.labelSmall.copyWith(
                          color: AppColors.goldAccent,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.8,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Seller approvals',
                        style: AppTextStyles.displayMedium.copyWith(
                          color: AppColors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Approve or reject new storefronts before they '
                        'appear on the marketplace.',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.white.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
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

class _PendingCard extends StatelessWidget {
  const _PendingCard({
    required this.seller,
    required this.busy,
    required this.onApprove,
    required this.onReject,
  });

  final Seller seller;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final cityLine = [seller.city, seller.province]
        .where((s) => s != null && s.isNotEmpty)
        .join(', ');
    final addressLine = [seller.address, seller.suburb]
        .where((s) => s != null && s.trim().isNotEmpty)
        .join(' · ');
    final photo = seller.profilePhotoUrl;
    final hasPhoto = photo != null && photo.isNotEmpty;
    final cover = seller.coverPhotoUrl;
    final hasCover = cover != null && cover.isNotEmpty;
    final isFinalReview = seller.isFinalReviewPending;
    final attempt = seller.applicationAttempts;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cover photo strip — gives the admin a visual feel for the
          // store before they read the form details.
          AspectRatio(
            aspectRatio: 16 / 7,
            child: hasCover
                ? CachedNetworkImage(
                    imageUrl: cover,
                    fit: BoxFit.cover,
                    errorWidget: (ctx, url, error) =>
                        const _CoverPlaceholder(),
                    placeholder: (ctx, url) => const _CoverPlaceholder(),
                  )
                : const _CoverPlaceholder(),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        gradient:
                            hasPhoto ? null : AppColors.primaryGradient,
                        color: hasPhoto ? AppColors.lightGrey : null,
                        shape: BoxShape.circle,
                        image: hasPhoto
                            ? DecorationImage(
                                image: CachedNetworkImageProvider(photo),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: hasPhoto
                          ? null
                          : const Icon(
                              Icons.storefront,
                              color: AppColors.white,
                              size: 26,
                            ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            seller.businessName,
                            style: AppTextStyles.titleMedium.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            SellerCategory.labelFor(seller.category),
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.primaryBlue,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _AttemptBadge(
                      attempt: attempt,
                      isFinal: isFinalReview,
                    ),
                  ],
                ),
                if (isFinalReview) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.red.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.red.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.gavel_outlined,
                          color: AppColors.red,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Final review — a rejection here permanently blocks future applications.',
                            style: AppTextStyles.labelSmall.copyWith(
                              color: AppColors.red,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (cityLine.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _MetaRow(
                    icon: Icons.location_on_outlined,
                    text: cityLine,
                  ),
                ],
                if (addressLine.isNotEmpty)
                  _MetaRow(
                    icon: Icons.home_outlined,
                    text: addressLine,
                  ),
                if ((seller.contactName ?? '').isNotEmpty)
                  _MetaRow(
                    icon: Icons.person_outline,
                    text: 'Contact: ${seller.contactName}',
                  ),
                if ((seller.whatsapp ?? '').isNotEmpty)
                  _MetaRow(
                    icon: Icons.chat_outlined,
                    text: 'WhatsApp ${seller.whatsapp}',
                  ),
                if ((seller.phone).isNotEmpty)
                  _MetaRow(
                    icon: Icons.phone_outlined,
                    text: seller.phone,
                  ),
                if ((seller.paymentMethods ?? '').isNotEmpty)
                  _MetaRow(
                    icon: Icons.payments_outlined,
                    text: 'Payment: ${seller.paymentMethods}',
                  ),
                if (seller.offersDelivery)
                  _MetaRow(
                    icon: Icons.local_shipping_outlined,
                    text: [
                      'Delivers',
                      if ((seller.deliveryArea ?? '').isNotEmpty)
                        'to ${seller.deliveryArea}',
                      if ((seller.deliveryFee ?? '').isNotEmpty)
                        '(${seller.deliveryFee})',
                    ].join(' '),
                  ),
                if (seller.observesSabbath)
                  _MetaRow(
                    icon: Icons.bedtime_outlined,
                    text: (seller.sabbathNoticeText ?? '').isNotEmpty
                        ? 'Sabbath: ${seller.sabbathNoticeText}'
                        : 'Observes the Sabbath',
                  ),
                if ((seller.description ?? '').isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.lightGrey,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      seller.description!,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: const Color.fromRGBO(26, 26, 46, 0.85),
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: busy ? null : onReject,
                        icon: const Icon(Icons.close, size: 18),
                        label:
                            Text('Reject', style: AppTextStyles.labelLarge),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.red,
                          side: const BorderSide(color: AppColors.red),
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: busy ? null : onApprove,
                        icon: busy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  color: AppColors.white,
                                  strokeWidth: 2.2,
                                ),
                              )
                            : const Icon(Icons.check, size: 18),
                        label: Text(
                          busy ? 'Working' : 'Approve',
                          style: AppTextStyles.labelLarge,
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.successGreen,
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CoverPlaceholder extends StatelessWidget {
  const _CoverPlaceholder();
  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(gradient: AppColors.appBarGradient),
      child: Center(
        child: Icon(
          Icons.image_outlined,
          color: AppColors.white,
          size: 32,
        ),
      ),
    );
  }
}

class _AttemptBadge extends StatelessWidget {
  const _AttemptBadge({required this.attempt, required this.isFinal});
  final int attempt;
  final bool isFinal;

  @override
  Widget build(BuildContext context) {
    final color = isFinal ? AppColors.red : AppColors.primaryBlue;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Text(
        isFinal ? 'FINAL · #$attempt/3' : '#$attempt/3',
        style: AppTextStyles.labelSmall.copyWith(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

/// Stateful dialog that owns its own TextEditingController so the
/// controller is disposed AFTER its TextField is detached from the
/// tree — the parent _askReason used to dispose immediately after
/// `await showDialog(...)`, which triggered `_dependents.isEmpty`
/// when the dialog's children hadn't finished unmounting.
class _RejectReasonDialog extends StatefulWidget {
  const _RejectReasonDialog({
    required this.seller,
    required this.isFinal,
  });

  final Seller seller;
  final bool isFinal;

  @override
  State<_RejectReasonDialog> createState() => _RejectReasonDialogState();
}

class _RejectReasonDialogState extends State<_RejectReasonDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      title: Text(
        widget.isFinal
            ? 'Final-review reject ${widget.seller.businessName}?'
            : 'Reject ${widget.seller.businessName}?',
        style: AppTextStyles.headlineSmall,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.isFinal) ...[
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.red.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.red.withValues(alpha: 0.30),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: AppColors.red,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This is the seller\'s third attempt. A rejection here permanently blocks them from re-applying.',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.red,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _controller,
            maxLines: 4,
            maxLength: 240,
            decoration: InputDecoration(
              hintText: 'Reason (optional, shown to the applicant)',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: Text(
            'Cancel',
            style:
                AppTextStyles.labelMedium.copyWith(color: AppColors.textDark),
          ),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.pop(context, _controller.text.trim()),
          style: FilledButton.styleFrom(backgroundColor: AppColors.red),
          child: Text(
            widget.isFinal ? 'Reject permanently' : 'Reject',
            style: AppTextStyles.labelLarge,
          ),
        ),
      ],
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(icon,
              size: 14, color: const Color.fromRGBO(26, 26, 46, 0.55)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.bodySmall.copyWith(
                color: const Color.fromRGBO(26, 26, 46, 0.7),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.successGreen.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.inbox_outlined,
              color: AppColors.successGreen,
              size: 38,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No pending sellers',
            style: AppTextStyles.headlineMedium.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'New storefronts will show up here for you to approve.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(
              color: const Color.fromRGBO(26, 26, 46, 0.6),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.cloud_off_outlined,
            size: 48,
            color: Color.fromRGBO(26, 26, 46, 0.4),
          ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(
              color: const Color.fromRGBO(26, 26, 46, 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height - 28);
    path.quadraticBezierTo(
      size.width / 2,
      size.height,
      size.width,
      size.height - 28,
    );
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.white.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14),
            border:
                Border.all(color: AppColors.white.withValues(alpha: 0.10)),
          ),
          child: Icon(icon, color: AppColors.white, size: 18),
        ),
      ),
    );
  }
}
