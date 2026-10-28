import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/countries.dart';
import '../../config/share_config.dart';
import '../../models/product_model.dart';
import '../../services/analytics_service.dart';
import '../../services/auth_service.dart';
import '../../services/cart_service.dart';
import '../../services/marketplace_service.dart';
import '../../services/recently_viewed_service.dart';
import '../../services/messaging_service.dart';
import '../../services/seller_service.dart';
import '../../models/seller_model.dart';
import '../../widgets/marketplace/product_tile.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/cached_image.dart';
import '../../widgets/marketplace/cart_badge_button.dart';
import '../../widgets/marketplace/safety_card.dart';
import '../../widgets/motion/brand_spinner.dart';
import '../../widgets/motion/pressable.dart';
import '../../widgets/motion/staggered_reveal.dart';
import '../../widgets/home/report_sheet.dart';
import '../../widgets/moderation_appeal_sheet.dart';
import '../../widgets/offline_toast.dart';
import '../../widgets/expandable_text.dart';
import '../../widgets/verified_tick.dart';
import '../../utils/photo_tint.dart';

/// Product detail.
///
/// Shape: the carousel runs full-bleed to the top of the screen (under the
/// status bar) at a 4:5 portrait crop, and the content rides up over it on
/// a sheet with rounded top corners. The old screen used a fixed square
/// and a flat content column, which cropped every photo identically and
/// left the buy action stranded mid-scroll.
///
/// The action bar is pinned. Price sits on the left of it so the number
/// and the button that acts on it are never separated.
class ProductDetailsScreen extends StatefulWidget {
  const ProductDetailsScreen({
    super.key,
    required this.productId,
    this.initialProduct,
  });

  final String productId;
  final Product? initialProduct;

  @override
  State<ProductDetailsScreen> createState() => _ProductDetailsScreenState();
}

class _ProductDetailsScreenState extends State<ProductDetailsScreen> {
  Product? _product;
  bool _loading = true;
  String? _error;

  /// The server says this listing is gone — deleted, removed by the
  /// seller, or the shop is no longer approved. Opening a shared link to
  /// one used to crash (`_product!` on null), and opening one from a stale
  /// grid kept offering Add to basket for something nobody can buy.
  bool _gone = false;
  bool _saved = false;
  int _currentImage = 0;
  final _pageController = PageController();

  /// Drives the header: glass buttons over the photo, then a solid bar
  /// with the title once the photo has scrolled away.
  final _scroll = ScrollController();
  double _scrolled = 0;

  /// Guards the in-app contact button — creating the conversation is a
  /// round trip, and a double-tap would open two threads with the seller.
  bool _openingChat = false;

  /// The store behind the listing — its rating, delivery and payment
  /// details. Best-effort: the page works without it.
  Seller? _seller;

  /// The same shop's other listings for sale.
  List<Product> _moreFromShop = const [];

  /// Adaptive colour from the product's first photo (see the sheet).
  Color? _tint;
  String? _tintFor;

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  Future<void> _loadTint(Product p) async {
    final url = p.firstImage;
    if (url.isEmpty || url == _tintFor) return;
    _tintFor = url;
    final tint = await PhotoTint.forPhoto(url);
    if (mounted && _tintFor == url) setState(() => _tint = tint);
  }

  static const double _sheetOverlap = 24;

  @override
  void initState() {
    super.initState();
    _product = widget.initialProduct;
    _loading = widget.initialProduct == null;
    _bootstrap();
    _loadSaved();
    _loadAdmin();
    if (widget.initialProduct != null) _loadShop(widget.initialProduct!);
    _scroll.addListener(() {
      final v = _scroll.offset;
      // Only rebuild across the band where the header is changing.
      if ((v < 400 || _scrolled < 400) && mounted) {
        setState(() => _scrolled = v);
      }
    });
    CartService.revision.addListener(_onCartChanged);
  }

