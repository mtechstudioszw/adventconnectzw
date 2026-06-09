import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/product_model.dart';
import '../../models/seller_model.dart';
import '../../services/auth_service.dart';
import '../../services/seller_rating_service.dart';
import '../../services/seller_service.dart';
import '../../services/user_profile_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/full_image_viewer.dart';
import '../../widgets/product_card.dart';
import '../../widgets/rate_seller_sheet.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Public storefront view. Buyers reach this from product_details → tap
/// seller, or from any future "Featured sellers" surface. Shows store
/// profile, badges, contact actions and the seller's live products.
///
/// Owner-side concerns (editing, hidden products, dashboard) live in
/// `seller_dashboard_screen` — this screen is read-only.
class SellerProfileScreen extends StatefulWidget {
  const SellerProfileScreen({
    super.key,
    required this.authUserId,
    this.initialSeller,
  });

  /// The seller's auth user id (= products.seller_id). Required because
  /// links land here via a path param.
  final String authUserId;

  /// Optional pre-fetched seller, e.g. passed via go_router `extra`
  /// from product_details. Avoids a fetch flash on first paint.
  final Seller? initialSeller;

  @override
  State<SellerProfileScreen> createState() => _SellerProfileScreenState();
}

class _SellerProfileScreenState extends State<SellerProfileScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance;
  late final Animation<double> _fade;
  late final Animation<double> _slide;

  Seller? _seller;
  PublicUserProfile? _owner;
  List<Product> _products = const [];
  List<SellerRating> _reviews = const [];
  SellerRating? _myReview;
  bool _loading = true;
  String? _error;

  /// True when the signed-in user is a different person from this
  /// seller — only then do we show the "Rate this seller" CTA.
  bool get _canRate {
    final me = AuthService.currentUser;
    final seller = _seller;
    if (me == null || seller == null) return false;
    return seller.authUserId.isNotEmpty && me.id != seller.authUserId;
  }

  @override
  void initState() {
    super.initState();
    _seller = widget.initialSeller;
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
      _loading = _seller == null;
      _error = null;
    });
    try {
      final results = await Future.wait([
        SellerService.fetchSellerByAuthUserId(widget.authUserId),
        SellerService.fetchPublicProductsByAuthUserId(widget.authUserId),
        UserProfileService.fetch(widget.authUserId),
      ]);
      if (!mounted) return;
      final seller = (results[0] as Seller?) ?? _seller;
      setState(() {
        _seller = seller;
        _products = results[1] as List<Product>;
        _owner = results[2] as PublicUserProfile?;
        _loading = false;
      });
      // Ratings depend on the seller row's BIGSERIAL id, so they
      // happen in a second pass once the seller has loaded.
      if (seller != null) _loadRatings(seller.id);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load this seller. Pull to retry.';
      });
    }
  }

  Future<void> _loadRatings(String sellerId) async {
    try {
      final results = await Future.wait([
        SellerRatingService.fetchForSeller(sellerId),
        SellerRatingService.fetchMine(sellerId),
      ]);
      if (!mounted) return;
      setState(() {
        _reviews = results[0] as List<SellerRating>;
        _myReview = results[1] as SellerRating?;
      });
    } catch (_) {
      // Reviews are non-essential — fail silently rather than blocking
      // the profile screen from rendering.
    }
  }

  Future<void> _openRateSheet() async {
    final seller = _seller;
    if (seller == null) return;
    final result = await showModalBottomSheet<SellerRating?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.palette.sheet,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => RateSellerSheet(
        sellerId: seller.id,
        sellerName: seller.businessName,
        existing: _myReview,
      ),
    );
    if (!mounted) return;
    // result==null can mean two things: the sheet was dismissed
    // without saving, OR the user removed their review. We can tell
    // them apart by comparing to _myReview's previous state, but
    // either way a refresh keeps the UI honest.
    await _bootstrap();
    if (result != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.successGreen,
          content: Text(
            'Thanks — your review is live.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    }
  }

  /// Share the seller's storefront via the seller-share Open Graph
  /// Edge Function — gives a thumbnail + title preview on
  /// WhatsApp / Facebook / X, deep-links into the app, falls back
  /// to the GitHub Releases APK.
  Future<void> _shareSeller() async {
    final seller = _seller;
    if (seller == null) return;
    final name = seller.businessName.trim().isNotEmpty
        ? seller.businessName.trim()
        : 'this seller';
    // seller-share Edge Function keys on auth_user_id and emits the
    // store's cover/logo as og:image for a rich preview.
    final shareUrl =
        'https://eqbyvasteolqyktbqbem.functions.supabase.co/seller-share?id=${seller.authUserId}';
    final text = 'Check out $name on Advent Connect ZW marketplace:\n$shareUrl';
    try {
      await Share.share(text, subject: name);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not open the share sheet.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    }
  }

  Future<void> _openWhatsApp(String number) async {
    final digits = number.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return;
    final uri = Uri.parse('https://wa.me/$digits');
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) throw Exception('launch failed');
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: number));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.darkNavy,
          content: Text(
            'WhatsApp not installed. Number copied: $number',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    }
  }

  Future<void> _callPhone(String number) async {
    final cleaned = number.replaceAll(RegExp(r'[^\d+]'), '');
    if (cleaned.isEmpty) return;
    final uri = Uri.parse('tel:$cleaned');
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) throw Exception('launch failed');
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: number));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.darkNavy,
          content: Text(
            'Could not place call. Number copied: $number',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    }
  }

  void _showReport() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.palette.sheet,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _ReportSheet(
        sellerName: _seller?.businessName ?? 'this seller',
        onSubmit: (reason) async {
          Navigator.pop(ctx);
          await _sendReportToAdmin(reason);
        },
      ),
    );
  }

  /// Reports route to the admin's WhatsApp (with email fallback) until
  /// the admin dashboard ships. The pre-filled message includes seller
  /// name + reason + reporter id so we can act on it from the inbox.
  Future<void> _sendReportToAdmin(String reason) async {
    final seller = _seller;
    if (seller == null) return;
    final me = AuthService.currentUser;
    final reporterId = me?.id ?? 'anonymous';
    final body =
        'Report: ${seller.businessName}\nReason: $reason\nSeller id: ${seller.authUserId}\nReporter: $reporterId';

    const adminPhone = '263778092494';
    const adminEmail = 'tanatswamichaelmikuwa@gmail.com';

    final waUri =
        Uri.parse('https://wa.me/$adminPhone?text=${Uri.encodeComponent(body)}');
    try {
      final ok = await launchUrl(waUri, mode: LaunchMode.externalApplication);
      if (ok) return;
    } catch (_) {}

    final mailUri = Uri(
      scheme: 'mailto',
      path: adminEmail,
      queryParameters: {
        'subject': 'Marketplace report: ${seller.businessName}',
        'body': body,
      },
    );
    try {
      final ok = await launchUrl(mailUri, mode: LaunchMode.externalApplication);
      if (ok) return;
    } catch (_) {}

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.darkNavy,
        content: Text(
          'Could not open WhatsApp or email. Reach us at +263 778 092 494.',
          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.scaffoldBg,
      body: RefreshIndicator(
        color: AppColors.primaryBlue,
        onRefresh: _bootstrap,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _seller == null) {
      return Stack(
        children: [
          _buildHero(),
          const Positioned.fill(
            child: Center(
              child: CircularProgressIndicator(color: AppColors.primaryBlue),
            ),
          ),
        ],
      );
    }
    if (_seller == null) {
      return SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          children: [
            _buildHero(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
              child: _ErrorCard(
                message: _error ?? 'Seller not found.',
              ),
            ),
          ],
        ),
      );
    }
    final seller = _seller!;
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(child: _buildHero()),
        SliverToBoxAdapter(
          child: AnimatedBuilder(
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _IdentityCard(seller: seller, productCount: _products.length),
                  if (_owner != null) ...[
                    const SizedBox(height: 12),
                    _OwnerBadge(
                      owner: _owner!,
                      fallbackName: seller.contactName,
                      onTap: () => context.pushNamed(
                        'user_profile',
                        pathParameters: {'userId': _owner!.id},
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  _ContactRow(
                    seller: seller,
                    onWhatsApp: () => _openWhatsApp(
                      (seller.whatsapp?.trim().isNotEmpty == true
                              ? seller.whatsapp
                              : seller.phone)!,
                    ),
                    onCall: () => _callPhone(seller.phone),
                    onMessage: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'In-app messaging opens once you start a conversation from a product.',
                            style: AppTextStyles.bodyMedium
                                .copyWith(color: AppColors.white),
                          ),
                        ),
                      );
                    },
                  ),
                  if (seller.observesSabbath) ...[
                    const SizedBox(height: 16),
                    _SabbathBadge(
                      notice: seller.sabbathNoticeText?.trim().isNotEmpty == true
                          ? seller.sabbathNoticeText!
                          : 'This seller observes the Sabbath. Response times may be slower Friday sundown to Saturday sundown.',
                    ),
                  ],
                  if (seller.description?.trim().isNotEmpty == true) ...[
                    const SizedBox(height: 16),
                    _AboutCard(text: seller.description!),
                  ],
                  if (seller.offersDelivery) ...[
                    const SizedBox(height: 16),
                    _DeliveryCard(
                      area: seller.deliveryArea,
                      fee: seller.deliveryFee,
                    ),
                  ],
                  const SizedBox(height: 20),
                  _ProductsSection(
                    products: _products,
                    onTap: (p) => context.pushNamed(
                      'product_details',
                      pathParameters: {'id': p.id},
                      extra: p,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _ReviewsSection(
                    reviews: _reviews,
                    average: seller.rating,
                    totalCount: seller.ratingCount,
                    myReview: _myReview,
                    canRate: _canRate,
                    onRate: _openRateSheet,
                  ),
                  const SizedBox(height: 20),
                  _ReportButton(onTap: _showReport),
                  const SizedBox(height: 16),
                  _SafetyCard(),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHero() {
    final seller = _seller;
    final photo = seller?.profilePhotoUrl;
    final cover = seller?.coverPhotoUrl;
    final hasPhoto = photo != null && photo.isNotEmpty;
    final hasCover = cover != null && cover.isNotEmpty;
    return Stack(
      children: [
        // Cover photo banner (or gradient fallback) sits behind the
        // hero content; a translucent dark overlay keeps the white
        // text + circle avatar legible no matter how bright the cover.
        Positioned.fill(
          child: hasCover
              ? GestureDetector(
                  onTap: () => FullImageViewer.show(context, cover),
                  child: CachedNetworkImage(
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
                  ),
                )
              : const DecoratedBox(
                  decoration: BoxDecoration(gradient: AppColors.appBarGradient),
                ),
        ),
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
        SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _CircleIconButton(
                    icon: Icons.arrow_back_ios_new,
                    onTap: () => context.canPop()
                        ? context.pop()
                        : context.goNamed('marketplace'),
                  ),
                  const Spacer(),
                  _CircleIconButton(
                    icon: Icons.share_outlined,
                    onTap: _shareSeller,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Center(
                child: GestureDetector(
                  onTap: hasPhoto
                      ? () => FullImageViewer.show(context, photo)
                      : null,
                  child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    gradient: hasPhoto ? null : AppColors.primaryGradient,
                    color: hasPhoto ? AppColors.lightGrey : null,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.white, width: 4),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.30),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ],
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
                          size: 42,
                        ),
                ),
                ),
              ),
              const SizedBox(height: 14),
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Flexible(
                            child: Text(
                              seller?.businessName ?? 'Loading…',
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.displayMedium.copyWith(
                                color: AppColors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                                height: 1.15,
                              ),
                            ),
                          ),
                          if (seller?.verified == true ||
                              seller?.sdaVerified == true) ...[
                            const SizedBox(width: 6),
                            const Icon(
                              Icons.verified,
                              color: AppColors.goldAccent,
                              size: 18,
                            ),
                          ],
                        ],
                      ),
                      if (seller != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          SellerCategory.labelFor(seller.category),
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.white.withValues(alpha: 0.75),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
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

class _IdentityCard extends StatelessWidget {
  const _IdentityCard({required this.seller, required this.productCount});

  final Seller seller;
  final int productCount;

  @override
  Widget build(BuildContext context) {
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
      child: Column(
        children: [
          if (cityLine.isNotEmpty)
            Row(
              children: [
                const Icon(
                  Icons.place_outlined,
                  size: 18,
                  color: AppColors.primaryBlue,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    cityLine,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: context.palette.text,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          if (cityLine.isNotEmpty) const SizedBox(height: 14),
          Row(
            children: [
              _Stat(value: '$productCount', label: 'PRODUCTS'),
              _v(),
              _Stat(
                value: seller.rating > 0
                    ? seller.rating.toStringAsFixed(1)
                    : '—',
                label: 'RATING',
                sub: seller.ratingCount > 0
                    ? '${seller.ratingCount} reviews'
                    : 'No reviews yet',
              ),
              _v(),
              _Stat(
                value: _memberSince(seller.createdAt),
                label: 'SINCE',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _v() => Builder(
        builder: (context) => Container(
          width: 1,
          height: 38,
          margin: const EdgeInsets.symmetric(horizontal: 8),
          color: context.palette.divider,
        ),
      );

  String _memberSince(DateTime? createdAt) {
    if (createdAt == null) return '—';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[createdAt.month - 1]} ${createdAt.year}';
  }
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
              fontSize: 20,
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
              textAlign: TextAlign.center,
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

class _ContactRow extends StatelessWidget {
  const _ContactRow({
    required this.seller,
    required this.onWhatsApp,
    required this.onCall,
    required this.onMessage,
  });

  final Seller seller;
  final VoidCallback onWhatsApp;
  final VoidCallback onCall;
  final VoidCallback onMessage;

  @override
  Widget build(BuildContext context) {
    final hasWhatsApp = (seller.whatsapp?.trim().isNotEmpty == true) ||
        seller.phone.trim().isNotEmpty;
    final hasPhone = seller.phone.trim().isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(14),
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
          if (hasWhatsApp) ...[
            Expanded(
              child: _PrimaryAction(
                icon: Icons.chat_outlined,
                label: 'WhatsApp',
                onTap: onWhatsApp,
              ),
            ),
            const SizedBox(width: 10),
          ],
          if (hasPhone)
            _SecondaryAction(
              icon: Icons.call_outlined,
              tooltip: 'Call',
              onTap: onCall,
            ),
          if (hasPhone) const SizedBox(width: 10),
          _SecondaryAction(
            icon: Icons.mail_outline,
            tooltip: 'Message',
            onTap: onMessage,
          ),
        ],
      ),
    );
  }
}

class _PrimaryAction extends StatelessWidget {
  const _PrimaryAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
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
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: AppColors.white, size: 18),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: AppTextStyles.buttonText.copyWith(
                    fontSize: 14,
                    letterSpacing: 0.4,
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

class _SecondaryAction extends StatelessWidget {
  const _SecondaryAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.primaryBlue.withValues(alpha: 0.35),
              ),
            ),
            child: Icon(icon, color: AppColors.primaryBlue, size: 20),
          ),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Observes the Sabbath',
                  style: AppTextStyles.titleSmall.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.goldAccent,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  notice,
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

class _AboutCard extends StatelessWidget {
  const _AboutCard({required this.text});

  final String text;

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
            'ABOUT',
            style: AppTextStyles.labelSmall.copyWith(
              color: context.palette.textMuted,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            text,
            style: AppTextStyles.bodyMedium.copyWith(
              color: context.palette.text,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }
}

class _DeliveryCard extends StatelessWidget {
  const _DeliveryCard({this.area, this.fee});

  final String? area;
  final String? fee;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primaryBlue.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.primaryBlue.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.local_shipping_outlined,
              color: AppColors.primaryBlue,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Offers delivery',
                  style: AppTextStyles.titleSmall.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryBlue,
                  ),
                ),
                const SizedBox(height: 4),
                if (area?.trim().isNotEmpty == true)
                  Text(
                    'Area: $area',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: context.palette.text,
                      height: 1.5,
                    ),
                  ),
                if (fee?.trim().isNotEmpty == true)
                  Text(
                    'Fee: $fee',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: context.palette.text,
                      height: 1.5,
                    ),
                  ),
                if ((area?.trim().isEmpty ?? true) &&
                    (fee?.trim().isEmpty ?? true))
                  Text(
                    'Contact the seller for delivery details.',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: context.palette.text,
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

class _ProductsSection extends StatelessWidget {
  const _ProductsSection({required this.products, required this.onTap});

  final List<Product> products;
  final ValueChanged<Product> onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              Text(
                'PRODUCTS',
                style: AppTextStyles.labelSmall.copyWith(
                  color: context.palette.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                ),
              ),
              const Spacer(),
              Text(
                '${products.length}',
                style: AppTextStyles.labelSmall.copyWith(
                  color: AppColors.primaryBlue,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (products.isEmpty)
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: context.palette.card,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.shopping_bag_outlined,
                  size: 38,
                  color: AppColors.primaryBlue.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 10),
                Text(
                  'No live products',
                  style: AppTextStyles.titleSmall.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Check back soon — this seller hasn\'t listed anything yet.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: context.palette.textMuted,
                  ),
                ),
              ],
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: products.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 0.72,
            ),
            itemBuilder: (context, i) {
              final p = products[i];
              return ProductCard(product: p, onTap: () => onTap(p));
            },
          ),
      ],
    );
  }
}

