import 'package:flutter/material.dart';

import '../../models/product_model.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';
import '../cached_image.dart';
import '../motion/pressable.dart';

/// The buyer-facing product tile.
///
/// Deliberately *not* a card. The old `ProductCard` wrapped every photo in
/// a white box with a shadow, then cropped the photo to whatever height
/// was left over after the text — so a dress and a book cover arrived at
/// the same near-square. Here the photo is the object: it takes a fixed
/// [aspectRatio], keeps its own rounded corners, and the title and price
/// sit on the scaffold background beneath it.
///
/// [aspectRatio] is a parameter rather than a constant so the grid can
/// move to natural-aspect masonry once the catalogue is big enough for
/// ragged columns to read as editorial rather than broken.
class ProductTile extends StatelessWidget {
  const ProductTile({
    super.key,
    required this.product,
    required this.onTap,
    this.heroTag,
    this.aspectRatio = 1,
    this.saved,
    this.onToggleSave,
  });

  /// The single grid geometry for product tiles.
  ///
  /// `childAspectRatio: 0.72` used to be copy-pasted across the
  /// marketplace grid, the category grid, the saved-listings grid, the
  /// storefront grid and the shimmer skeleton — five places to keep in
  /// sync by hand, and the skeleton had already drifted from the grid it
  /// stands in for. It lives here now.
  static const SliverGridDelegateWithFixedCrossAxisCount gridDelegate =
      SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: AppSpace.md,
        crossAxisSpacing: AppSpace.md,
        // Square photo + ~110px of text inside the card.
        childAspectRatio: 0.62,
      );

  final Product product;
  final VoidCallback onTap;

  /// When set, the photo flies into the details screen's hero. Leave null
  /// anywhere the same product can appear twice on one screen — duplicate
  /// hero tags throw in debug.
  final Object? heroTag;

  final double aspectRatio;

  /// Null hides the heart entirely (e.g. signed-out, or the seller's own
  /// storefront). False/true drives the filled state.
  final bool? saved;
  final VoidCallback? onToggleSave;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final unavailable = !product.isAvailable || product.isSoldOut;
    // Redesigned 28 Oct 2026 to the house rules: a card (white with
    // shadow, 16 radius) holding a SQUARE photo — CLAUDE.md makes product
    // covers square — with price, title and seller inside the card. It was
    // a 3:4 photo with its text floating on the page background.
    final compactText = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    return LayoutBuilder(
      builder: (context, constraints) => _card(
        context,
        palette,
        unavailable,
        compactText,
        bounded: constraints.hasBoundedHeight,
      ),
    );
  }

  /// [bounded]: in a grid cell or fixed-height rail the text area fills the
  /// rest of the card and the seller line sits at the bottom. Unbounded
  /// (the listing preview sheet) it simply takes its natural height —
  /// `Expanded` there would throw.
  Widget _card(
    BuildContext context,
    AppPalette palette,
    bool unavailable,
    bool compactText, {
    required bool bounded,
  }) {
    final text = Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.md - 2,
        AppSpace.sm,
        AppSpace.md - 2,
        AppSpace.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: bounded ? MainAxisSize.max : MainAxisSize.min,
        children: [
          Text(
            product.formatPrice(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.titleMedium.copyWith(
              color: AppColors.primaryBlue,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            product.title,
            maxLines: compactText ? 1 : 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.bodySmall.copyWith(
              color: palette.text,
              fontWeight: FontWeight.w500,
              height: 1.3,
            ),
          ),
          if (bounded) const Spacer() else const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                Icons.storefront_outlined,
                size: 12,
                color: palette.textMuted,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  product.sellerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: palette.textMuted,
                    fontSize: 11.5,
                  ),
                ),
              ),
              if (product.sellerVerified) ...[
                const SizedBox(width: AppSpace.xs),
                const Icon(
                  Icons.verified,
                  size: 12,
                  color: AppColors.goldAccent,
                ),
              ],
            ],
          ),
        ],
      ),
    );
    return Pressable(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: palette.card,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: palette.divider),
          boxShadow: AppShadows.card(context),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: bounded ? MainAxisSize.max : MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: aspectRatio,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (heroTag != null)
                    Hero(
                      tag: heroTag!,
                      child: _TileImage(url: product.firstImage),
                    )
                  else
                    _TileImage(url: product.firstImage),
                  if (unavailable)
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                      ),
                    ),
                  if (unavailable)
                    Center(
                      child: _StatusStamp(
                        label: product.isSold
                            ? 'SOLD'
                            : product.isSoldOut
                            ? 'SOLD OUT'
                            : 'RESERVED',
                      ),
                    ),
                  if (product.isFeatured && !unavailable)
                    const Positioned(
                      top: AppSpace.sm,
                      left: AppSpace.sm,
                      child: _FeaturedPip(),
                    ),
                  if (saved != null)
                    Positioned(
                      top: AppSpace.xs,
                      right: AppSpace.xs,
                      child: _SaveHeart(saved: saved!, onTap: onToggleSave),
                    ),
                ],
              ),
            ),
            if (bounded) Expanded(child: text) else text,
          ],
        ),
      ),
    );
  }
}

class _TileImage extends StatelessWidget {
  const _TileImage({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return const _TilePlaceholder(icon: Icons.shopping_bag_outlined);
    }
    return CachedImage(
      url,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) =>
          const _TilePlaceholder(icon: Icons.broken_image_outlined),
    );
  }
}

class _TilePlaceholder extends StatelessWidget {
  const _TilePlaceholder({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: AppColors.appBarGradient),
      child: Center(
        child: Icon(
          icon,
          color: AppColors.white.withValues(alpha: 0.5),
          size: 34,
        ),
      ),
    );
  }
}

/// Diagonal-free, plain stamp. A rotated ribbon read as decoration; a flat
/// capsule reads as state.
class _StatusStamp extends StatelessWidget {
  const _StatusStamp({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: AppRadius.pillAll,
      ),
      child: Text(
        label,
        style: AppTextStyles.labelSmall.copyWith(
          color: AppColors.darkNavy,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.4,
        ),
      ),
    );
  }
}

class _FeaturedPip extends StatelessWidget {
  const _FeaturedPip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.goldAccent,
        borderRadius: AppRadius.pillAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star_rounded, size: 12, color: AppColors.darkNavy),
          const SizedBox(width: 3),
          Text(
            'Featured',
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.darkNavy,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// Save affordance. Until now `saveProduct` existed in the service, the
/// `saved_listings` table existed, and the Saved screen existed — but
/// nothing in the app could actually save anything. This is that button.
class _SaveHeart extends StatelessWidget {
  const _SaveHeart({required this.saved, this.onTap});

  final bool saved;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      pressedScale: 0.88,
      haptics: true,
      child: Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.38),
          shape: BoxShape.circle,
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          transitionBuilder: (child, animation) =>
              ScaleTransition(scale: animation, child: child),
          child: Icon(
            saved ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            key: ValueKey<bool>(saved),
            size: 18,
            color: saved ? AppColors.red : AppColors.white,
          ),
        ),
      ),
    );
  }
}
