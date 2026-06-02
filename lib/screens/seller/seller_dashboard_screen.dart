import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/product_model.dart';
import '../../models/seller_model.dart';
import '../../services/seller_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/cached_image.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Entry point into the seller flow. Three states:
///   * no seller row → CTA to set up the store
///   * pending / rejected → banner explaining state, no dashboard
///   * approved → stats + product preview + management actions
class SellerDashboardScreen extends StatefulWidget {
  const SellerDashboardScreen({super.key});

  @override
  State<SellerDashboardScreen> createState() => _SellerDashboardScreenState();
}

class _SellerDashboardScreenState extends State<SellerDashboardScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance;
  late final Animation<double> _fade;
  late final Animation<double> _slide;

  Seller? _seller;
  List<Product> _products = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();
    _fade = CurvedAnimation(parent: _entrance, curve: Curves.easeOut);
    _slide = Tween<double>(begin: 12, end: 0).animate(
      CurvedAnimation(parent: _entrance, curve: Curves.easeOut),
    );
    _bootstrap();
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final seller = await SellerService.fetchMySellerProfile();
      List<Product> products = const [];
      if (seller != null && seller.isApproved) {
        products = await SellerService.fetchMyProducts();
      }
      if (!mounted) return;
      setState(() {
        _seller = seller;
        _products = products;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load your store. Pull to retry.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.scaffoldBg,
      body: RefreshIndicator(
        color: AppColors.primaryBlue,
        onRefresh: _bootstrap,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              _buildHero(),
              AnimatedBuilder(
                animation: _entrance,
                builder: (context, child) => Opacity(
                  opacity: _fade.value,
                  child: Transform.translate(
                    offset: Offset(0, _slide.value),
                    child: child,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  child: _buildBody(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 80),
        child: Column(
          children: const [
            CircularProgressIndicator(color: AppColors.primaryBlue),
          ],
        ),
      );
    }
    if (_error != null) {
      return _buildErrorState();
    }
    if (_seller == null) {
      return _buildEmptyState();
    }
    if (_seller!.isPending) {
      return _buildPendingState(_seller!);
    }
    if (_seller!.isFinalReviewPending) {
      return _buildFinalReviewState(_seller!);
    }
    if (_seller!.isRejectedFinal) {
      return _buildRejectedFinalState(_seller!);
    }
    if (_seller!.isRejected) {
      return _buildRejectedState(_seller!);
    }
    return _buildApprovedDashboard(_seller!);
  }

  Widget _buildErrorState() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Icon(
            Icons.cloud_off_outlined,
            size: 48,
            color: context.palette.textMuted,
          ),
          const SizedBox(height: 12),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(
              color: context.palette.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: context.palette.card,
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
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.storefront,
              color: AppColors.white,
              size: 44,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Become a seller',
            textAlign: TextAlign.center,
            style: AppTextStyles.headlineMedium.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'List products to the SDA community across Zimbabwe. We review applications within 1–3 days.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(
              color: context.palette.textMuted,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 22),
          _GradientButton(
            label: 'Start setup',
            icon: Icons.arrow_forward,
            onTap: () async {
              // Self-serve flow: route through the Code of Conduct
              // gate first so the user agrees before we let them
              // open a storefront (patch_022 enforces this at the
              // DB layer too).
              await context.pushNamed('marketplace_guidelines');
              if (mounted) _bootstrap();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPendingState(Seller seller) {
    return Column(
      children: [
        _StatusBanner(
          tone: _BannerTone.info,
          icon: Icons.hourglass_top,
          title: 'Awaiting admin approval',
          message:
              'An admin is reviewing your store profile. You\'ll get a '
              'notification the moment it\'s approved — usually within '
              'a day or two. Once approved you can list products without '
              'further per-product reviews.',
        ),
        const SizedBox(height: 16),
        _StoreSummaryCard(seller: seller),
        const SizedBox(height: 16),
        _ChecklistCard(
          items: const [
            'Photo and clear business name',
            'Province + city set',
            'Phone or WhatsApp reachable',
          ],
        ),
      ],
    );
  }

  Widget _buildRejectedState(Seller seller) {
    final attemptsLeft = seller.attemptsRemaining;
    final isLastChance = attemptsLeft <= 1;
    return Column(
      children: [
        _StatusBanner(
          tone: _BannerTone.danger,
          icon: Icons.report_problem_outlined,
          title: isLastChance
              ? 'Application not approved — final attempt remaining'
              : 'Application not approved',
          message: seller.rejectionReason?.trim().isNotEmpty == true
              ? seller.rejectionReason!
              : 'Reach out via support if you\'d like more detail. Update your store details below and resubmit — '
                  '${attemptsLeft == 1 ? 'this is your last chance' : '$attemptsLeft attempts remaining'} '
                  'before marketplace access is closed.',
        ),
        const SizedBox(height: 16),
        _StoreSummaryCard(seller: seller),
        const SizedBox(height: 16),
        _GradientButton(
          label: 'Edit & resubmit',
          icon: Icons.edit_outlined,
          onTap: () async {
            await context.pushNamed('edit_store', extra: seller);
            if (mounted) _bootstrap();
          },
        ),
      ],
    );
  }

  Widget _buildFinalReviewState(Seller seller) {
    return Column(
      children: [
        _StatusBanner(
          tone: _BannerTone.info,
          icon: Icons.gavel_outlined,
          title: 'Final review in progress',
          message:
              'This is your third and final application. An admin is reviewing '
              'your updated details — you\'ll get a notification when there\'s '
              'a decision.',
        ),
        const SizedBox(height: 16),
        _StoreSummaryCard(seller: seller),
      ],
    );
  }

  Widget _buildRejectedFinalState(Seller seller) {
    return Column(
      children: [
        _StatusBanner(
          tone: _BannerTone.danger,
          icon: Icons.block_outlined,
          title: 'Marketplace access closed',
          message:
              'Your seller application has been rejected 3 times. You are no '
              'longer eligible to apply to become a marketplace seller. '
              'Please contact support if you need more information.',
        ),
        const SizedBox(height: 16),
        _StoreSummaryCard(seller: seller),
      ],
    );
  }

  Widget _buildApprovedDashboard(Seller seller) {
    final stats = SellerService.statsFor(_products);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StoreSummaryCard(seller: seller, showStatusChip: true),
        const SizedBox(height: 16),
        _StatsRow(seller: seller, stats: stats),
        const SizedBox(height: 16),
        _QuickActionsCard(
          seller: seller,
          onAdd: () async {
            await context.pushNamed('add_product');
            if (mounted) _bootstrap();
          },
          onManage: () async {
            await context.pushNamed('manage_products');
            if (mounted) _bootstrap();
          },
          onEdit: () async {
            await context.pushNamed('edit_store', extra: seller);
            if (mounted) _bootstrap();
          },
        ),
        const SizedBox(height: 16),
        _RecentProductsSection(products: _products),
        const SizedBox(height: 16),
        if (seller.observesSabbath)
          _SabbathBadge(
            notice: seller.sabbathNoticeText ?? 'Observes the Sabbath.',
          ),
        if (seller.observesSabbath) const SizedBox(height: 16),
        _DangerZoneCard(onDelete: () => _confirmDeleteStore(seller)),
      ],
    );
  }

  Future<void> _confirmDeleteStore(Seller seller) async {
    // Two-step confirm so an accidental tap can't wipe the storefront
    // — destructive + irreversible (every product is dropped too).
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Delete your store?', style: AppTextStyles.headlineSmall),
        content: Text(
          '"${seller.businessName}" and every product you\'ve listed will be '
          'removed from the marketplace. This cannot be undone.',
          style: AppTextStyles.bodyMedium.copyWith(
            color: ctx.palette.text,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style:
                  AppTextStyles.labelMedium.copyWith(color: ctx.palette.text),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            child: Text('Delete store', style: AppTextStyles.labelLarge),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await SellerService.deleteMySellerProfile();
      if (!mounted) return;
      setState(() {
        _seller = null;
        _products = const [];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.successGreen,
          content: Text(
            'Store deleted.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.red,
          content: Text(
            'Could not delete the store. Try again.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    }
  }

  Widget _buildHero() {
    final cover = _seller?.coverPhotoUrl;
    final hasCover = cover != null && cover.isNotEmpty;
    return ClipPath(
      clipper: _HeroClipper(),
      child: Stack(
        children: [
          // Background: cover photo when set, gradient fallback
          Positioned.fill(
            child: hasCover
                ? CachedNetworkImage(
                    imageUrl: cover,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => const DecoratedBox(
                      decoration:
                          BoxDecoration(gradient: AppColors.appBarGradient),
                    ),
                    errorWidget: (context, url, error) => const DecoratedBox(
                      decoration:
                          BoxDecoration(gradient: AppColors.appBarGradient),
                    ),
                  )
                : const DecoratedBox(
                    decoration:
                        BoxDecoration(gradient: AppColors.appBarGradient),
                  ),
          ),
          // Dark overlay so text stays readable over bright photos
          if (hasCover)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.30),
                      Colors.black.withValues(alpha: 0.65),
                    ],
                  ),
                ),
              ),
            ),
          // Hero content
          SizedBox(
            width: double.infinity,
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
                              : context.goNamed('profile'),
                        ),
                        const Spacer(),
                        // Account-mode switching lives on the Profile tab
                        // now — this header keeps just the add-product CTA.
                        if (_seller != null && _seller!.isApproved) ...[
                          _CircleIconButton(
                            icon: Icons.add,
                            onTap: () async {
                              await context.pushNamed('add_product');
                              if (mounted) _bootstrap();
                            },
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 20),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'SELLER DASHBOARD',
                            style: AppTextStyles.labelSmall.copyWith(
                              color: AppColors.white.withValues(alpha: 0.55),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.8,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _seller?.businessName.isNotEmpty == true
                                ? _seller!.businessName
                                : 'Your store',
                            style: AppTextStyles.displayMedium.copyWith(
                              color: AppColors.white,
                              fontSize: 26,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _heroSubtitle(),
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
        ],
      ),
    );
  }

  String _heroSubtitle() {
    if (_seller == null) {
      return 'Open a storefront on the marketplace.';
    }
    if (_seller!.isPending) return 'Application under review.';
    if (_seller!.isFinalReviewPending) return 'Final review in progress.';
    if (_seller!.isRejectedFinal) return 'Marketplace access closed.';
    if (_seller!.isRejected) return 'Application needs your attention.';
    return 'Listings, stats, and store settings in one place.';
  }
}

enum _BannerTone { info, danger, success }

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.tone,
    required this.icon,
    required this.title,
    required this.message,
  });

  final _BannerTone tone;
  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final color = switch (tone) {
      _BannerTone.info => AppColors.primaryBlue,
      _BannerTone.danger => AppColors.red,
      _BannerTone.success => AppColors.successGreen,
    };
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.titleMedium.copyWith(
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: context.palette.text,
                    height: 1.5,
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

class _StoreSummaryCard extends StatelessWidget {
  const _StoreSummaryCard({
    required this.seller,
    this.showStatusChip = false,
  });

  final Seller seller;
  final bool showStatusChip;

  @override
  Widget build(BuildContext context) {
    final photo = seller.profilePhotoUrl;
    final hasPhoto = photo != null && photo.isNotEmpty;
    final cityLine = [seller.city, seller.province]
        .where((s) => s != null && s.isNotEmpty)
        .join(', ');
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              gradient: hasPhoto ? null : AppColors.primaryGradient,
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
                    size: 28,
                  ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        seller.businessName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.titleMedium.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (seller.verified || seller.sdaVerified) ...[
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.verified,
                        color: AppColors.goldAccent,
                        size: 16,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  SellerCategory.labelFor(seller.category),
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.primaryBlue,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (cityLine.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    cityLine,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: context.palette.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (showStatusChip) _StatusChip(status: seller.status),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'approved' => AppColors.successGreen,
      'pending' => AppColors.primaryBlue,
      'rejected' => AppColors.red,
      _ => AppColors.primaryBlue,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.toUpperCase(),
        style: AppTextStyles.labelSmall.copyWith(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.seller, required this.stats});

  final Seller seller;
  final SellerStats stats;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          _Stat(value: '${stats.available}', label: 'LIVE'),
          _v(),
          _Stat(value: '${stats.hidden}', label: 'HIDDEN'),
          _v(),
          _Stat(
            value: seller.rating > 0 ? seller.rating.toStringAsFixed(1) : '—',
            label: 'RATING',
            sub: seller.ratingCount > 0 ? '${seller.ratingCount} ratings' : null,
          ),
        ],
      ),
    );
  }

  Widget _v() => Builder(
        builder: (context) => Container(
          width: 1,
          height: 36,
          color: context.palette.divider,
        ),
      );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, this.sub});

  final String value;
  final String label;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: AppTextStyles.headlineMedium.copyWith(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppColors.primaryBlue,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: AppTextStyles.labelSmall.copyWith(
              color: context.palette.textMuted,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
          if (sub != null) ...[
            const SizedBox(height: 2),
            Text(
              sub!,
              style: AppTextStyles.bodySmall.copyWith(
                color: context.palette.textMuted,
                fontSize: 10.5,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _QuickActionsCard extends StatelessWidget {
  const _QuickActionsCard({
    required this.seller,
    required this.onAdd,
    required this.onManage,
    required this.onEdit,
  });

  final Seller seller;
  final VoidCallback onAdd;
  final VoidCallback onManage;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.palette.card,
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'QUICK ACTIONS',
            style: AppTextStyles.labelSmall.copyWith(
              color: context.palette.textMuted,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          _ActionRow(
            icon: Icons.add_box_outlined,
            title: 'Add a new product',
            subtitle: 'Photos, price and a description.',
            onTap: onAdd,
          ),
          const _Divider(),
          _ActionRow(
            icon: Icons.inventory_2_outlined,
            title: 'Manage products',
            subtitle: 'Toggle visibility, edit, or delete.',
            onTap: onManage,
          ),
          const _Divider(),
          _ActionRow(
            icon: Icons.edit_outlined,
            title: 'Edit store profile',
            subtitle: 'Update contact, delivery, Sabbath hours.',
            onTap: onEdit,
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: AppColors.primaryBlue, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTextStyles.titleSmall.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: context.palette.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: context.palette.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      color: context.palette.divider,
    );
  }
}

class _RecentProductsSection extends StatelessWidget {
  const _RecentProductsSection({required this.products});

  final List<Product> products;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.palette.card,
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'RECENT PRODUCTS',
                style: AppTextStyles.labelSmall.copyWith(
                  color: context.palette.textMuted,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                ),
              ),
              const Spacer(),
              if (products.isNotEmpty)
                TextButton(
                  onPressed: () => context.pushNamed('manage_products'),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    'See all',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.primaryBlue,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (products.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Column(
                children: [
                  Icon(
                    Icons.inventory_2_outlined,
                    size: 36,
                    color: AppColors.primaryBlue.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'No products yet',
                    style: AppTextStyles.titleSmall.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Tap the + button to list your first product.',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: context.palette.textMuted,
                    ),
                  ),
                ],
              ),
            )
          else
            ...products.take(3).map(
                  (p) => _ProductPreviewRow(product: p),
                ),
        ],
      ),
    );
  }
}

class _ProductPreviewRow extends StatelessWidget {
  const _ProductPreviewRow({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final firstImage = product.firstImage;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 52,
              height: 52,
              color: context.palette.cardMuted,
              child: firstImage.isNotEmpty
                  ? CachedImage(
                      firstImage,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Icon(
                        Icons.image_not_supported_outlined,
                        color: context.palette.textMuted,
                      ),
                    )
                  : Icon(
                      Icons.image_outlined,
                      color: context.palette.textMuted,
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.titleSmall.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  product.formatPrice(),
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.primaryBlue,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          _AvailabilityChip(available: product.isAvailable),
        ],
      ),
    );
  }
}