class _ReportButton extends StatelessWidget {
  const _ReportButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppColors.red.withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.flag_outlined,
                color: AppColors.red,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                'Report this seller',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.red,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SafetyCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.darkNavy.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.darkNavy.withValues(alpha: 0.12),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.shield_outlined,
              color: AppColors.primaryBlue,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Stay safe',
                  style: AppTextStyles.titleSmall.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Meet in a public place. Inspect items before paying. Never send money in advance to people you don\'t trust. Advent Connect ZW is not a party to any transaction.',
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

class _ReportSheet extends StatefulWidget {
  const _ReportSheet({required this.sellerName, required this.onSubmit});

  final String sellerName;
  final void Function(String reason) onSubmit;

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  static const _reasons = [
    'Scam or fraud',
    'Counterfeit goods',
    'Inappropriate content',
    'Harassment or abuse',
    'Doesn\'t belong on the marketplace',
    'Other',
  ];

  String? _selected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: context.palette.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Report ${widget.sellerName}',
              style: AppTextStyles.headlineSmall.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Reports are reviewed by the Advent Connect ZW team.',
              style: AppTextStyles.bodySmall.copyWith(
                color: context.palette.textMuted,
              ),
            ),
            const SizedBox(height: 18),
            for (final r in _reasons)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  onTap: () => setState(() => _selected = r),
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: _selected == r
                          ? AppColors.primaryBlue.withValues(alpha: 0.08)
                          : context.palette.chipBg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _selected == r
                            ? AppColors.primaryBlue
                            : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _selected == r
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          color: _selected == r
                              ? AppColors.primaryBlue
                              : context.palette.textMuted,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            r,
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: _selected == r
                                  ? AppColors.primaryBlue
                                  : context.palette.text,
                              fontWeight: _selected == r
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primaryBlue.withValues(alpha: 0.30),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _selected == null
                      ? null
                      : () => widget.onSubmit(_selected!),
                  borderRadius: BorderRadius.circular(14),
                  child: Opacity(
                    opacity: _selected == null ? 0.6 : 1,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Center(
                        child: Text(
                          'Submit report',
                          style: AppTextStyles.buttonText.copyWith(
                            fontSize: 14,
                            letterSpacing: 0.4,
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
      ),
    );
  }
}

class _ReviewsSection extends StatelessWidget {
  const _ReviewsSection({
    required this.reviews,
    required this.average,
    required this.totalCount,
    required this.myReview,
    required this.canRate,
    required this.onRate,
  });

