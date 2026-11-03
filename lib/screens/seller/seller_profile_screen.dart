import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
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
import '../../widgets/marketplace/cart_badge_button.dart';
import '../../widgets/marketplace/product_tile.dart';
import '../../widgets/marketplace/safety_card.dart';
import '../../widgets/motion/brand_spinner.dart';
import '../../widgets/motion/branded_refresh_indicator.dart';
import '../../widgets/motion/pressable.dart';
import '../../widgets/motion/staggered_reveal.dart';
import '../../widgets/rate_seller_sheet.dart';
import '../../widgets/offline_toast.dart';
import '../../widgets/expandable_text.dart';
import '../../widgets/verified_tick.dart';
import '../../marketplace/market_ui.dart';
import '../../marketplace/product_image_source.dart';
import '../../marketplace/product_theme.dart';

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
    _seller = widget.initialSeller ??
        SellerService.cachedSeller(widget.authUserId);
    // The shop's listings as last seen: the page opens instantly (and
    // offline), then refreshes.
    final cachedProducts = SellerService.cachedShopProducts(widget.authUserId);
    if (cachedProducts != null && _seller != null) {
      _products = [
        for (final p in cachedProducts)
          _seller!.businessName.isEmpty
              ? p
              : Product.fromJson({
                  ...p.toJson(),
                  'seller_name': _seller!.businessName,
                }),
      ];
    }
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
    final text =
        'Check out $name on Adventist Super App marketplace:\n$shareUrl';
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

  // ---------------------------------------------------------------------
  //  Storefront (redesign, 28 Oct 2026) — the same language as the product
  //  page so going from a product to its shop and back feels like one
  //  place: a stage coloured from the shop's own logo (or cover), a sheet
  //  that rides over it, hairline sections instead of stacked cards, and
  //  the same Chat + accent-pill action bar.
  // ---------------------------------------------------------------------

  /// Scroll offset, read from scroll notifications, for the header.
  double _scrolled = 0;
  ProductTheme? _theme;
  String? _themeFor;

  ProductLook get _look => ProductTheme.lookForText(
    '${_seller?.category ?? ''} ${_seller?.businessName ?? ''}',
  );

  String? get _themeImage {
    final s = _seller;
    if (s == null) return null;
    final logo = s.profilePhotoUrl?.trim();
    if (logo != null && logo.isNotEmpty) return logo;
    final cover = s.coverPhotoUrl?.trim();
    return (cover != null && cover.isNotEmpty) ? cover : null;
  }

  ProductTheme get _currentTheme =>
      _theme ??
      ProductTheme.cachedImage(_themeImage, _look) ??
      ProductTheme.preset(_look);

  Future<void> _loadTheme() async {
    final key = '${_themeImage ?? ''}|${_look.name}';
    if (_seller == null || key == _themeFor) return;
    _themeFor = key;
    final theme = await ProductTheme.resolveImage(_themeImage, _look);
    if (mounted && _themeFor == key) setState(() => _theme = theme);
  }

  bool get _hasWhatsApp {
    final s = _seller;
    return s != null &&
        ((s.whatsapp?.trim().isNotEmpty ?? false) || s.phone.trim().isNotEmpty);
  }

  Future<void> _openContactSheet() async {
    final seller = _seller;
    if (seller == null) return;
    final palette = context.palette;
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: palette.sheet,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: palette.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Contact ${seller.businessName}',
                style: AppTextStyles.titleLarge.copyWith(
                  color: palette.text,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              MarketContactOption(
                icon: Icons.forum_rounded,
                title: 'Message in the app',
                subtitle: 'Chat with the shop inside Adventist Super App',
                onTap: () => Navigator.pop(ctx, 'chat'),
              ),
              if (_hasWhatsApp) ...[
                const SizedBox(height: 10),
                MarketContactOption(
                  icon: Icons.chat_rounded,
                  title: 'WhatsApp',
                  subtitle: 'Opens WhatsApp with a link to this shop',
                  onTap: () => Navigator.pop(ctx, 'whatsapp'),
                ),
              ],
              if (seller.phone.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                MarketContactOption(
                  icon: Icons.call_outlined,
                  title: 'Call',
                  subtitle: seller.phone.trim(),
                  onTap: () => Navigator.pop(ctx, 'call'),
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case 'chat':
        await _messageSeller();
      case 'whatsapp':
        await _openWhatsApp();
      case 'call':
        await _callPhone();
    }
  }

  @override
  Widget build(BuildContext context) {
    final seller = _seller;
    if (seller != null) _loadTheme();
    final b = Theme.of(context).brightness;
    final theme = _currentTheme;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          BrandedRefreshIndicator(
            color: AppColors.primaryBlue,
            onRefresh: _bootstrap,
            child: _buildBody(),
          ),
          _buildTopBar(),
        ],
      ),
      // No bar for the owner (their preview says so) or a closed shop.
      bottomNavigationBar: seller == null || _isOwner || _shopClosed
          ? null
          : MarketActionBar(
              chat: MarketChatButton(
                onTap: _openContactSheet,
                semanticLabel: 'Contact the shop',
              ),
              primary: MarketPill(
                label: _hasWhatsApp ? 'WhatsApp the shop' : 'Message the shop',
                leading: _hasWhatsApp
                    ? Icons.chat_rounded
                    : Icons.forum_outlined,
                trailing: const Icon(Icons.arrow_forward_rounded, size: 18),
                bg: theme.accent(b),
                fg: theme.onAccent(b),
                raised: true,
                onTap: _hasWhatsApp ? _openWhatsApp : _messageSeller,
              ),
            ),
      // No ad here (user decision 2026-07-02): a banner under a seller's
      // own storefront cheapened the page and competed with their goods.
    );
  }

  double _stageHeight(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final hasCover = (_seller?.coverPhotoUrl ?? '').trim().isNotEmpty;
    return hasCover
        ? MediaQuery.sizeOf(context).width * 9 / 16 + top
        : top + 150;
  }

  Widget _buildTopBar() {
    final palette = context.palette;
    final t = ((_scrolled - (_stageHeight(context) - 110)) / 70).clamp(
      0.0,
      1.0,
    );
    final solid = t > 0.5;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: BoxDecoration(
          color: palette.scaffoldBg.withValues(alpha: t),
          border: Border(
            bottom: BorderSide(color: palette.divider.withValues(alpha: t)),
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
            child: Row(
              children: [
                StageHeaderButton(
                  icon: Icons.arrow_back_rounded,
                  solid: solid,
                  tooltip: 'Back',
                  onTap: () => context.canPop()
                      ? context.pop()
                      : context.goNamed('marketplace'),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Opacity(
                    opacity: t,
                    child: Text(
                      _seller?.businessName ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.titleSmall.copyWith(
                        color: palette.text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                if (_seller != null)
                  StageHeaderButton(
                    icon: Icons.ios_share_rounded,
                    solid: solid,
                    tooltip: 'Share shop',
                    onTap: _shareSeller,
                  ),
                const SizedBox(width: 8),
                CartBadgeButton(onTap: () => context.pushNamed('cart')),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStage() {
    final seller = _seller;
    final b = Theme.of(context).brightness;
    final theme = _currentTheme;
    final cover = seller?.coverPhotoUrl?.trim();
    final hasCover = cover != null && cover.isNotEmpty;
    // In dark mode a bright logo background would light up the whole band;
    // the shop's dark surface is used instead (the logo keeps its own
    // background in its tile).
    var stage = theme.stage(b);
    if (b == Brightness.dark && stage.computeLuminance() > 0.5) {
      stage = theme.stageDark == theme.stageLight
          ? ProductTheme.preset(theme.look).stageDark
          : theme.stageDark;
    }
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: stage),
      duration: const Duration(milliseconds: 450),
      builder: (context, color, child) =>
          Container(height: _stageHeight(context), color: color, child: child),
      child: hasCover
          ? GestureDetector(
              onTap: () => FullImageViewer.show(context, cover),
              child: Image(
                image: ProductImageSource.provider(cover),
                fit: BoxFit.cover,
                width: double.infinity,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            )
          : null,
    );
  }

  Widget _buildBody() {
    final seller = _seller;
    if (seller == null || _shopClosed) {
      final offline = !ConnectivityService.isOnline;
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          _buildStage(),
          if (_loading && seller == null)
            const Padding(
              padding: EdgeInsets.only(top: 60),
              child: Center(child: BrandSpinner(size: 30)),
            )
          else
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

    final palette = context.palette;
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.depth == 0) {
          _scrolled = n.metrics.pixels;
          _onScrollTick();
        }
        return false;
      },
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          // Stage and sheet in ONE sliver: in a scroll view an earlier sliver
          // paints over a later one, so the logo breaking the sheet's top
          // edge was hidden under the stage.
          SliverToBoxAdapter(
            child: Column(
              children: [
                _buildStage(),
                Transform.translate(
                  offset: const Offset(0, -24),
                  child: Container(
                    decoration: BoxDecoration(
                      color: palette.scaffoldBg,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(28),
                      ),
                    ),
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: _buildIdentity(seller),
                  ),
                ),
              ],
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Row(
                children: [
                  Text(
                    'Products',
                    style: AppTextStyles.titleMedium.copyWith(
                      color: palette.text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (_products.isNotEmpty)
                    Text(
                      '${_products.length}',
                      style: AppTextStyles.labelLarge.copyWith(
                        color: palette.textMuted,
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (_products.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
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
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
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
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  MarketSection(
                    title: 'Reviews',
                    child: _ReviewsSection(
                      reviews: _reviews,
                      average: seller.rating,
                      totalCount: seller.ratingCount,
                      myReview: _myReview,
                      canRate: _canRate,
                      onRate: _openRateSheet,
                    ),
                  ),
                  if (_owner != null)
                    MarketSection(
                      title: 'The person behind the shop',
                      child: _OwnerBadge(
                        owner: _owner!,
                        fallbackName: seller.contactName,
                        onTap: () => context.pushNamed(
                          'user_profile',
                          pathParameters: {'userId': _owner!.id},
                        ),
                      ),
                    ),
                  if (!_isOwner) ...[
                    const SizedBox(height: 24),
                    _buildBuySafely(),
                    Center(
                      child: TextButton.icon(
                        onPressed: _showReport,
                        icon: const Icon(Icons.flag_outlined, size: 16),
                        label: const Text('Report this shop'),
                        style: TextButton.styleFrom(
                          foregroundColor: palette.textMuted,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _onScrollTick() {
    if ((_scrolled < 420) && mounted) setState(() {});
  }

  Widget _buildIdentity(Seller seller) {
    final palette = context.palette;
    final b = Theme.of(context).brightness;
    final theme = _currentTheme;
    final accent = theme.accent(b);
    final logo = seller.profilePhotoUrl?.trim();
    final hasLogo = logo != null && logo.isNotEmpty;
    final place = [
      seller.city,
      seller.province,
    ].where((s) => (s ?? '').isNotEmpty).join(', ');
    final initials = seller.businessName
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();

    final chips = <(IconData, String)>[
      if (seller.offersDelivery)
        (
          Icons.local_shipping_outlined,
          (seller.deliveryArea ?? '').trim().isNotEmpty
              ? 'Delivers · ${seller.deliveryArea!.trim()}'
              : 'Delivers',
        )
      else
        (Icons.storefront_outlined, 'Collection only'),
      if ((seller.paymentMethods ?? '').trim().isNotEmpty)
        (Icons.account_balance_wallet_outlined, seller.paymentMethods!.trim()),
      if (seller.observesSabbath)
        (Icons.brightness_3_outlined, 'Keeps the Sabbath'),
      if (seller.createdAt != null)
        (Icons.event_outlined, 'Since ${seller.createdAt!.year}'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Logo breaks the sheet's top edge, like the product photo above
        // its details.
        Transform.translate(
          offset: const Offset(0, -40),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              GestureDetector(
                onTap: hasLogo
                    ? () => FullImageViewer.show(context, logo)
                    : null,
                child: Container(
                  width: 92,
                  height: 92,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: palette.scaffoldBg,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.10),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: hasLogo
                        ? Image(
                            image: ResizeImage(
                              ProductImageSource.provider(logo),
                              width: 300,
                            ),
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => _LogoFallback(
                              initials: initials,
                              color: accent,
                            ),
                          )
                        : _LogoFallback(initials: initials, color: accent),
                  ),
                ),
              ),
              const Spacer(),
              if (seller.ratingCount > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: _RatingBadge(
                    rating: seller.rating,
                    count: seller.ratingCount,
                  ),
                ),
            ],
          ),
        ),
        Transform.translate(
          offset: const Offset(0, -28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      seller.businessName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.headlineSmall.copyWith(
                        color: palette.text,
                        fontWeight: FontWeight.w700,
                        fontSize: 24,
                        height: 1.2,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                  if (seller.verified || seller.sdaVerified)
                    const VerifiedTick(size: 18, leftGap: 6),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                [
                  if (seller.category != 'other')
                    SellerCategory.labelFor(seller.category),
                  if (place.isNotEmpty) place,
                  if (seller.ratingCount == 0) 'New shop',
                ].join('  ·  '),
                style: AppTextStyles.bodyMedium.copyWith(
                  color: palette.textMuted,
                ),
              ),
              if ((seller.description ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 14),
                ExpandableText(
                  text: seller.description!.trim(),
                  collapsedLines: 3,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: palette.text,
                    height: 1.55,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in chips)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: palette.card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: palette.divider),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(c.$1, size: 15, color: accent),
                          const SizedBox(width: 6),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 240),
                            child: Text(
                              c.$2,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.labelMedium.copyWith(
                                color: palette.text,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              if (_isOwner) ...[
                const SizedBox(height: 16),
                _OwnerPreviewBanner(seller: seller),
              ],
              const SizedBox(height: 12),
              Divider(height: 1, color: palette.divider),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBuySafely() {
    final palette = context.palette;
    return Material(
      color: palette.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => showModalBottomSheet<void>(
          context: context,
          backgroundColor: palette.sheet,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          builder: (_) => const SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 20, 16, 16),
              child: MarketplaceSafetyCard(),
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const Icon(
                Icons.shield_outlined,
                color: AppColors.primaryBlue,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Buy safely',
                      style: AppTextStyles.labelLarge.copyWith(
                        color: palette.text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Meet in public and inspect before you pay.',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: palette.textMuted,
                      ),
                    ),
                  ],
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

class _LogoFallback extends StatelessWidget {
  const _LogoFallback({required this.initials, required this.color});
  final String initials;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: color,
      child: Center(
        child: Text(
          initials.isEmpty ? '?' : initials,
          style: AppTextStyles.headlineMedium.copyWith(
            color: color.computeLuminance() > 0.5
                ? const Color(0xFF111111)
                : AppColors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// "★ 4.6 · 5 reviews" — only rendered when real reviews exist.
class _RatingBadge extends StatelessWidget {
  const _RatingBadge({required this.rating, required this.count});
  final double rating;
  final int count;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.divider),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star_rounded, size: 18, color: AppColors.goldAccent),
          const SizedBox(width: 4),
          Text(
            rating.toStringAsFixed(1),
            style: AppTextStyles.titleSmall.copyWith(
              color: palette.text,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            '  ·  $count review${count == 1 ? '' : 's'}',
            style: AppTextStyles.bodySmall.copyWith(color: palette.textMuted),
          ),
        ],
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
    // A section, not a card: the storefront's sections are separated by
    // space and hairlines (MarketSection supplies the title).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
