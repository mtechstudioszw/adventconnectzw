import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../models/product_model.dart';
import '../../models/seller_model.dart';
import '../../services/account_mode_service.dart';
import '../../services/account_service.dart';
import '../../services/marketplace_service.dart';
import '../../services/seller_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/ad_banner.dart';
import '../../widgets/product_card.dart';
import '../widgets/main_bottom_nav.dart';
import '../widgets/post_form_widgets.dart';

class MarketplaceScreen extends StatefulWidget {
  const MarketplaceScreen({super.key});

  @override
  State<MarketplaceScreen> createState() => _MarketplaceScreenState();
}

class _MarketplaceScreenState extends State<MarketplaceScreen>
    with SingleTickerProviderStateMixin {
  final _searchController = TextEditingController();
  Timer? _debounce;

  late final AnimationController _entrance;
  late final Animation<double> _fade;
  late final Animation<double> _slide;

  List<Product> _products = [];
  String _selectedCategory = 'all';
  bool _loading = true;
  String? _error;
  Seller? _mySeller;

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
    _loadProducts();
    _loadMySeller();
  }

  Future<void> _loadMySeller() async {
    try {
      final seller = await SellerService.fetchMySellerProfile();
      if (mounted) setState(() => _mySeller = seller);
    } catch (_) {
      // Banner is decorative — failures must never block the marketplace.
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _entrance.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await MarketplaceService.fetchProducts(
        search: _searchController.text,
        category: _selectedCategory,
      );
      if (!mounted) return;
      setState(() {
        _products = list;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load products. Pull to retry.';
        _loading = false;
      });
    }
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _loadProducts);
  }

  void _selectCategory(String id) {
    setState(() => _selectedCategory = id);
    _loadProducts();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightGrey,
      bottomNavigationBar: const MainBottomNav(currentIndex: 3),
      floatingActionButton: const PostFab(
        routeName: 'add_product',
        tooltip: 'List a product',
      ),
      body: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: SizedBox(
          height: MediaQuery.of(context).size.height,
          child: Column(
            children: [
              _buildHero(),
              _buildSearchBar(),
              if (_mySeller != null) _SellerStatusBanner(seller: _mySeller!),
              const _ShopJobsSegment(active: _Section.shop),
              _buildCategoryStrip(),
              Expanded(
                child: RefreshIndicator(
                  color: AppColors.primaryBlue,
                  onRefresh: _loadProducts,
                  child: AnimatedBuilder(
                    animation: _entrance,
                    builder: (context, child) => Opacity(
                      opacity: _fade.value,
                      child: Transform.translate(
                        offset: Offset(0, _slide.value),
                        child: child,
                      ),
                    ),
                    child: _buildGrid(),
                  ),
                ),
              ),
              const AdBanner(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHero() {
    return ClipPath(
      clipper: _HeroClipper(),
      child: Container(
        decoration: const BoxDecoration(gradient: AppColors.appBarGradient),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _CircleIconButton(
                      icon: Icons.arrow_back,
                      onTap: () => context.canPop()
                          ? context.pop()
                          : context.goNamed('home'),
                    ),
                    const Spacer(),
                    _CircleIconButton(
                      icon: Icons.grid_view_rounded,
                      onTap: () => context.pushNamed('categories'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'MARKETPLACE',
                        style: AppTextStyles.labelSmall.copyWith(
                          color: AppColors.white.withValues(alpha: 0.55),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.8,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Shop within the community',
                        style: AppTextStyles.displayMedium.copyWith(
                          color: AppColors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
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

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: TextField(
        controller: _searchController,
        onChanged: _onSearchChanged,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => _loadProducts(),
        style: AppTextStyles.bodyLarge,
        decoration: InputDecoration(
          hintText: 'Search products',
          prefixIcon: const Icon(Icons.search, color: AppColors.primaryBlue),
          suffixIcon: _searchController.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(
                    Icons.close,
                    color: Color.fromRGBO(26, 26, 46, 0.5),
                  ),
                  onPressed: () {
                    _searchController.clear();
                    _loadProducts();
                  },
                ),
          filled: true,
          fillColor: AppColors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 4),
        ),
      ),
    );
  }

  Widget _buildCategoryStrip() {
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: ProductCategory.all.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final cat = ProductCategory.all[i];
          final selected = _selectedCategory == cat.id;
          return _CategoryChip(
            label: cat.label,
            icon: cat.icon,
            selected: selected,
            onTap: () => _selectCategory(cat.id),
          );
        },
      ),
    );
  }

  Widget _buildGrid() {
    if (_loading && _products.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primaryBlue),
      );
    }
    if (_error != null && _products.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 100),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                children: [
                  const Icon(
                    Icons.cloud_off_outlined,
                    size: 56,
                    color: Color.fromRGBO(26, 26, 46, 0.4),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: const Color.fromRGBO(26, 26, 46, 0.6),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }
    if (_products.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 80),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlue.withValues(alpha: 0.10),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.shopping_bag_outlined,
                      color: AppColors.primaryBlue,
                      size: 40,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'No products yet',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.headlineMedium.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Know an SDA business owner? Tell them about us.',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: const Color.fromRGBO(26, 26, 46, 0.6),
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => _onBecomeSellerTapped(context),
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          gradient: AppColors.primaryGradient,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primaryBlue
                                  .withValues(alpha: 0.30),
                              blurRadius: 14,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.storefront,
                              color: AppColors.white,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Become a seller',
                              style: AppTextStyles.buttonText.copyWith(
                                fontSize: 14,
                                letterSpacing: 0.3,
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
        ],
      );
    }
    return GridView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      itemCount: _products.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        childAspectRatio: 0.72,
      ),
      itemBuilder: (context, i) {
        final p = _products[i];
        return ProductCard(
          product: p,
          onTap: () => context.pushNamed(
            'product_details',
            pathParameters: {'id': p.id},
            extra: p,
          ),
        );
      },
    );
  }
}