  final List<SellerRating> reviews;
  final double average;
  final int totalCount;
  final SellerRating? myReview;
  final bool canRate;
  final VoidCallback onRate;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              Text(
                'REVIEWS',
                style: AppTextStyles.labelSmall.copyWith(
                  color: context.palette.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                ),
              ),
              const Spacer(),
              if (totalCount > 0)
                Text(
                  '$totalCount',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.primaryBlue,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Container(
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
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _RatingSummary(average: average, totalCount: totalCount),
              if (canRate) ...[
                const SizedBox(height: 14),
                _RateCta(
                  isEditing: myReview != null,
                  myStars: myReview?.rating ?? 0,
                  onTap: onRate,
                ),
              ],
              if (reviews.isNotEmpty) ...[
                const SizedBox(height: 18),
                const Divider(height: 1, color: Color(0x14000000)),
                const SizedBox(height: 12),
                for (final r in reviews) ...[
                  _ReviewRow(review: r),
                  if (r != reviews.last)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Divider(
                        height: 1,
                        color: Color(0x10000000),
                      ),
                    ),
                ],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _RatingSummary extends StatelessWidget {
  const _RatingSummary({required this.average, required this.totalCount});

  final double average;
  final int totalCount;

  @override
  Widget build(BuildContext context) {
    final hasRatings = totalCount > 0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          hasRatings ? average.toStringAsFixed(1) : '—',
          style: AppTextStyles.displayMedium.copyWith(
            color: AppColors.primaryBlue,
            fontSize: 32,
            fontWeight: FontWeight.w700,
            height: 1,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _StarStrip(value: average),
              const SizedBox(height: 4),
              Text(
                hasRatings
                    ? '$totalCount ${totalCount == 1 ? 'review' : 'reviews'}'
                    : 'No reviews yet — be the first.',
                style: AppTextStyles.bodySmall.copyWith(
                  color: context.palette.textMuted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StarStrip extends StatelessWidget {
  const _StarStrip({required this.value, this.size = 18});

  final double value;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(5, (i) {
        final filled = value >= i + 1;
        final half = !filled && value > i && value < i + 1;
        return Padding(
          padding: const EdgeInsets.only(right: 2),
          child: Icon(
            half
                ? Icons.star_half_rounded
                : (filled
                    ? Icons.star_rounded
                    : Icons.star_outline_rounded),
            size: size,
            color: filled || half
                ? AppColors.goldAccent
                : context.palette.divider,
          ),
        );
      }),
    );
  }
}

class _RateCta extends StatelessWidget {
  const _RateCta({
    required this.isEditing,
    required this.myStars,
    required this.onTap,
  });

  final bool isEditing;
  final int myStars;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: AppColors.primaryBlue.withValues(alpha: 0.06),
            border: Border.all(
              color: AppColors.primaryBlue.withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.rate_review_outlined,
                color: AppColors.primaryBlue,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isEditing
                          ? 'Update your review'
                          : 'Rate this seller',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.primaryBlue,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (isEditing) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            'You gave them',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: context.palette.textMuted,
                            ),
                          ),
                          const SizedBox(width: 6),
                          _StarStrip(
                            value: myStars.toDouble(),
                            size: 13,
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: AppColors.primaryBlue,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({required this.review});

  final SellerRating review;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _StarStrip(value: review.rating.toDouble(), size: 15),
            const Spacer(),
            Text(
              _relative(review.createdAt),
              style: AppTextStyles.labelSmall.copyWith(
                color: context.palette.textMuted,
                fontSize: 11,
              ),
            ),
          ],
        ),
        if (review.review != null && review.review!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            review.review!,
            style: AppTextStyles.bodySmall.copyWith(
              color: context.palette.text,
              height: 1.45,
            ),
          ),
        ],
      ],
    );
  }

