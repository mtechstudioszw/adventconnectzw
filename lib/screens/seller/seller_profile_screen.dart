import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../widgets/profile/profile_header.dart';
import '../../widgets/screen_shell.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/countries.dart';
import '../../config/share_config.dart';
import '../../models/product_model.dart';
import '../../models/seller_model.dart';
import '../../services/auth_service.dart';
import '../../services/marketplace_service.dart';
import '../../services/messaging_service.dart';
import '../../services/seller_rating_service.dart';
import '../../services/seller_service.dart';
import '../../services/user_profile_service.dart';
import '../../services/connectivity_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/full_image_viewer.dart';
import '../../widgets/home/report_sheet.dart';
import '../../widgets/home/section_header.dart';
import '../../widgets/marketplace/cart_badge_button.dart';
import '../../widgets/marketplace/product_tile.dart';
import '../../widgets/marketplace/safety_card.dart';
import '../../widgets/motion/brand_spinner.dart';
import '../../widgets/motion/branded_refresh_indicator.dart';
import '../../widgets/motion/pressable.dart';
import '../../widgets/motion/staggered_reveal.dart';
import '../../widgets/rate_seller_sheet.dart';
import '../../widgets/offline_toast.dart';

/// Public storefront.
///
/// Reordered so the goods come first. The old page opened with a centred
/// avatar and then six stacked cards — identity, owner, contact, sabbath,
/// about, delivery — before a buyer reached a single product. A shop
/// window shows stock, not paperwork, so products now sit directly under
/// the header and everything else moves below them.
///
/// The grid is a real [SliverGrid]. It used to be a `shrinkWrap` GridView
/// with `NeverScrollableScrollPhysics` inside a `SliverToBoxAdapter`,
/// which built and laid out every product — and fired every image request
/// — on first paint, with no recycling.
class SellerProfileScreen extends StatefulWidget {
  const SellerProfileScreen({
    super.key,
    required this.authUserId,
    this.initialSeller,
  });

  /// The seller's auth user id (= products.seller_id).
  final String authUserId;

  /// Optional pre-fetched seller passed via go_router `extra`. Avoids a
  /// fetch flash on first paint.
  final Seller? initialSeller;

  @override
  State<SellerProfileScreen> createState() => _SellerProfileScreenState();
}

class _SellerProfileScreenState extends State<SellerProfileScreen> {
  Seller? _seller;
  PublicUserProfile? _owner;
  List<Product> _products = const [];
  List<SellerRating> _reviews = const [];
  SellerRating? _myReview;
  Set<String> _savedIds = <String>{};
  bool _loading = true;
  String? _error;

  /// Only show the rating CTA to someone who isn't this seller.
  bool get _canRate {
    final me = AuthService.currentUser;
    final seller = _seller;
    if (me == null || seller == null) return false;
    return seller.authUserId.isNotEmpty && me.id != seller.authUserId;
  }

  bool get _isOwner =>
      AuthService.currentUser?.id == _seller?.authUserId &&
      _seller?.authUserId.isNotEmpty == true;

  /// A pending, rejected, banned or deactivated shop, seen by anyone but
  /// its owner. patch_031's rule is that such a shop's products never reach
  /// buyers; the marketplace grid and product details enforced it, but
  /// this page loaded the storefront and its products for any link.
  bool get _shopClosed {
    final seller = _seller;
    if (seller == null || _isOwner) return false;
    return !(seller.isApproved && seller.isActive);
  }