/// Entry point for the "Become a seller" button. Mirrors the gating
/// in add_product_screen so the marketplace doesn't push a personal
/// account into a setup-store flow they aren't eligible for:
///
///   - no business yet      → "Apply for a business account" sheet
///   - has business, in personal view  → "Switch to business" sheet
///   - has business, in business view  → original chooser
///
/// Failure to load the account state falls through to the chooser so
/// a transient network blip doesn't permanently lock the button.
Future<void> _onBecomeSellerTapped(BuildContext context) async {
  AccountState? account;
  try {
    account = await AccountService.fetchMyAccount();
  } catch (_) {
    account = null;
  }
  if (!context.mounted) return;
  if (account != null && !account.isBusiness) {
    await _showApplyForBusinessSheet(context, account: account);
    return;
  }
  if (account != null &&
      account.isBusiness &&
      !AccountModeService.inBusinessMode) {
    await _showSwitchToBusinessSheet(context);
    return;
  }
  await _showSellerChooser(context);
}

/// Sheet for users without an approved business account. Surfaces the
/// pending / rejected states the same way the in-screen gate does and
/// routes them to apply_business.
Future<void> _showApplyForBusinessSheet(
  BuildContext context, {
  required AccountState account,
}) {
  final pending = account.hasPendingApplication;
  final rejected = account.hasRejectedApplication;
  final title = pending
      ? 'Application in review'
      : rejected
          ? 'Application declined'
          : 'Business account required';
  final body = pending
      ? 'Your business application is being reviewed. We\'ll notify '
          'you the moment it\'s approved.'
      : rejected
          ? (account.latestApplication?.reviewerNote?.trim().isNotEmpty == true
              ? '${account.latestApplication!.reviewerNote!.trim()}\n\nYou can edit your details and re-apply.'
              : 'Your application was declined. You can edit your '
                  'details and re-apply.')
          : 'Selling on the marketplace is only available to business '
              'accounts. Apply to start selling within the SDA '
              'community.';
  final cta = pending
      ? 'OK'
      : rejected
          ? 'Re-apply'
          : 'Apply for Business';

  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => _ChooserSheet(
      icon: pending ? Icons.hourglass_top_rounded : Icons.business_center,
      title: title,
      subtitle: body,
      primaryLabel: cta,
      onPrimary: () {
        Navigator.of(sheetContext).pop();
        if (!pending) context.pushNamed('apply_business');
      },
    ),
  );
}

/// Sheet for an approved business that's currently looking at the
/// app in personal view. Sends them to their profile so they can
/// flip the toggle.
Future<void> _showSwitchToBusinessSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => _ChooserSheet(
      icon: Icons.swap_horiz,
      title: 'Switch to Business mode',
      subtitle:
          'You\'re approved as a business, but the app is currently in '
          'Personal mode. Switch to Business mode from your profile to '
          'access your store.',
      primaryLabel: 'Go to profile',
      onPrimary: () {
        Navigator.of(sheetContext).pop();
        context.goNamed('profile');
      },
    ),
  );
}

/// Bottom-sheet chooser fired when the user taps "Become a seller"
/// and qualifies for the seller flow. Asks whether they already have
/// a store or want to set up a fresh one. The "+" button on the
/// marketplace tab handles the same distinction implicitly via
/// add_product's gate; this surfaces the choice explicitly for new
/// users.
Future<void> _showSellerChooser(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color.fromRGBO(26, 26, 46, 0.18),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Selling on Advent Connect',
              style: AppTextStyles.titleLarge.copyWith(
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Already running a store, or starting a new one?',
              style: AppTextStyles.bodySmall.copyWith(
                color: const Color.fromRGBO(26, 26, 46, 0.65),
              ),
            ),
            const SizedBox(height: 18),
            _SellerChoiceTile(
              icon: Icons.storefront_outlined,
              title: 'I already have a store',
              subtitle: 'Open my seller dashboard.',
              onTap: () {
                Navigator.of(sheetContext).pop();
                context.pushNamed('seller_dashboard');
              },
            ),
            const SizedBox(height: 10),
            _SellerChoiceTile(
              icon: Icons.add_business_outlined,
              title: 'Set up a new store',
              subtitle:
                  'Apply to start selling within the SDA community.',
              onTap: () {
                Navigator.of(sheetContext).pop();
                context.pushNamed('setup_store');
              },
            ),
          ],
        ),
      ),
    ),
  );
}