class _AvailabilityChip extends StatelessWidget {
  const _AvailabilityChip({required this.available});
  final bool available;

  @override
  Widget build(BuildContext context) {
    final color = available ? AppColors.successGreen : context.palette.text;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: available ? 0.12 : 0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        available ? 'LIVE' : 'HIDDEN',
        style: AppTextStyles.labelSmall.copyWith(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _SabbathBadge extends StatelessWidget {
  const _SabbathBadge({required this.notice});

  final String notice;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.goldAccent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.goldAccent.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.brightness_3,
            color: AppColors.goldAccent,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              notice,
              style: AppTextStyles.bodySmall.copyWith(
                color: context.palette.text,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChecklistCard extends StatelessWidget {
  const _ChecklistCard({required this.items});
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.palette.card,
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'WHILE YOU WAIT',
            style: AppTextStyles.labelSmall.copyWith(
              color: context.palette.textMuted,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Reviewers check for:',
            style: AppTextStyles.titleSmall.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle_outline,
                    color: AppColors.primaryBlue,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: context.palette.text,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GradientButton extends StatelessWidget {
  const _GradientButton({
    required this.label,
    required this.onTap,
    this.icon,
  });

  final String label;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryBlue.withValues(alpha: 0.30),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: AppTextStyles.buttonText.copyWith(
                    fontSize: 15,
                    letterSpacing: 0.4,
                  ),
                ),
                if (icon != null) ...[
                  const SizedBox(width: 8),
                  Icon(icon, color: AppColors.white, size: 18),
                ],
              ],
            ),
          ),
        ),
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
            border: Border.all(color: AppColors.white.withValues(alpha: 0.10)),
          ),
          child: Icon(icon, color: AppColors.white, size: 18),
        ),
      ),
    );
  }
}

/// Destructive "danger zone" footer for the approved dashboard. Lives
/// below the recent-products card so a seller has to scroll past
/// everything else before they reach Delete — and the row uses the
/// outlined red treatment so it visually reads as "stop, are you sure"
/// before the confirm dialog also asks.
class _DangerZoneCard extends StatelessWidget {
  const _DangerZoneCard({required this.onDelete});

  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.red.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'DANGER ZONE',
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.red,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Delete this store and every product you\'ve listed. This '
            'cannot be undone.',
            style: AppTextStyles.bodySmall.copyWith(
              color: context.palette.textMuted,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline, size: 18),
            label: Text('Delete store', style: AppTextStyles.labelLarge),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.red,
              side: const BorderSide(color: AppColors.red),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