  @override
  void initState() {
    super.initState();
    _seller = widget.initialSeller;
    _bootstrap();
    _loadSaved();
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
      // No row is an answer, not a failure: the shop is gone or hidden
      // from this viewer. Falling back to the copy passed in from the rail
      // kept a closed shop open.
      final seller = results[0] as Seller?;
      setState(() {
        _seller = seller;
        // Tiles read `sellerName`, which `products` has no column for —
        // on the shop's own page every product said "Seller".
        _products = [
          for (final p in results[1] as List<Product>)
            seller == null || seller.businessName.isEmpty
                ? p
                : Product.fromJson({
                    ...p.toJson(),
                    'seller_name': seller.businessName,
                  }),
        ];
        _owner = results[2] as PublicUserProfile?;
        _loading = false;
      });
      // Ratings key off the seller row's BIGSERIAL id, so they need the
      // seller to have loaded first.
      if (seller != null) _loadRatings(seller.id);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Pull down to try again.';
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
      // Reviews are non-essential — never block the storefront on them.
    }
  }

  Future<void> _loadSaved() async {
    try {
      final ids = await MarketplaceService.fetchSavedProductIds();
      if (mounted) setState(() => _savedIds = ids);
    } catch (_) {}
  }

  Future<void> _toggleSave(Product product) async {
    final was = _savedIds.contains(product.id);
    setState(() {
      _savedIds = was
          ? ({..._savedIds}..remove(product.id))
          : {..._savedIds, product.id};
    });
    try {
      if (was) {
        await MarketplaceService.unsaveProduct(product.id);
      } else {
        await MarketplaceService.saveProduct(product.id);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _savedIds = was
            ? {..._savedIds, product.id}
            : ({..._savedIds}..remove(product.id));
      });
      if (maybeShowOffline(context)) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AuthService.currentUser == null
                ? 'Sign in to save listings.'
                : "Couldn't save this listing. Try again.",
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    }
  }

  Future<void> _openRateSheet() async {
    final seller = _seller;
    if (seller == null) return;
    final result = await showModalBottomSheet<SellerRating?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.palette.sheet,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.sheetTop),
      builder: (ctx) => RateSellerSheet(
        sellerId: seller.id,
        sellerName: seller.businessName,
        existing: _myReview,
      ),
    );
    if (!mounted) return;
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

  Future<void> _shareSeller() async {
    final seller = _seller;
    if (seller == null) return;
    final name = seller.businessName.trim().isNotEmpty
        ? seller.businessName.trim()
        : 'this seller';
    final shareUrl = sellerShareUrl(seller.authUserId);
    final text = 'Check out $name on Adventist Super App marketplace:\n$shareUrl';
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

  Future<void> _openWhatsApp() async {
    final seller = _seller;
    if (seller == null) return;
    final number = seller.whatsapp?.trim().isNotEmpty == true
        ? seller.whatsapp!
        : seller.phone;
    // Normalised against the SELLER's country, not the buyer's — a Kenyan
    // shop's `07…` has to become +254, whoever is looking at it.
    final digits = Countries.toWhatsAppDigits(
      number,
      countryCode: seller.country,
    );
    if (digits == null || digits.isEmpty) return;
    // Open WhatsApp with the enquiry already written.
    //
    // This used to be a bare wa.me/<number> — the seller received a blank
    // chat from an unknown number with no clue which shop, listing or app
    // it came from. The store link is what lets them answer without
    // asking three questions first.
    final message =
        'Hi ${seller.contactName?.trim().isNotEmpty == true ? seller.contactName!.trim() : seller.businessName}, '
        "I found ${seller.businessName} on Adventist Super App and I'd like to ask about your products."
        '\n\n${sellerShareUrl(seller.authUserId)}';
    final uri = Uri.parse(
      'https://wa.me/$digits?text=${Uri.encodeComponent(message)}',
    );
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

  Future<void> _callPhone() async {
    final number = _seller?.phone ?? '';
    final cleaned = number.replaceAll(RegExp(r'[^\d+]'), '');
    if (cleaned.isEmpty) return;
    try {
      final ok = await launchUrl(
        Uri.parse('tel:$cleaned'),
        mode: LaunchMode.externalApplication,
      );
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

  /// Opens a chat with the shop directly.
  ///
  /// This replaces a button whose entire behaviour was showing a snackbar
  /// telling the user that messaging only works from a product page.
  Future<void> _messageSeller() async {
    final seller = _seller;
    if (seller == null || seller.authUserId.isEmpty) return;
    if (_isOwner) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'This is your own store.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    try {
      final convo = await MessagingService.createConversation(
        otherUserId: seller.authUserId,
        otherUserName: seller.businessName,
        source: 'marketplace',
        isBusiness: true,
      ).timeout(const Duration(seconds: 15));
      if (!mounted) return;
      ChatLaunchIntent.set(draft: 'Hi ${seller.businessName}, ');
      if (!mounted) return;
      context.pushNamed('chat', pathParameters: {'id': convo.id}, extra: convo);
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: AppColors.red,
          content: Text(
            'Could not open the chat. Try WhatsApp instead.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    }
  }

  /// Files the report into the `reports` table, like every other report in
  /// the app.
  ///
  /// It used to open WhatsApp to the founder's personal number with a
  /// pre-filled message. That was wrong in four separate ways:
  ///
  ///   * it handed the reporter the founder's phone number, and handed the
  ///     founder the reporter's — reporting a seller should not introduce
  ///     you to anyone;
  ///   * the body carried the reporter's user id into a message the
  ///     reporter could read;
  ///   * WhatsApp lets the sender EDIT that text before sending, so the
  ///     seller id, the reason and the reporter id were all attacker-
  ///     controlled by the time they arrived — the report could not be
  ///     trusted at all;
  ///   * if they never pressed send, nothing was recorded anywhere, while
  ///     the app behaved as though it had been.
  ///
  /// `ReportService` already exists, already lists 'seller' as a content
  /// type, and already feeds the moderation queue.
  void _showReport() {
    final seller = _seller;
    if (seller == null) return;
    showReportSheet(
      context,
      contentType: 'seller',
      contentId: seller.authUserId,
      contentLabel: seller.businessName,
    );
  }


  @override
  Widget build(BuildContext context) {
    final seller = _seller;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: BrandedRefreshIndicator(
        color: AppColors.primaryBlue,
        onRefresh: _bootstrap,
        child: _buildBody(),
      ),
      // Contact is pinned rather than buried in a card halfway down —
      // reaching the shop is the whole point of the page.
      bottomNavigationBar: seller == null || _isOwner
          ? null
          : _ContactBar(
              seller: seller,
              onWhatsApp: _openWhatsApp,
              onCall: _callPhone,
              onMessage: _messageSeller,
            ),
      // No ad here (user decision 2026-07-02): a banner under a seller's
      // own storefront cheapened the page and competed with their goods.
    );
  }

  Widget _buildBody() {
    if (_loading && _seller == null) {
      return Stack(
        children: [
          _buildHeader(),
          const Positioned.fill(child: Center(child: BrandSpinner(size: 30))),
        ],
      );
    }
    final seller = _seller;
    if (seller == null || _shopClosed) {
      final offline = !ConnectivityService.isOnline;
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          _buildHeader(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
            child: _shopClosed
                ? const _ErrorCard(
                    title: "This shop isn't open",
                    message: 'It may be under review or no longer trading.',
                  )
                : _error == null
                ? const _ErrorCard(
                    title: 'Seller not found',
                    message: 'This shop may have closed.',
                  )
                : _ErrorCard(
                    title: offline ? "You're offline" : "Couldn't load shop",
                    message: _error!,
                  ),
          ),
        ],
      );
    }

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(child: _buildHeader()),
        // Opened from your own dashboard, this page is a PREVIEW. Say so
        // — the buyer actions are all hidden for you, so without this the
        // page just looks broken rather than deliberately read-only.
        if (_isOwner)
          SliverToBoxAdapter(child: _OwnerPreviewBanner(seller: seller)),

        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: AppSpace.xl),
            // The count is in the header's stats now; saying it twice was
            // noise.
            child: const SectionHeader(title: 'Products'),
          ),
        ),

        if (_products.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.lg,
                AppSpace.md,
                AppSpace.lg,
                0,
              ),
              // Opened from the shops rail the seller is already known, so
              // a failed load used to land here and say the shop had no
              // products — when they simply had not arrived.
              child: _error != null
                  ? _ErrorCard(
                      title: !ConnectivityService.isOnline
                          ? "You're offline"
                          : "Couldn't load products",
                      message: _error!,
                    )
                  : _EmptyProducts(),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.lg,
              AppSpace.md,
              AppSpace.lg,
              0,
            ),
            sliver: SliverGrid(
              gridDelegate: ProductTile.gridDelegate,
              delegate: SliverChildBuilderDelegate((context, i) {
                final p = _products[i];
                final tile = ProductTile(
                  product: p,
                  saved: _isOwner ? null : _savedIds.contains(p.id),
                  onToggleSave: () => _toggleSave(p),
                  onTap: () => context.pushNamed(
                    'product_details',
                    pathParameters: {'id': p.id},
                    extra: p,
                  ),
                );
                if (i >= 6) return tile;
                return StaggeredReveal(index: i, rise: 20, child: tile);
              }, childCount: _products.length),
            ),
          ),

        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.lg,
              AppSpace.xl,
              AppSpace.lg,
              AppSpace.xxl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (seller.observesSabbath) ...[
                  _SabbathBadge(
                    notice: seller.sabbathNoticeText?.trim().isNotEmpty == true
                        ? seller.sabbathNoticeText!
                        : 'This seller observes the Sabbath. Response times '
                              'may be slower Friday sundown to Saturday '
                              'sundown.',
                  ),
                  const SizedBox(height: AppSpace.lg),
                ],
                if (seller.description?.trim().isNotEmpty == true) ...[
                  _AboutCard(text: seller.description!),
                  const SizedBox(height: AppSpace.lg),
                ],
                if (seller.offersDelivery ||
                    (seller.paymentMethods ?? '').trim().isNotEmpty) ...[
                  _DeliveryCard(
                    delivers: seller.offersDelivery,
                    area: seller.deliveryArea,
                    fee: seller.deliveryFee,
                    payment: seller.paymentMethods,
                  ),
                  const SizedBox(height: AppSpace.lg),
                ],
                if (_owner != null) ...[
                  _OwnerBadge(
                    owner: _owner!,
                    fallbackName: seller.contactName,
                    onTap: () => context.pushNamed(
                      'user_profile',
                      pathParameters: {'userId': _owner!.id},
                    ),
                  ),
                  const SizedBox(height: AppSpace.lg),
                ],
                _ReviewsSection(
                  reviews: _reviews,
                  average: seller.rating,
                  totalCount: seller.ratingCount,
                  myReview: _myReview,
                  canRate: _canRate,
                  onRate: _openRateSheet,
                ),
                const SizedBox(height: AppSpace.lg),
                // Reporting your own shop, and being warned about buying
                // safely from yourself, are both nonsense when this is a
                // preview of your own storefront.
                if (!_isOwner) ...[
                  _ReportButton(onTap: _showReport),
                  const SizedBox(height: AppSpace.lg),
                  const MarketplaceSafetyCard(),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Flat top bar + the shared profile header (redesign, 28 Oct 2026).
  ///
  /// The old header painted the app-bar gradient as a 190px slab whenever a
  /// shop had no cover — CLAUDE.md: a missing cover is never a reason for a
  /// navy slab. Now a cover shows only when there is one, the logo is a
  /// rounded square (organizations, not people — same as Pages), and the
  /// name, rating and place read the same way as everywhere else.
  Widget _buildHeader() {
    final seller = _seller;
    final topBar = FlatStatusBar(
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Row(
            children: [
              const ScreenHeroBackButton(fallbackRoute: 'marketplace'),
              const Spacer(),
              if (seller != null)
                HeaderIconButton(
                  icon: Icons.ios_share_rounded,
                  tooltip: 'Share shop',
                  onTap: _shareSeller,
                ),
              const SizedBox(width: AppSpace.sm),
              CartBadgeButton(onTap: () => context.pushNamed('cart')),
            ],
          ),
        ),
      ),
    );
    if (seller == null) return topBar;
    final place = <String?>[
      seller.city,
      seller.province,
      Countries.nameOf(seller.country),
    ].where((s) => s != null && s.isNotEmpty).join(', ');
    final initials = seller.businessName
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();
    final photo = seller.profilePhotoUrl;
    final cover = seller.coverPhotoUrl;
    return ProfileGlow(
      photoUrl: photo,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          topBar,
          ProfileHeader(
            name: seller.businessName,
            initials: initials.isEmpty ? '?' : initials,
            photoUrl: photo,
            coverUrl: cover,
            squareAvatar: true,
            verified: seller.verified || seller.sdaVerified,
            relationNote: SellerCategory.labelFor(seller.category),
            facts: [
              if (place.isNotEmpty)
                ProfileFact(
                  Icons.place_outlined,
                  '${Countries.flagOf(seller.country)} $place'.trim(),
                ),
              if (seller.createdAt != null)
                ProfileFact(
                  Icons.event_outlined,
                  'Since ${_monthYear(seller.createdAt!)}',
                ),
            ],
            stats: [
              ProfileStat(
                _products.length == 1 ? 'Product' : 'Products',
                _products.length,
              ),
              // Real reviews only; a shop with none shows no rating cell
              // rather than a zero.
              if (seller.ratingCount > 0)
                ProfileStat(
                  seller.ratingCount == 1 ? 'Review' : 'Reviews',
                  seller.ratingCount,
                ),
            ],
            badges: [
              if (seller.ratingCount > 0)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.star_rounded,
                      size: 16,
                      color: AppColors.goldAccent,
                    ),
                    Text(
                      seller.rating.toStringAsFixed(1),
                      style: AppTextStyles.labelLarge.copyWith(
                        color: context.palette.text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
            ],
            onAvatarTap: (photo ?? '').isEmpty
                ? null
                : () => FullImageViewer.show(context, photo),
            onCoverTap: (cover ?? '').isEmpty
                ? null
                : () => FullImageViewer.show(context, cover),
            actions: const [],
          ),
        ],
      ),
    );
  }

  static String _monthYear(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[d.month - 1]} ${d.year}';
  }
}