  void _onCartChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadShop(Product p) async {
    _loadTint(p);
    if (p.sellerId.isEmpty) return;
    try {
      final results = await Future.wait([
        SellerService.fetchSellerByAuthUserId(p.sellerId),
        SellerService.fetchPublicProductsByAuthUserId(p.sellerId),
      ]);
      if (!mounted) return;
      setState(() {
        _seller = results[0] as Seller?;
        // products has no seller-name column; these are all this shop's.
        final name = _seller?.businessName ?? p.sellerName;
        _moreFromShop = [
          for (final x in results[1] as List<Product>)
            if (x.id != p.id)
              Product.fromJson({...x.toJson(), 'seller_name': name}),
        ].take(10).toList();
      });
    } catch (_) {
      // Seller extras just don't show.
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _scroll.dispose();
    CartService.revision.removeListener(_onCartChanged);
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      final fetched = await MarketplaceService.fetchProductById(
        widget.productId,
      );
      if (!mounted) return;
      setState(() {
        if (fetched == null) {
          _gone = true;
          _product = null;
        } else {
          _product = fetched;
        }
        _loading = false;
      });
      // Only listings someone else is selling, and only while for sale —
      // your own stock isn't "recently viewed".
      if (fetched != null && _seller == null) _loadShop(fetched);
      if (fetched != null &&
          fetched.status == 'available' &&
          fetched.sellerId != AuthService.currentUser?.id) {
        RecentlyViewedService.add(fetched);
        MarketplaceService.recordView(fetched.id);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load product.';
        _loading = false;
      });
    }
  }

  Future<void> _loadSaved() async {
    try {
      final saved = await MarketplaceService.isSaved(widget.productId);
      if (mounted) setState(() => _saved = saved);
    } catch (_) {
      // Signed out — heart stays hollow and taps prompt to sign in.
    }
  }

  Future<void> _toggleSave() async {
    final was = _saved;
    setState(() => _saved = !was);
    try {
      if (was) {
        await MarketplaceService.unsaveProduct(widget.productId);
      } else {
        await MarketplaceService.saveProduct(widget.productId);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _saved = was);
      // Every failure used to say "Sign in", including a signed-in member
      // with no signal.
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

  Future<void> _addToCart() async {
    final product = _product;
    if (product == null) return;
    if (product.sellerId == AuthService.currentUser?.id) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'This is your own listing.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
      return;
    }
    await CartService.add(product);
    // No confirmation toast: the basket badge in the header increments, which
    // is the feedback, and the bar that used to restate it is gone. A haptic
    // acknowledges the tap without occupying the screen.
    await HapticFeedback.mediumImpact();
  }

  Future<void> _shareProduct() async {
    final product = _product;
    if (product == null) return;
    final shareUrl = productShareUrl(product.id);
    final text =
        '${product.title}\n\n'
        'For sale on Adventist Super App marketplace:\n$shareUrl';
    try {
      await Share.share(text, subject: product.title);
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

  Future<void> _contactSeller() async {
    final phone = _product?.sellerPhone?.trim() ?? '';
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Seller hasn\'t shared a phone number.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
      return;
    }
    AnalyticsService.marketplaceContact(int.tryParse(widget.productId) ?? 0);
    // The listing's own country, which is the seller's — a `07…` typed by a
    // Kenyan seller has to dial +254, not the buyer's code.
    final digits = Countries.toWhatsAppDigits(
      phone,
      countryCode: _product?.country,
    );
    if (digits == null || digits.isEmpty) return;
    // Tag the actual listing, not just its title. A seller with forty
    // products and two called "Church shoes" can't act on a name alone —
    // the link opens the exact one, with its price and photos.
    final product = _product;
    final priceLine = product == null ? '' : ' (${product.formatPrice()})';
    final link = product == null ? '' : '\n\n${productShareUrl(product.id)}';
    final message =
        'Hi, I\'m interested in "${product?.title ?? 'your listing'}"'
        '$priceLine on Adventist Super App.$link';
    final waUri = Uri.parse(
      'https://wa.me/$digits?text=${Uri.encodeComponent(message)}',
    );
    try {
      final ok = await launchUrl(waUri, mode: LaunchMode.externalApplication);
      if (ok) return;
      throw Exception('launch failed');
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: phone));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.darkNavy,
          content: Text(
            'WhatsApp not installed. Number copied: $phone',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    }
  }

  /// Message the seller inside the app.
  ///
  /// The second contact route, restored. It was removed when the two
  /// unlabelled speech-bubble glyphs here were collapsed into one — but
  /// the fix for "which bubble reaches the seller?" is a label, not the
  /// loss of in-app chat, and a buyer without WhatsApp had no way to ask
  /// a question at all.
  ///
  /// Hands the listing to the chat as a product card rather than as text:
  /// `ChatLaunchIntent` fills the composer with an editable opener and
  /// pins the thumbnail/title/price above it, and the first message goes
  /// out as `message_type='product'` so the seller's bubble is tappable
  /// straight back to this exact listing. Same primitive as
  /// [OrderHandoff.viaAdventChat].
  Future<void> _messageSellerInApp() async {
    final product = _product;
    if (product == null || _openingChat) return;
    if (product.sellerId.isEmpty) {
      _toast('This seller can\'t be messaged in the app. Try WhatsApp.');
      return;
    }
    setState(() => _openingChat = true);
    final router = GoRouter.of(context);
    try {
      AnalyticsService.marketplaceContact(int.tryParse(widget.productId) ?? 0);
      final convo = await MessagingService.createConversation(
        otherUserId: product.sellerId,
        otherUserName: product.sellerName,
        source: 'marketplace',
        isBusiness: true,
      ).timeout(const Duration(seconds: 15));
      // No share link in the draft — the product card riding alongside it
      // already points at the listing, and a raw URL in the opener reads
      // like spam.
      ChatLaunchIntent.set(
        draft:
            'Hi, I\'m interested in "${product.title}" '
            '(${product.formatPrice()}). Is it still available?',
        productId: product.id.toString(),
        productImageUrl: product.firstImage,
        productTitle: product.title,
        productPrice: product.formatPrice(),
      );
      if (!mounted) return;
      router.pushNamed('chat', pathParameters: {'id': convo.id}, extra: convo);
    } catch (_) {
      if (!mounted) return;
      _toast('Could not open the chat. Try WhatsApp instead.');
    } finally {
      if (mounted) setState(() => _openingChat = false);
    }
  }

  bool _isOwnListing(Product p) => p.sellerId == AuthService.currentUser?.id;

  bool _isSuperAdmin = false;
  bool _moderating = false;

  Future<void> _loadAdmin() async {
    final admin = await SellerService.isCurrentUserSuperAdmin();
    if (mounted && admin) setState(() => _isSuperAdmin = true);
  }

  Future<void> _adminHide(Product product) async {
    final reason = await showModerationReasonDialog(
      context,
      what: 'listing',
      defaultReason:
          'It claims to treat or cure a medical condition, which '
          'the marketplace guidelines do not allow.',
    );
    if (reason == null || !mounted) return;
    setState(() => _moderating = true);
    try {
      await SellerService.adminSetProductStatus(
        productId: product.id,
        hidden: true,
        reason: reason,
      );
      if (!mounted) return;
      _toast('Listing hidden. The seller has been told why.');
      Navigator.of(context).maybePop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _moderating = false);
      _toast(
        e.toString().contains('admin_set_product_status')
            ? 'Hiding needs database patch_272 to be run first.'
            : 'Could not hide this listing. Try again.',
      );
    }
  }

  /// After an appeal: make the listing visible again. Only reachable by
  /// super admins, who can open a hidden listing (patch_272).
  Future<void> _adminRestore(Product product) async {
    setState(() => _moderating = true);
    try {
      await SellerService.adminSetProductStatus(
        productId: product.id,
        hidden: false,
      );
      if (!mounted) return;
      _toast('Listing restored. The seller has been told.');
      await _bootstrap();
    } catch (_) {
      if (mounted) _toast('Could not restore this listing. Try again.');
    } finally {
      if (mounted) setState(() => _moderating = false);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.darkNavy,
        content: Text(
          message,
          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  //  Layout (premium redesign, 28 Oct 2026)
  //
  //  One idea per band, separated by space and hairlines rather than a
  //  stack of identical cards:
  //    gallery → who sells it → what it is → what it costs → key facts →
  //    about → how you get it → the shop → more from the shop → buy safely.
  //  The header is glass over the photo and turns into a solid bar with
  //  the title once the photo scrolls away. One primary action at the
  //  bottom; the two ways to reach the seller live behind "Contact".
  // ---------------------------------------------------------------------

  static const double _galleryAspect = 4 / 5;

  @override
  Widget build(BuildContext context) {
    final product = _product;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          _buildBody(),
          if (product != null && !_gone) _buildTopBar(product),
        ],
      ),
      bottomNavigationBar: product == null || _gone
          ? null
          : _BuyBar(
              product: product,
              own: _isOwnListing(product),
              inBasket: CartService.contains(product.id),
              chatBusy: _openingChat,
              onAdd: _addToCart,
              onViewBasket: () => context.pushNamed('cart'),
              onContact: _openContactSheet,
              onManage: () => context.pushNamed('seller_dashboard'),
            ),
    );
  }

  /// Glass circles over the photo; past it, a solid flat bar with the
  /// title. It's pinned over scrolling content, so it is opaque once it
  /// appears (CLAUDE.md: pinned headers are opaque).
  Widget _buildTopBar(Product product) {
    final galleryHeight = MediaQuery.sizeOf(context).width / _galleryAspect;
    final t = ((_scrolled - (galleryHeight - 140)) / 80).clamp(0.0, 1.0);
    final palette = context.palette;
    final solid = t > 0.5;
    Widget btn(IconData icon, VoidCallback onTap, {Color? tint, String? tip}) =>
        _HeaderButton(
          icon: icon,
          onTap: onTap,
          tint: tint,
          solid: solid,
          tooltip: tip,
        );
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
                btn(
                  Icons.arrow_back_rounded,
                  () => context.canPop()
                      ? context.pop()
                      : context.goNamed('marketplace'),
                  tip: 'Back',
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Opacity(
                    opacity: t,
                    child: Text(
                      product.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.titleSmall.copyWith(
                        color: palette.text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                btn(
                  _saved
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  _toggleSave,
                  tint: _saved ? AppColors.red : null,
                  tip: _saved ? 'Remove from saved' : 'Save',
                ),
                const SizedBox(width: 8),
                btn(Icons.ios_share_rounded, _shareProduct, tip: 'Share'),
                const SizedBox(width: 8),
                CartBadgeButton(onTap: () => context.pushNamed('cart')),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_gone) return _buildGone();
    if (_loading && _product == null) {
      return const Center(child: BrandSpinner(size: 34));
    }
    if (_error != null && _product == null) {
      return _buildError();
    }
    final product = _product!;
    final palette = context.palette;
    return CustomScrollView(
      controller: _scroll,
      slivers: [
        SliverToBoxAdapter(child: _buildGallery(product)),
        SliverToBoxAdapter(
          child: Transform.translate(
            offset: const Offset(0, -_sheetOverlap),
            child: Container(
              decoration: BoxDecoration(
                color: palette.scaffoldBg,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  // Adaptive colour (owner-approved, 28 Oct 2026): a faint
                  // wash of the product photo's own colour across the top
                  // of the sheet, fading out. Background only — text,
                  // price and buttons keep the palette. PhotoTint returns
                  // null for green, pink and dull photos: no wash then.
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: 460,
                    child: IgnorePointer(
                      child: AnimatedOpacity(
                        opacity: _tint == null ? 0 : 1,
                        duration: const Duration(milliseconds: 500),
                        child: _tint == null
                            ? const SizedBox.shrink()
                            : DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      _tint!.withValues(
                                        alpha: _isDark ? 0.26 : 0.18,
                                      ),
                                      _tint!.withValues(
                                        alpha: _isDark ? 0.10 : 0.07,
                                      ),
                                      _tint!.withValues(alpha: 0),
                                    ],
                                    stops: const [0, 0.45, 1],
                                  ),
                                ),
                              ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        StaggeredReveal(index: 0, child: _buildIntro(product)),
                        if (product.isModerated && _isOwnListing(product))
                          Padding(
                            padding: const EdgeInsets.only(top: AppSpace.lg),
                            child: ModeratedBanner(
                              kind: ModeratedKind.listing,
                              itemId: product.id,
                              title: product.title,
                              reason: product.moderationReason,
                            ),
                          ),
                        const SizedBox(height: 18),
                        StaggeredReveal(index: 1, child: _buildSpecs(product)),
                        if (product.description?.trim().isNotEmpty == true)
                          _Section(
                            title: 'About this item',
                            child: ExpandableText(
                              text: product.description!.trim(),
                              collapsedLines: 5,
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: palette.text,
                                height: 1.6,
                              ),
                            ),
                          ),
                        if (_seller != null)
                          _Section(
                            title: 'Delivery & pickup',
                            child: _buildFulfilment(_seller!),
                          ),
                        _Section(title: 'Sold by', child: _buildShop(product)),
                        if (_moreFromShop.isNotEmpty)
                          _buildMoreFromShop(product),
                        const SizedBox(height: 28),
                        _buildFooter(product),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Shared frame for the full-screen notices. The details screen has no
  /// app bar (the photo runs under the status bar), so without this the
  /// only way out of an error was the system back gesture.
  Widget _noticeFrame(Widget child) {
    return SafeArea(
      child: Stack(
        children: [
          Center(child: child),
          const Positioned(top: 4, left: 4, child: BackButton()),
        ],
      ),
    );
  }

  Widget _buildGone() {
    final palette = context.palette;
    return _noticeFrame(
      Padding(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.remove_shopping_cart_outlined,
              size: 48,
              color: palette.textMuted,
            ),
            const SizedBox(height: AppSpace.md),
            Text(
              'This listing is no longer available',
              textAlign: TextAlign.center,
              style: AppTextStyles.titleMedium.copyWith(
                color: palette.text,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpace.sm),
            Text(
              'The seller may have sold or removed it.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(
                color: palette.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return _noticeFrame(
      Padding(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.red),
            const SizedBox(height: AppSpace.md),
            Text(_error!, style: AppTextStyles.bodyMedium),
            const SizedBox(height: AppSpace.lg),
            FilledButton(
              onPressed: () {
                setState(() {
                  _loading = true;
                  _error = null;
                });
                _bootstrap();
              },
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                shape: RoundedRectangleBorder(
                  borderRadius: AppRadius.buttonAll,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: AppSpace.md,
                ),
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  // ----- Gallery --------------------------------------------------------

  Widget _buildGallery(Product product) {
    final images = product.imageUrls;
    final unavailable = !product.isAvailable;
    return Stack(
      children: [
        AspectRatio(
          aspectRatio: _galleryAspect,
          child: images.isEmpty
              ? _GalleryPlaceholder(category: product.category)
              : PageView.builder(
                  controller: _pageController,
                  itemCount: images.length,
                  onPageChanged: (i) => setState(() => _currentImage = i),
                  itemBuilder: (context, i) {
                    final image = GestureDetector(
                      onTap: () => _GalleryViewer.open(context, images, i),
                      child: CachedImage(
                        images[i],
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            _GalleryPlaceholder(category: product.category),
                      ),
                    );
                    return i == 0
                        ? Hero(tag: 'product_image_${product.id}', child: image)
                        : image;
                  },
                ),
        ),
        // Soft scrim under the glass buttons only.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 120,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.30),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),
        if (unavailable)
          Positioned.fill(
            child: IgnorePointer(
              child: ColoredBox(color: Colors.black.withValues(alpha: 0.35)),
            ),
          ),
        if (images.length > 1)
          Positioned(
            right: 16,
            bottom: _sheetOverlap + 12,
            child: _Pill(
              text: '${_currentImage + 1} / ${images.length}',
              dark: true,
            ),
          ),
      ],
    );
  }

  // ----- Intro: shop line, title, price, status ----------------------------

  Widget _buildIntro(Product product) {
    final palette = context.palette;
    final s = _seller;
    final status = product.isAvailable
        ? null
        : product.isSold
        ? 'Sold'
        : 'Reserved';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Who sells it, first — the way the best shops do it. Tappable.
        InkWell(
          onTap: product.sellerId.isEmpty ? null : () => _openStore(product),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    product.sellerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.labelLarge.copyWith(
                      color: AppColors.primaryBlue,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (product.sellerVerified) const VerifiedTick(size: 14),
                if ((s?.ratingCount ?? 0) > 0) ...[
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.star_rounded,
                    size: 15,
                    color: AppColors.goldAccent,
                  ),
                  Text(
                    ' ${s!.rating.toStringAsFixed(1)}',
                    style: AppTextStyles.labelMedium.copyWith(
                      color: palette.text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    ' (${s.ratingCount})',
                    style: AppTextStyles.labelMedium.copyWith(
                      color: palette.textMuted,
                    ),
                  ),
                ],
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: palette.textMuted,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          product.title,
          style: AppTextStyles.headlineSmall.copyWith(
            color: palette.text,
            fontWeight: FontWeight.w600,
            fontSize: 22,
            height: 1.28,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              product.formatPrice(),
              style: AppTextStyles.displayMedium.copyWith(
                color: palette.text,
                fontWeight: FontWeight.w700,
                fontSize: 30,
                height: 1,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(width: 12),
            if (status == null)
              const _StatusPill(text: 'Available', ok: true)
            else
              _StatusPill(text: status, ok: false),
          ],
        ),
      ],
    );
  }

  // ----- Key facts as quiet chips --------------------------------------------

  Widget _buildSpecs(Product product) {
    final chips = <(IconData, String)>[
      if (product.conditionLabel != null)
        (Icons.auto_awesome_outlined, product.conditionLabel!),
      if (product.category?.isNotEmpty == true)
        (Icons.category_outlined, _categoryLabel(product.category!)),
      if (product.subcategory?.trim().isNotEmpty == true)
        (Icons.sell_outlined, product.subcategory!.trim()),
      if (product.locationLine != null)
        (Icons.place_outlined, product.locationLine!),
    ];
    if (chips.isEmpty) return const SizedBox.shrink();
    final palette = context.palette;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final c in chips)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: palette.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: palette.divider),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(c.$1, size: 15, color: AppColors.primaryBlue),
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 220),
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
    );
  }

  // ----- Delivery & pickup ----------------------------------------------------

  Widget _buildFulfilment(Seller s) {
    final rows = <(IconData, String, String)>[
      if (s.offersDelivery)
        (
          Icons.local_shipping_outlined,
          'Delivery available',
          [
            if ((s.deliveryArea ?? '').trim().isNotEmpty)
              s.deliveryArea!.trim(),
            if ((s.deliveryFee ?? '').trim().isNotEmpty)
              'Fee ${s.deliveryFee!.trim()}',
          ].join(' · ').ifEmpty('Ask the shop about your area'),
        )
      else
        (
          Icons.storefront_outlined,
          'Collection',
          'Pick up from the shop${(s.city ?? '').isEmpty ? '' : ' in ${s.city}'}',
        ),
      if ((s.paymentMethods ?? '').trim().isNotEmpty)
        (
          Icons.account_balance_wallet_outlined,
          'Payment',
          s.paymentMethods!.trim(),
        ),
      if (s.observesSabbath)
        (
          Icons.brightness_3_outlined,
          'Keeps the Sabbath',
          (s.sabbathNoticeText ?? '').trim().isNotEmpty
              ? s.sabbathNoticeText!.trim()
              : 'Closed Friday sunset to Saturday sunset',
        ),
    ];
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.primaryBlue.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(r.$1, size: 18, color: AppColors.primaryBlue),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.$2,
                        style: AppTextStyles.labelLarge.copyWith(
                          color: palette.text,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        r.$3,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: palette.textMuted,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        Text(
          'You arrange payment and handover with the shop directly — '
          'Adventist Super App never takes payment.',
          style: AppTextStyles.bodySmall.copyWith(
            color: palette.textMuted,
            fontSize: 11.5,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  // ----- The shop ---------------------------------------------------------------

  void _openStore(Product product) => context.pushNamed(
    'seller_profile',
    pathParameters: {'userId': product.sellerId},
  );

  Widget _buildShop(Product product) {
    final palette = context.palette;
    final s = _seller;
    final logo = s?.profilePhotoUrl;
    final rated = (s?.ratingCount ?? 0) > 0;
    final meta = [
      if (rated)
        '${s!.rating.toStringAsFixed(1)} · ${s.ratingCount} review${s.ratingCount == 1 ? '' : 's'}'
      else if (s != null)
        'New shop',
      if ((s?.city ?? '').isNotEmpty) s!.city!,
      if (s?.createdAt != null) 'Since ${s!.createdAt!.year}',
    ].join('  ·  ');
    final initials = product.sellerName.trim().isEmpty
        ? '?'
        : product.sellerName.trim()[0].toUpperCase();
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            width: 52,
            height: 52,
            child: (logo ?? '').isEmpty
                ? DecoratedBox(
                    decoration: const BoxDecoration(
                      gradient: AppColors.primaryGradient,
                    ),
                    child: Center(
                      child: Text(
                        initials,
                        style: AppTextStyles.titleLarge.copyWith(
                          color: AppColors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  )
                : CachedImage(logo!, fit: BoxFit.cover),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      product.sellerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.titleSmall.copyWith(
                        color: palette.text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (product.sellerVerified) const VerifiedTick(size: 14),
                ],
              ),
              if (meta.isNotEmpty) ...[
                const SizedBox(height: 3),
                Row(
                  children: [
                    if (rated) ...[
                      const Icon(
                        Icons.star_rounded,
                        size: 14,
                        color: AppColors.goldAccent,
                      ),
                      const SizedBox(width: 3),
                    ],
                    Flexible(
                      child: Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: palette.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton(
          onPressed: product.sellerId.isEmpty
              ? null
              : () => _openStore(product),
          style: OutlinedButton.styleFrom(
            foregroundColor: palette.text,
            side: BorderSide(color: palette.divider),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            // The theme's buttons are full-width; this one sits in a row.
            minimumSize: const Size(0, 40),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Text(
            'Visit',
            style: AppTextStyles.labelLarge.copyWith(
              color: palette.text,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMoreFromShop(Product product) {
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'More from this shop',
                  style: AppTextStyles.titleMedium.copyWith(
                    color: context.palette.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => _openStore(product),
                child: const Text('See all'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 252,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              itemCount: _moreFromShop.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, i) {
                final p = _moreFromShop[i];
                return SizedBox(
                  width: 156,
                  child: ProductTile(
                    product: p,
                    onTap: () => context.pushReplacementNamed(
                      'product_details',
                      pathParameters: {'id': p.id},
                      extra: p,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ----- Footer: buy safely, report, admin -------------------------------------

  Widget _buildFooter(Product product) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!_isOwnListing(product))
          Material(
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
          ),
        if (!_isOwnListing(product))
          Wrap(
            alignment: WrapAlignment.center,
            children: [
              TextButton.icon(
                onPressed: () => showReportSheet(
                  context,
                  contentType: 'product',
                  contentId: product.id,
                  contentLabel: product.title,
                ),
                icon: const Icon(Icons.flag_outlined, size: 16),
                label: const Text('Report this listing'),
                style: TextButton.styleFrom(foregroundColor: palette.textMuted),
              ),
              if (_isSuperAdmin)
                TextButton.icon(
                  onPressed: _moderating
                      ? null
                      : () => product.isModerated
                            ? _adminRestore(product)
                            : _adminHide(product),
                  icon: Icon(
                    product.isModerated
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 16,
                  ),
                  label: Text(
                    product.isModerated
                        ? 'Restore listing (admin)'
                        : 'Hide listing (admin)',
                  ),
                  style: TextButton.styleFrom(foregroundColor: AppColors.red),
                ),
            ],
          ),
      ],
    );
  }

  // ----- Contact sheet ----------------------------------------------------------

  Future<void> _openContactSheet() async {
    final product = _product;
    if (product == null) return;
    final palette = context.palette;
    final hasPhone = (product.sellerPhone ?? '').trim().isNotEmpty;
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
                'Contact ${product.sellerName}',
                style: AppTextStyles.titleLarge.copyWith(
                  color: palette.text,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Ask about the item, delivery or a time to collect.',
                style: AppTextStyles.bodySmall.copyWith(
                  color: palette.textMuted,
                ),
              ),
              const SizedBox(height: 16),
              _ContactOption(
                icon: Icons.forum_rounded,
                title: 'Message in the app',
                subtitle: 'The listing is attached to your message',
                onTap: () => Navigator.pop(ctx, 'chat'),
              ),
              if (hasPhone) ...[
                const SizedBox(height: 10),
                _ContactOption(
                  icon: Icons.chat_rounded,
                  title: 'WhatsApp',
                  subtitle: 'Opens WhatsApp with a link to this listing',
                  onTap: () => Navigator.pop(ctx, 'whatsapp'),
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (choice == 'chat') await _messageSellerInApp();
    if (choice == 'whatsapp') await _contactSeller();
  }
}

String _categoryLabel(String id) {
  for (final c in ProductCategory.all) {
    if (c.id == id) return c.label;
  }
  return id[0].toUpperCase() + id.substring(1);
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

/// A titled band: generous space above, a hairline, then the content.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Divider(height: 1, color: palette.divider),
          const SizedBox(height: 20),
          Text(
            title,
            style: AppTextStyles.titleMedium.copyWith(
              color: palette.text,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.text, required this.ok});
  final String text;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    // Success green is for status badges — this is one.
    final color = ok ? AppColors.successGreen : AppColors.red;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: AppTextStyles.labelSmall.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, this.dark = false});
  final String text;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: AppTextStyles.labelSmall.copyWith(
          color: AppColors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.icon,
    required this.onTap,
    required this.solid,
    this.tint,
    this.tooltip,
  });
  final IconData icon;
  final VoidCallback onTap;
  final bool solid;
  final Color? tint;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final button = Pressable(
      onTap: onTap,
      pressedScale: 0.9,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: solid ? palette.card : Colors.black.withValues(alpha: 0.32),
          shape: BoxShape.circle,
          border: solid ? Border.all(color: palette.divider) : null,
        ),
        child: Icon(
          icon,
          size: 20,
          color: tint ?? (solid ? palette.text : AppColors.white),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

class _GalleryPlaceholder extends StatelessWidget {
  const _GalleryPlaceholder({this.category});
  final String? category;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.palette.cardMuted,
      child: Center(
        child: Icon(
          Icons.shopping_bag_outlined,
          size: 72,
          color: context.palette.textMuted.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}

/// Full-screen gallery: swipe between every photo, pinch to zoom each.
class _GalleryViewer extends StatefulWidget {
  const _GalleryViewer({required this.images, required this.initial});
  final List<String> images;
  final int initial;

  static Future<void> open(BuildContext context, List<String> images, int i) {
    return Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (_, _, _) => _GalleryViewer(images: images, initial: i),
        transitionsBuilder: (_, a, _, child) =>
            FadeTransition(opacity: a, child: child),
      ),
    );
  }

  @override
  State<_GalleryViewer> createState() => _GalleryViewerState();
}

class _GalleryViewerState extends State<_GalleryViewer> {
  late final _controller = PageController(initialPage: widget.initial);
  late int _index = widget.initial;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: widget.images.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (_, i) => InteractiveViewer(
              minScale: 1,
              maxScale: 4,
              child: Center(
                child: CachedImage(widget.images[i], fit: BoxFit.contain),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: AppColors.white,
                    ),
                    tooltip: 'Close',
                  ),
                  const Spacer(),
                  if (widget.images.length > 1)
                    _Pill(text: '${_index + 1} / ${widget.images.length}'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactOption extends StatelessWidget {
  const _ContactOption({
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
    final palette = context.palette;
    return Material(
      color: palette.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: palette.divider),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: AppColors.primaryBlue, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTextStyles.labelLarge.copyWith(
                        color: palette.text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      subtitle,
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

/// The pinned purchase bar: one secondary (Contact) and one primary action.
/// The primary morphs once the item is in the basket, so the tap has a
/// visible answer without a toast.
class _BuyBar extends StatelessWidget {
  const _BuyBar({
    required this.product,
    required this.own,
    required this.inBasket,
    required this.chatBusy,
    required this.onAdd,
    required this.onViewBasket,
    required this.onContact,
    required this.onManage,
  });

  final Product product;
  final bool own;
  final bool inBasket;
  final bool chatBusy;
  final VoidCallback onAdd;
  final VoidCallback onViewBasket;
  final VoidCallback onContact;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final available = product.isAvailable;

    Widget primary;
    if (own) {
      primary = _PrimaryButton(
        icon: Icons.storefront_outlined,
        label: 'Manage in your shop',
        onTap: onManage,
      );
    } else if (!available) {
      primary = _PrimaryButton(
        icon: Icons.block_rounded,
        label: product.isSold ? 'Sold' : 'Reserved',
        onTap: null,
      );
    } else if (inBasket) {
      primary = _PrimaryButton(
        icon: Icons.check_rounded,
        label: 'In basket · View',
        onTap: onViewBasket,
        tonal: true,
      );
    } else {
      primary = _PrimaryButton(
        icon: Icons.add_shopping_cart_rounded,
        label: 'Add to basket',
        onTap: onAdd,
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: palette.card,
        border: Border(top: BorderSide(color: palette.divider)),
        boxShadow: AppShadows.floating(context),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              if (!own) ...[
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 52,
                    child: OutlinedButton.icon(
                      onPressed: chatBusy ? null : onContact,
                      icon: chatBusy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: BrandSpinner(size: 16),
                            )
                          : const Icon(
                              Icons.chat_bubble_outline_rounded,
                              size: 18,
                            ),
                      label: const Text('Contact'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: palette.text,
                        side: BorderSide(color: palette.divider),
                        minimumSize: const Size(0, 52),
                        textStyle: AppTextStyles.labelLarge.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(flex: 3, child: primary),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.tonal = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool tonal;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    final fg = tonal ? AppColors.primaryBlue : AppColors.white;
    return Semantics(
      button: true,
      label: label,
      child: Pressable(
        onTap: onTap,
        haptics: true,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          height: 52,
          decoration: BoxDecoration(
            gradient: tonal || disabled ? null : AppColors.primaryGradient,
            color: tonal
                ? AppColors.primaryBlue.withValues(alpha: 0.12)
                : disabled
                ? context.palette.cardMuted
                : null,
            borderRadius: BorderRadius.circular(14),
            boxShadow: tonal || disabled ? null : AppShadows.glow(context),
          ),
          alignment: Alignment.center,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 19,
                  color: disabled ? context.palette.textMuted : fg,
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: AppTextStyles.buttonText.copyWith(
                    fontSize: 15,
                    color: disabled ? context.palette.textMuted : fg,
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
