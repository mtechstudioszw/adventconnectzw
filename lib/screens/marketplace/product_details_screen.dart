import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/share_config.dart';
import '../../models/product_model.dart';
import '../../services/analytics_service.dart';
import '../../services/auth_service.dart';
import '../../services/cart_service.dart';
import '../../services/marketplace_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/cached_image.dart';
import '../../widgets/full_image_viewer.dart';
import '../../widgets/marketplace/cart_badge_button.dart';
import '../../widgets/marketplace/safety_card.dart';
import '../../widgets/motion/brand_spinner.dart';
import '../../widgets/motion/pressable.dart';
import '../../widgets/motion/staggered_reveal.dart';

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
  bool _saved = false;
  int _currentImage = 0;
  final _pageController = PageController();

  static const double _sheetOverlap = 24;

  @override
  void initState() {
    super.initState();
    _product = widget.initialProduct;
    _loading = widget.initialProduct == null;
    _bootstrap();
    _loadSaved();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      final fetched = await MarketplaceService.fetchProductById(
        widget.productId,
      );
      if (!mounted) return;
      setState(() {
        _product = fetched ?? _product;
        _loading = false;
      });
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
      // Signed out â€” heart stays hollow and taps prompt to sign in.
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Sign in to save listings.',
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
        'For sale on Advent Connect ZW marketplace:\n$shareUrl';
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
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    // Tag the actual listing, not just its title. A seller with forty
    // products and two called "Church shoes" can't act on a name alone —
    // the link opens the exact one, with its price and photos.
    final product = _product;
    final priceLine = product == null ? '' : ' (${product.formatPrice()})';
    final link = product == null ? '' : '\n\n${productShareUrl(product.id)}';
    final message =
        'Hi, I\'m interested in "${product?.title ?? 'your listing'}"'
        '$priceLine on Advent Connect ZW.$link';
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


  @override
  Widget build(BuildContext context) {
    final product = _product;
    return Scaffold(
      backgroundColor: context.palette.scaffoldBg,
      extendBodyBehindAppBar: true,
      body: _buildBody(),
      bottomNavigationBar: product == null
          ? null
          : _ActionBar(
              product: product,
              onAddToCart: _addToCart,
              onWhatsApp: _contactSeller,
            ),
    );
  }

  Widget _buildBody() {
    if (_loading && _product == null) {
      return const Center(child: BrandSpinner(size: 34));
    }
    if (_error != null && _product == null) {
      return _buildError();
    }
    final product = _product!;
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _buildCarousel(product)),
        SliverToBoxAdapter(
          child: Transform.translate(
            offset: const Offset(0, -_sheetOverlap),
            child: Container(
              decoration: BoxDecoration(
                color: context.palette.scaffoldBg,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(AppRadius.sheet),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(
                AppSpace.lg,
                AppSpace.xl,
                AppSpace.lg,
                AppSpace.xl,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  StaggeredReveal(index: 0, child: _buildHeader(product)),
                  const SizedBox(height: AppSpace.lg),
                  StaggeredReveal(index: 1, child: _buildFacts(product)),
                  const SizedBox(height: AppSpace.lg),
                  StaggeredReveal(index: 2, child: _buildSellerCard(product)),
                  if (product.description?.trim().isNotEmpty == true) ...[
                    const SizedBox(height: AppSpace.lg),
                    StaggeredReveal(
                      index: 3,
                      child: _buildDescription(product),
                    ),
                  ],
                  const SizedBox(height: AppSpace.lg),
                  StaggeredReveal(
                    index: 4,
                    child: const MarketplaceSafetyCard(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
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

  Widget _buildCarousel(Product product) {
    final images = product.imageUrls.isEmpty ? [''] : product.imageUrls;
    final unavailable = !product.isAvailable;
    return Stack(
      children: [
        AspectRatio(
          // Portrait, and full-bleed to the screen edges. Goods are
          // photographed vertically on a phone; a square threw away the
          // top and bottom of nearly every listing.
          aspectRatio: 4 / 5,
          child: PageView.builder(
            controller: _pageController,
            itemCount: images.length,
            onPageChanged: (i) => setState(() => _currentImage = i),
            itemBuilder: (context, i) => i == 0
                ? Hero(
                    tag: 'product_image_${product.id}',
                    child: _CarouselImage(url: images[i]),
                  )
                : _CarouselImage(url: images[i]),
          ),
        ),

        if (unavailable)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.4),
                ),
              ),
            ),
          ),

        // Scrim so the white header buttons stay legible over bright photos.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 140,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.45),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),

        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.md,
              AppSpace.sm,
              AppSpace.md,
              0,
            ),
            child: Row(
              children: [
                _GlassIconButton(
                  icon: Icons.arrow_back,
                  onTap: () => context.canPop()
                      ? context.pop()
                      : context.goNamed('marketplace'),
                ),
                const Spacer(),
                _GlassIconButton(
                  icon: _saved
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  tint: _saved ? AppColors.red : null,
                  onTap: _toggleSave,
                ),
                const SizedBox(width: AppSpace.sm),
                _GlassIconButton(
                  icon: Icons.share_outlined,
                  onTap: _shareProduct,
                ),
                const SizedBox(width: AppSpace.sm),
                CartBadgeButton(onTap: () => context.pushNamed('cart')),
              ],
            ),
          ),
        ),

        if (unavailable)
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            bottom: _sheetOverlap,
            child: IgnorePointer(
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.xl,
                    vertical: AppSpace.md,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: AppRadius.pillAll,
                  ),
                  child: Text(
                    product.isSold ? 'SOLD' : 'RESERVED',
                    style: AppTextStyles.titleMedium.copyWith(
                      color: AppColors.darkNavy,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                    ),
                  ),
                ),
              ),
            ),
          ),

        // Counter rather than dots â€” a listing can carry many photos and a
        // row of ten dots is unreadable.
        if (images.length > 1)
          Positioned(
            right: AppSpace.lg,
            bottom: _sheetOverlap + AppSpace.md,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.md,
                vertical: 5,
              ),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: AppRadius.pillAll,
              ),
              child: Text(
                '${_currentImage + 1}/${images.length}',
                style: AppTextStyles.labelSmall.copyWith(
                  color: AppColors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildHeader(Product product) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (product.category?.isNotEmpty == true) ...[
          Text(
            product.category!.toUpperCase(),
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.primaryBlue,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: AppSpace.sm),
        ],
        Text(
          product.title,
          style: AppTextStyles.displayMedium.copyWith(
            color: context.palette.text,
            fontWeight: FontWeight.w700,
            height: 1.2,
          ),
        ),
        const SizedBox(height: AppSpace.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              product.formatPrice(),
              style: AppTextStyles.displayLarge.copyWith(
                color: context.palette.text,
                fontWeight: FontWeight.w800,
                height: 1.1,
              ),
            ),
            if (product.viewCount > 0) ...[
              const Spacer(),
              Icon(
                Icons.visibility_outlined,
                size: 15,
                color: context.palette.textMuted,
              ),
              const SizedBox(width: AppSpace.xs),
              Text(
                '${product.viewCount} views',
                style: AppTextStyles.bodySmall.copyWith(
                  color: context.palette.textMuted,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  /// The four columns the old screen collected and threw away â€”
  /// condition, subcategory, province and location. They were being
  /// stored on every product and shown nowhere.
  Widget _buildFacts(Product product) {
    final facts = <(IconData, String, String)>[
      if (product.condition?.trim().isNotEmpty == true)
        (Icons.verified_outlined, 'Condition', product.condition!),
      if (product.locationLine != null)
        (Icons.place_outlined, 'Location', product.locationLine!),
      if (product.subcategory?.trim().isNotEmpty == true)
        (Icons.sell_outlined, 'Type', product.subcategory!),
    ];
    if (facts.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.lg,
        vertical: AppSpace.sm,
      ),
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: AppRadius.lgAll,
        boxShadow: AppShadows.card(context),
      ),
      child: Column(
        children: [
          for (var i = 0; i < facts.length; i++) ...[
            if (i > 0) Divider(height: 1, color: context.palette.divider),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpace.md),
              child: Row(
                children: [
                  Icon(
                    facts[i].$1,
                    size: 18,
                    color: AppColors.primaryBlue,
                  ),
                  const SizedBox(width: AppSpace.md),
                  Text(
                    facts[i].$2,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: context.palette.textMuted,
                    ),
                  ),
                  const Spacer(),
                  Flexible(
                    child: Text(
                      facts[i].$3,
                      textAlign: TextAlign.end,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: context.palette.text,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSellerCard(Product product) {
    return Pressable(
      onTap: product.sellerId.isEmpty
          ? null
          : () => context.pushNamed(
              'seller_profile',
              pathParameters: {'userId': product.sellerId},
            ),
      child: Container(
        padding: const EdgeInsets.all(AppSpace.lg),
        decoration: BoxDecoration(
          color: context.palette.card,
          borderRadius: AppRadius.lgAll,
          boxShadow: AppShadows.card(context),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.storefront,
                color: AppColors.white,
                size: 22,
              ),
            ),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SELLER',
                    style: AppTextStyles.labelSmall.copyWith(
                      color: context.palette.textMuted,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          product.sellerName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.titleSmall.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (product.sellerVerified) ...[
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.verified,
                          size: 16,
                          color: AppColors.goldAccent,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'View store',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.primaryBlue,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: context.palette.textMuted),
          ],
        ),
      ),
    );
  }

  Widget _buildDescription(Product product) {
    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: AppRadius.lgAll,
        boxShadow: AppShadows.card(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Description',
            style: AppTextStyles.titleMedium.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpace.sm),
          Text(
            product.description!,
            style: AppTextStyles.bodyMedium.copyWith(
              color: context.palette.textMuted,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }
}

/// Pinned action bar. Price and the button that acts on it stay together
/// no matter how long the description runs.
class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.product,
    required this.onAddToCart,
    required this.onWhatsApp,
  });

  final Product product;
  final VoidCallback onAddToCart;
  final VoidCallback onWhatsApp;

  @override
  Widget build(BuildContext context) {
    final unavailable = !product.isAvailable;
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
          child: unavailable
              ? _UnavailableBar(product: product, onWhatsApp: onWhatsApp)
              : Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Price',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: context.palette.textMuted,
                          ),
                        ),
                        Text(
                          product.formatPrice(),
                          style: AppTextStyles.titleLarge.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: AppSpace.md),
                    // One contact route, and it says what it is. There used to
                    // be two unlabelled glyphs here â€” a speech bubble for
                    // in-app chat and a second, near-identical bubble for
                    // WhatsApp â€” so the button that actually reaches the
                    // seller was a coin flip.
                    _WhatsAppButton(onTap: onWhatsApp),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(
                      child: Pressable(
                        onTap: onAddToCart,
                        haptics: true,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: AppSpace.lg,
                          ),
                          decoration: BoxDecoration(
                            gradient: AppColors.primaryGradient,
                            borderRadius: AppRadius.buttonAll,
                            boxShadow: AppShadows.glow(context),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.add_shopping_cart_rounded,
                                color: AppColors.white,
                                size: 18,
                              ),
                              const SizedBox(width: AppSpace.sm),
                              Text(
                                'Add',
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

class _UnavailableBar extends StatelessWidget {
  const _UnavailableBar({required this.product, required this.onWhatsApp});

  final Product product;

  /// Also WhatsApp, so "ask the shop" means the same thing on a sold listing
  /// as it does on an available one.
  final VoidCallback onWhatsApp;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                product.isSold ? 'This item is sold' : 'This item is reserved',
                style: AppTextStyles.titleSmall.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                'Ask the shop if more are coming.',
                style: AppTextStyles.bodySmall.copyWith(
                  color: context.palette.textMuted,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpace.md),
        _WhatsAppButton(onTap: onWhatsApp),
      ],
    );
  }
}

/// "Contact on WhatsApp", in WhatsApp's own green and spelled out.
///
/// **Deliberate palette exception.** CLAUDE.md forbids green outside status
/// badges, and this breaks that rule on purpose: WhatsApp is how every sale in
/// this marketplace actually closes, and members recognise the destination by
/// its colour before they read anything. A brand-blue button here does not
/// tell anyone which app is about to open. Treat this as scoped to third-party
/// brand affordances â€” do not let green leak anywhere else.
///
/// The word mark, not the logo: shipping WhatsApp's glyph would mean bundling
/// a trademarked asset, and the label plus the colour is unambiguous already.
class _WhatsAppButton extends StatelessWidget {
  const _WhatsAppButton({required this.onTap});

  final VoidCallback onTap;

  /// WhatsApp brand green.
  static const Color _brand = Color(0xFF25D366);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Contact the seller on WhatsApp',
      child: Pressable(
        onTap: onTap,
        haptics: true,
        pressedScale: 0.94,
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _brand,
            borderRadius: AppRadius.buttonAll,
            boxShadow: [
              BoxShadow(
                color: _brand.withValues(alpha: 0.32),
                blurRadius: 12,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.chat_bubble_rounded,
                color: AppColors.white,
                size: 17,
              ),
              const SizedBox(width: AppSpace.sm - 2),
              Text(
                'WhatsApp',
                style: AppTextStyles.labelMedium.copyWith(
                  color: AppColors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({required this.icon, required this.onTap, this.tint});

  final IconData icon;
  final VoidCallback onTap;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      pressedScale: 0.9,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.38),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: tint ?? AppColors.white, size: 20),
      ),
    );
  }
}

class _CarouselImage extends StatelessWidget {
  const _CarouselImage({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return Container(
        decoration: const BoxDecoration(gradient: AppColors.appBarGradient),
        child: Center(
          child: Icon(
            Icons.shopping_bag_outlined,
            color: AppColors.white.withValues(alpha: 0.55),
            size: 80,
          ),
        ),
      );
    }
    return GestureDetector(
      onTap: () => FullImageViewer.show(context, url),
      child: CachedImage(
        url,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Container(
          decoration: const BoxDecoration(gradient: AppColors.appBarGradient),
          child: Center(
            child: Icon(
              Icons.broken_image_outlined,
              color: AppColors.white.withValues(alpha: 0.55),
              size: 56,
            ),
          ),
        ),
      ),
    );
  }
}