class _ContactBar extends StatelessWidget {
  const _ContactBar({
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
    final hasWhatsApp =
        (seller.whatsapp?.trim().isNotEmpty == true) ||
        seller.phone.trim().isNotEmpty;
    final hasPhone = seller.phone.trim().isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        color: context.palette.card,
        boxShadow: AppShadows.floating(context),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.lg,
            AppSpace.md,
            AppSpace.lg,
            AppSpace.md,
          ),
          child: Row(
            children: [
              if (hasPhone) ...[
                _IconAction(icon: Icons.call_outlined, onTap: onCall),
                const SizedBox(width: AppSpace.sm),
              ],
              _IconAction(icon: Icons.forum_outlined, onTap: onMessage),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Pressable(
                  onTap: hasWhatsApp ? onWhatsApp : onMessage,
                  haptics: true,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: AppSpace.lg),
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      borderRadius: AppRadius.buttonAll,
                      boxShadow: AppShadows.glow(context),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          hasWhatsApp
                              ? Icons.chat_rounded
                              : Icons.forum_outlined,
                          color: AppColors.white,
                          size: 18,
                        ),
                        const SizedBox(width: AppSpace.sm),
                        Text(
                          hasWhatsApp ? 'WhatsApp this shop' : 'Message',
                          style: AppTextStyles.buttonText.copyWith(
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
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

class _IconAction extends StatelessWidget {
  const _IconAction({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      pressedScale: 0.92,
      child: Container(
        width: 48,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: AppRadius.buttonAll,
          border: Border.all(color: context.palette.divider),
        ),
        child: Icon(icon, color: AppColors.primaryBlue, size: 20),
      ),
    );
  }
}


class _EmptyProducts extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: AppRadius.lgAll,
        boxShadow: AppShadows.card(context),
      ),
      child: Column(
        children: [
          Icon(
            Icons.shopping_bag_outlined,
            size: 38,
            color: AppColors.primaryBlue.withValues(alpha: 0.5),
          ),
          const SizedBox(height: AppSpace.md - 2),
          Text(
            'No live products',
            style: AppTextStyles.titleSmall.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpace.xs),
          Text(
            'Check back soon — this seller hasn\'t listed anything yet.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySmall.copyWith(
              color: context.palette.textMuted,
            ),
          ),
        ],
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
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: AppColors.goldAccent.withValues(alpha: 0.08),
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: AppColors.goldAccent.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.brightness_3, color: AppColors.goldAccent, size: 20),
          const SizedBox(width: AppSpace.md),
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
                const SizedBox(height: AppSpace.xs),
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
        borderRadius: AppRadius.lgAll,
        boxShadow: AppShadows.card(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ABOUT',
            style: AppTextStyles.labelSmall.copyWith(
              color: context.palette.textMuted,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: AppSpace.md - 2),
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
  const _DeliveryCard({
    required this.delivers,
    this.area,
    this.fee,
    this.payment,
  });

  final bool delivers;
  final String? area;
  final String? fee;

  /// What the shop accepts, as it typed it (EcoCash, cash…).
  final String? payment;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: AppColors.primaryBlue.withValues(alpha: 0.06),
        borderRadius: AppRadius.lgAll,
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
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  delivers ? 'Offers delivery' : 'Collection only',
                  style: AppTextStyles.titleSmall.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryBlue,
                  ),
                ),
                const SizedBox(height: AppSpace.xs),
                if (payment?.trim().isNotEmpty == true)
                  Text(
                    'Payment: ${payment!.trim()}',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: context.palette.text,
                      height: 1.5,
                    ),
                  ),
                if (delivers && area?.trim().isNotEmpty == true)
                  Text(
                    'Area: $area',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: context.palette.text,
                      height: 1.5,
                    ),
                  ),
                if (delivers && fee?.trim().isNotEmpty == true)
                  Text(
                    'Fee: $fee',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: context.palette.text,
                      height: 1.5,
                    ),
                  ),
                if (delivers &&
                    (area?.trim().isEmpty ?? true) &&
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

/// Shown only to the shop's owner, when they open their own storefront
/// from the seller dashboard.
///
/// The page is identical to what a buyer sees minus every buyer action —
/// no WhatsApp / Call / Message bar, no rating CTA, no report link, no
/// safety card. Without this strip that reads as a broken page; with it,
/// it reads as the preview it is, and gives them the one action that
/// does belong here: editing the shop.
class _OwnerPreviewBanner extends StatelessWidget {
  const _OwnerPreviewBanner({required this.seller});

  final Seller seller;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        AppSpace.lg,
        AppSpace.lg,
        0,
      ),
      child: Container(
        padding: const EdgeInsets.all(AppSpace.md),
        decoration: BoxDecoration(
          color: AppColors.primaryBlue.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
            color: AppColors.primaryBlue.withValues(alpha: 0.22),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.primaryBlue.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.visibility_outlined,
                size: 18,
                color: AppColors.primaryBlue,
              ),
            ),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Preview',
                    style: AppTextStyles.titleSmall.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'This is how buyers see your shop. Contact and rating '
                    'buttons are off for you.',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: palette.textMuted,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpace.sm),
            TextButton(
              onPressed: () => context.pushNamed('edit_store', extra: seller),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primaryBlue,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: const Size(0, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'Edit',
                style: AppTextStyles.labelMedium.copyWith(
                  color: AppColors.primaryBlue,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportButton extends StatelessWidget {
  const _ReportButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          vertical: AppSpace.md + 2,
          horizontal: AppSpace.lg,
        ),
        decoration: BoxDecoration(
          borderRadius: AppRadius.buttonAll,
          border: Border.all(color: AppColors.red.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.flag_outlined, color: AppColors.red, size: 18),
            const SizedBox(width: AppSpace.sm),
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
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpace.xl),
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: AppRadius.lgAll,
        boxShadow: AppShadows.card(context),
      ),
      child: Column(
        children: [
          Icon(
            Icons.storefront_outlined,
            size: 48,
            color: context.palette.textMuted,
          ),
          const SizedBox(height: AppSpace.md),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppTextStyles.titleMedium.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpace.xs),
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
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.md,
          vertical: AppSpace.md - 2,
        ),
        decoration: BoxDecoration(
          color: context.palette.card,
          borderRadius: AppRadius.cardAll,
          border: Border.all(
            color: AppColors.primaryBlue.withValues(alpha: 0.18),
          ),
        ),
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
                  : const Icon(Icons.person, color: AppColors.white, size: 18),
            ),
            const SizedBox(width: AppSpace.md - 2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'OWNED BY',
                    style: AppTextStyles.labelSmall.copyWith(
                      color: context.palette.textMuted,
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
                          ),
                        ),
                      ),
                      if (owner.isVerified) ...[
                        const SizedBox(width: AppSpace.xs),
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
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: AppRadius.lgAll,
        boxShadow: AppShadows.card(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'REVIEWS',
            style: AppTextStyles.labelSmall.copyWith(
              color: context.palette.textMuted,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: AppSpace.md),
          _RatingSummary(average: average, totalCount: totalCount),
          if (canRate) ...[
            const SizedBox(height: AppSpace.md + 2),
            _RateCta(
              isEditing: myReview != null,
              myStars: myReview?.rating ?? 0,
              onTap: onRate,
            ),
          ],
          if (reviews.isNotEmpty) ...[
            const SizedBox(height: 18),
            Divider(height: 1, color: context.palette.divider),
            const SizedBox(height: AppSpace.md),
            for (final r in reviews) ...[
              _ReviewRow(review: r),
              if (r != reviews.last)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpace.md),
                  child: Divider(height: 1, color: context.palette.divider),
                ),
            ],
          ],
        ],
      ),
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
      children: [
        Text(
          hasRatings ? average.toStringAsFixed(1) : '—',
          style: AppTextStyles.displayMedium.copyWith(
            color: context.palette.text,
            fontWeight: FontWeight.w800,
            height: 1,
          ),
        ),
        const SizedBox(width: AppSpace.md + 2),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _StarStrip(value: average),
              const SizedBox(height: AppSpace.xs),
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
                : (filled ? Icons.star_rounded : Icons.star_outline_rounded),
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
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.md + 2,
          vertical: AppSpace.md,
        ),
        decoration: BoxDecoration(
          borderRadius: AppRadius.buttonAll,
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
            const SizedBox(width: AppSpace.md - 2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isEditing ? 'Update your review' : 'Rate this seller',
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
                        _StarStrip(value: myStars.toDouble(), size: 13),
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
    if (diff.inDays >= 30) return '${(diff.inDays / 30).floor()}mo ago';
    if (diff.inDays >= 1) return '${diff.inDays}d ago';
    if (diff.inHours >= 1) return '${diff.inHours}h ago';
    if (diff.inMinutes >= 1) return '${diff.inMinutes}m ago';
    return 'just now';
  }
}
