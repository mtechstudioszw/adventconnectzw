import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/seller_model.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';
import '../motion/pressable.dart';

/// A storefront as a destination, for the shops rail on the marketplace tab.
///
/// The shape is deliberately the inverse of a product tile: wide 16:9 cover
/// with the logo breaking its bottom edge, so shops and products can never
/// be confused for one another while scrolling.
class ShopCard extends StatelessWidget {
  const ShopCard({
    super.key,
    required this.seller,
    required this.onTap,
    this.width = 224,
  });

  final Seller seller;
  final VoidCallback onTap;
  final double width;

  static const double _logo = 44;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final cover = seller.coverPhotoUrl;
    final hasCover = cover != null && cover.isNotEmpty;
    final place = [
      seller.city,
      seller.province,
    ].where((s) => s != null && s.isNotEmpty).join(', ');

    return Pressable(
      onTap: onTap,
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Cover + overlapping logo. The Stack is sized by the cover and
            // allowed to overflow downward by half the logo, so the row of
            // text below starts clear of it.
            SizedBox(
              height: width * 9 / 16 + _logo / 2,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    child: ClipRRect(
                      borderRadius: AppRadius.lgAll,
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: hasCover
                            ? CachedNetworkImage(
                                imageUrl: cover,
                                fit: BoxFit.cover,
                                placeholder: (context, url) =>
                                    const _CoverFallback(),
                                errorWidget: (context, url, error) =>
                                    const _CoverFallback(),
                              )
                            : const _CoverFallback(),
                      ),
                    ),
                  ),
                  Positioned(
                    left: AppSpace.md,
                    bottom: 0,
                    child: _ShopLogo(seller: seller, size: _logo),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.sm),
            Row(
              children: [
                Flexible(
                  child: Text(
                    seller.businessName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.titleSmall.copyWith(
                      color: palette.text,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (seller.verified || seller.sdaVerified) ...[
                  const SizedBox(width: AppSpace.xs),
                  const Icon(
                    Icons.verified,
                    size: 14,
                    color: AppColors.goldAccent,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                if (seller.ratingCount > 0) ...[
                  const Icon(
                    Icons.star_rounded,
                    size: 13,
                    color: AppColors.goldAccent,
                  ),
                  const SizedBox(width: 2),
                  Text(
                    seller.rating.toStringAsFixed(1),
                    style: AppTextStyles.bodySmall.copyWith(
                      color: palette.text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: AppSpace.sm),
                ] else ...[
                  Text(
                    'New',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.primaryBlue,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: AppSpace.sm),
                ],
                Flexible(
                  child: Text(
                    place.isEmpty
                        ? SellerCategory.labelFor(seller.category)
                        : place,
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
        ),
      ),
    );
  }
}

class _CoverFallback extends StatelessWidget {
  const _CoverFallback();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(gradient: AppColors.appBarGradient),
    );
  }
}

class _ShopLogo extends StatelessWidget {
  const _ShopLogo({required this.seller, required this.size});

  final Seller seller;
  final double size;

  @override
  Widget build(BuildContext context) {
    final photo = seller.profilePhotoUrl;
    final hasPhoto = photo != null && photo.isNotEmpty;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: hasPhoto ? null : AppColors.primaryGradient,
        color: hasPhoto ? AppColors.lightGrey : null,
        shape: BoxShape.circle,
        border: Border.all(color: context.palette.scaffoldBg, width: 3),
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
          : Icon(Icons.storefront, color: AppColors.white, size: size * 0.45),
    );
  }
}