class _SellerChoiceTile extends StatelessWidget {
  const _SellerChoiceTile({
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
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.lightGrey,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color.fromRGBO(26, 26, 46, 0.05),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: AppColors.white, size: 22),
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
                        fontSize: 14.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: const Color.fromRGBO(26, 26, 46, 0.6),
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: AppColors.primaryBlue,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Status pill rendered at the top of the marketplace tab when the
/// current user has a `sellers` row. It mirrors the same states as the
/// seller-gate dialog inside add_product, but keeps them visible from
/// the storefront list without having to attempt a listing first.
class _SellerStatusBanner extends StatelessWidget {
  const _SellerStatusBanner({required this.seller});

  final Seller seller;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color tint, String label, String hint) = seller
            .isApproved
        ? (
            Icons.storefront_rounded,
            AppColors.successGreen,
            'Seller mode',
            'Tap to open your seller dashboard.',
          )
        : seller.isPending
            ? (
                Icons.hourglass_top_rounded,
                AppColors.goldAccent,
                'Store under review',
                'Tap to check approval status.',
              )
            : (
                Icons.error_outline_rounded,
                AppColors.red,
                'Application needs attention',
                'Tap to review and resubmit.',
              );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => context.pushNamed('seller_dashboard'),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: tint.withValues(alpha: 0.30)),
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: tint.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: tint, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: AppTextStyles.titleSmall.copyWith(
                          color: tint,
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        hint,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: const Color.fromRGBO(26, 26, 46, 0.65),
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: tint.withValues(alpha: 0.7),
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shared layout for the apply-for-business / switch-to-business
/// explainer sheets. Single primary CTA + an implicit "Cancel" via
/// dismissing the sheet.
class _ChooserSheet extends StatelessWidget {
  const _ChooserSheet({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.primaryLabel,
    required this.onPrimary,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String primaryLabel;
  final VoidCallback onPrimary;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color.fromRGBO(26, 26, 46, 0.18),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Center(
              child: Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: AppColors.white, size: 26),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTextStyles.titleLarge.copyWith(
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySmall.copyWith(
                color: const Color.fromRGBO(26, 26, 46, 0.7),
                height: 1.5,
                fontSize: 13.5,
              ),
            ),
            const SizedBox(height: 22),
            Container(
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primaryBlue.withValues(alpha: 0.28),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onPrimary,
                  borderRadius: BorderRadius.circular(14),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Center(
                      child: Text(
                        primaryLabel,
                        style: AppTextStyles.buttonText.copyWith(
                          color: AppColors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
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

class _HeroClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height - 24);
    path.quadraticBezierTo(
      size.width / 2,
      size.height,
      size.width,
      size.height - 24,
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

enum _Section { shop, jobs }

class _ShopJobsSegment extends StatelessWidget {
  const _ShopJobsSegment({required this.active});
  final _Section active;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color.fromRGBO(26, 26, 46, 0.06)),
        ),
        child: Row(
          children: [
            _SegmentButton(
              label: 'Shop',
              icon: Icons.shopping_bag_outlined,
              selected: active == _Section.shop,
              onTap: active == _Section.shop
                  ? null
                  : () => context.goNamed('marketplace'),
            ),
            _SegmentButton(
              label: 'Jobs',
              icon: Icons.work_outline,
              selected: active == _Section.jobs,
              onTap: active == _Section.jobs
                  ? null
                  : () => context.goNamed('jobs'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  const _SegmentButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: selected ? AppColors.primaryGradient : null,
              borderRadius: BorderRadius.circular(10),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: AppColors.primaryBlue.withValues(alpha: 0.25),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : [],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: selected
                      ? AppColors.white
                      : const Color.fromRGBO(26, 26, 46, 0.6),
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: AppTextStyles.labelMedium.copyWith(
                    color: selected
                        ? AppColors.white
                        : const Color.fromRGBO(26, 26, 46, 0.7),
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
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

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: selected ? AppColors.primaryGradient : null,
            color: selected ? null : AppColors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? AppColors.primaryBlue
                  : const Color.fromRGBO(26, 26, 46, 0.08),
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: AppColors.primaryBlue.withValues(alpha: 0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : [],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(icon, style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 6),
              Text(
                label,
                style: AppTextStyles.labelMedium.copyWith(
                  color: selected ? AppColors.white : AppColors.textDark,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
