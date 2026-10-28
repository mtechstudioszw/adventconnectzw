import 'package:flutter/material.dart';

import '../../config/countries.dart';
import '../../models/org_page_model.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';
import '../cached_image.dart';
import '../motion/pressable.dart';
import '../verified_tick.dart';

/// One organization Page in a list: square logo, name + tick, category
/// and place. Tapping opens the Page.
class PageTile extends StatelessWidget {
  const PageTile({super.key, required this.page, required this.onTap});

  final OrgPage page;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final place = [
      page.city,
      if (page.country != null) Countries.nameOf(page.country),
    ].where((s) => (s ?? '').isNotEmpty).join(', ');
    final meta = [page.category.label, if (place.isNotEmpty) place].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Pressable(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppSpace.sm + 2),
          decoration: BoxDecoration(
            color: palette.card,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: palette.divider),
            boxShadow: AppShadows.card(context),
          ),
          child: Row(
            children: [
              PageLogo(page: page, size: 56),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            page.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.titleSmall.copyWith(
                              color: palette.text,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (page.isVerified) const VerifiedTick(size: 14),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: palette.textMuted,
                      ),
                    ),
                    if (page.isHidden)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Hidden by moderators',
                          style: AppTextStyles.labelSmall.copyWith(
                            color: AppColors.red,
                            fontWeight: FontWeight.w700,
                          ),
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

/// A Page's square logo, or its category glyph on the brand gradient.
class PageLogo extends StatelessWidget {
  const PageLogo({super.key, required this.page, this.size = 56});
  final OrgPage page;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fallback = DecoratedBox(
      decoration: const BoxDecoration(gradient: AppColors.primaryGradient),
      child: Center(
        child: Icon(
          page.category.icon,
          color: AppColors.white,
          size: size * 0.42,
        ),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.button),
      child: SizedBox(
        width: size,
        height: size,
        child: page.logoUrl == null
            ? fallback
            : CachedImage(
                page.logoUrl!,
                fit: BoxFit.cover,
                width: size,
                height: size,
                errorBuilder: (_, _, _) => fallback,
              ),
      ),
    );
  }
}