  String _relative(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inDays >= 30) {
      final months = (diff.inDays / 30).floor();
      return '${months}mo ago';
    }
    if (diff.inDays >= 1) return '${diff.inDays}d ago';
    if (diff.inHours >= 1) return '${diff.inHours}h ago';
    if (diff.inMinutes >= 1) return '${diff.inMinutes}m ago';
    return 'just now';
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
        color: context.palette.card,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Icon(
            Icons.storefront_outlined,
            size: 48,
            color: context.palette.textMuted,
          ),
          const SizedBox(height: 12),
          Text(
            'Seller not found',
            style: AppTextStyles.titleMedium.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySmall.copyWith(
              color: context.palette.textMuted,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _OwnerBadge extends StatelessWidget {
  const _OwnerBadge({
    required this.owner,
    required this.onTap,
    this.fallbackName,
  });

  final PublicUserProfile owner;
  final String? fallbackName;
  final VoidCallback onTap;

  String get _displayName {
    final raw = owner.fullName.trim();
    if (raw.isNotEmpty && raw.toLowerCase() != 'member') return raw;
    final fb = fallbackName?.trim();
    if (fb != null && fb.isNotEmpty) return fb;
    return 'a verified member';
  }

  @override
  Widget build(BuildContext context) {
    final photo = owner.profilePhotoUrl;
    final hasPhoto = photo != null && photo.isNotEmpty;
    return Material(
      color: context.palette.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            color: context.palette.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.primaryBlue.withValues(alpha: 0.18),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
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
                alignment: Alignment.center,
                child: hasPhoto
                    ? null
                    : const Icon(
                        Icons.person,
                        color: AppColors.white,
                        size: 18,
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'OWNED BY',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: context.palette.textMuted,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.4,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            _displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.titleSmall.copyWith(
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5,
                            ),
                          ),
                        ),
                        if (owner.isVerified) ...[
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.verified,
                            size: 14,
                            color: AppColors.goldAccent,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: context.palette.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
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
            color: AppColors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.white.withValues(alpha: 0.10)),
          ),
          child: Icon(icon, color: AppColors.white, size: 18),
        ),
      ),
    );
  }
}
