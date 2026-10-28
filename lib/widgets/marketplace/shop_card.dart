import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/seller_model.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';
import '../motion/pressable.dart';

/// One shop in the "Shops in the community" rail.
///
/// Redesigned 28 Oct 2026. It was a 224px card with a 16:9 cover and a
/// logo hanging off it — two of them filled the screen, so the rail pushed
/// every product below the fold on a phone. Now a short horizontal card: a
/// square thumbnail (the logo, else the cover, else a storefront glyph —
/// uploaded images are square per CLAUDE.md), the name on up to two lines,
/// and one line of trust and place. The cover still leads the shop page.
class ShopCard extends StatelessWidget {
  const ShopCard({
    super.key,
    required this.seller,
    required this.onTap,
    this.width = 236,
  });

  final Seller seller;
  final VoidCallback onTap;
  final double width;

  static const double _thumb = 60;

  /// Rail height that fits the card at 1.0x text. The rail uses this so the
  /// two can't drift apart.
  static const double railHeight = 92;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final place = [
      seller.city,
      seller.province,
    ].where((s) => s != null && s.isNotEmpty).join(', ');
    final rated = seller.ratingCount > 0;

    return Pressable(
      onTap: onTap,
      child: Container(
        width: width,
        padding: const EdgeInsets.all(AppSpace.sm + 2),
        decoration: BoxDecoration(
          color: palette.card,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: palette.divider),
          boxShadow: AppShadows.card(context),
        ),
        child: Row(
          children: [
            _ShopThumb(seller: seller, size: _thumb),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      text: seller.businessName,
                      children: [
                        if (seller.verified || seller.sdaVerified)
                          const WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: Padding(
                              padding: EdgeInsets.only(left: 3),
                              child: Icon(
                                Icons.verified,
                                size: 14,
                                color: AppColors.goldAccent,
                              ),
                            ),
                          ),
                      ],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.labelLarge.copyWith(
                      color: palette.text,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text.rich(
                    TextSpan(
                      children: [
                        if (rated) ...[
                          const WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: Icon(
                              Icons.star_rounded,
                              size: 13,
                              color: AppColors.goldAccent,
                            ),
                          ),
                          TextSpan(
                            text: ' ${seller.rating.toStringAsFixed(1)}',
                            style: TextStyle(
                              color: palette.text,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ] else
                          const TextSpan(
                            text: 'New',
                            style: TextStyle(
                              color: AppColors.primaryBlue,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        TextSpan(
                          text:
                              ' · ${place.isEmpty ? SellerCategory.labelFor(seller.category) : place}',
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: palette.textMuted,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShopThumb extends StatelessWidget {
  const _ShopThumb({required this.seller, required this.size});

  final Seller seller;
  final double size;

  @override
  Widget build(BuildContext context) {
    final logo = seller.profilePhotoUrl;
    final cover = seller.coverPhotoUrl;
    final url = (logo != null && logo.isNotEmpty)
        ? logo
        : (cover != null && cover.isNotEmpty)
        ? cover
        : null;
    final fallback = DecoratedBox(
      decoration: const BoxDecoration(gradient: AppColors.primaryGradient),
      child: Center(
        child: Icon(
          Icons.storefront_rounded,
          color: AppColors.white,
          size: size * 0.36,
        ),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.button),
      child: SizedBox(
        width: size,
        height: size,
        child: url == null
            ? fallback
            : CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                placeholder: (context, _) => fallback,
                errorWidget: (context, _, _) => fallback,
              ),
      ),
    );
  }
}
