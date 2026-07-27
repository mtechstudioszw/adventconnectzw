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
    this.aspectRatio = 3 / 4,
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
        mainAxisSpacing: AppSpace.xl,
        crossAxisSpacing: AppSpace.md,
        childAspectRatio: 0.56,
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
    final unavailable = !product.isAvailable;
    return Pressable(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Flexible, not a bare AspectRatio.
          //
          // The grid hands each tile a FIXED height (width / 0.56) and the
          // 3:4 photo plus price + two title lines + the seller row landed
          // within ~2dp of it. Any larger system font size, or a font
          // whose metrics differ by a hair, tipped it over — which is the
          // "BOTTOM OVERFLOWED BY 7 PIXELS" stripe.
          //
          // Loose-fitting the photo lets it give back the few pixels the
          // text needs instead of the column blowing its bounds. At normal
          // text size nothing moves; the photo keeps its 3:4.
          Flexible(
            child: AspectRatio(
              aspectRatio: aspectRatio,
              child: ClipRRect(
                borderRadius: AppRadius.lgAll,
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

                    // Sold / reserved dim the photo rather than hiding the
                    // listing — scarcity is information a buyer wants.
                    if (unavailable)
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                        ),
                      ),
                    if (unavailable)
                      Center(
                        child: _StatusStamp(
                          label: product.isSold ? 'SOLD' : 'RESERVED',
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
            ),
          ),
          const SizedBox(height: AppSpace.sm),

          // Price leads. It is the number the buyer is actually scanning
          // for, so it gets the strongest type on the tile instead of
          // being a 12px chip floating over uncontrolled photo content.
          Text(
            product.formatPrice(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.titleMedium.copyWith(
              color: palette.text,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            product.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.bodySmall.copyWith(
              color: palette.text,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Flexible(
                child: Text(
                  product.sellerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: palette.textMuted,
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
