import 'package:flutter/material.dart';

import '../../services/cart_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../screen_shell.dart';

/// Header basket button. Rebuilds off [CartService.revision] so the count
/// is live everywhere it's mounted without any screen having to remember
/// to refresh it.
class CartBadgeButton extends StatelessWidget {
  const CartBadgeButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: CartService.revision,
      builder: (context, revision, child) => HeaderIconButton(
        icon: Icons.shopping_bag_outlined,
        tooltip: 'Basket',
        onTap: onTap,
        badgeCount: CartService.count,
      ),
    );
  }
}

/// Floating "N items · View basket" bar. Shown above the bottom nav on the
/// marketplace surfaces whenever the basket has something in it, so the
/// basket is never more than one tap away and never invisible.
class CartFloatingBar extends StatelessWidget {
  const CartFloatingBar({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: CartService.revision,
      builder: (context, revision, child) {
        final count = CartService.count;
        final shops = CartService.sellerCount;
        return AnimatedSlide(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          offset: count == 0 ? const Offset(0, 1.4) : Offset.zero,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: count == 0 ? 0 : 1,
            child: count == 0
                ? const SizedBox.shrink()
                : _Bar(count: count, shops: shops, onTap: onTap),
          ),
        );
      },
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.count, required this.shops, required this.onTap});

  final int count;
  final int shops;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(100),
          child: Ink(
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(100),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryBlue.withValues(alpha: 0.32),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 14,
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.shopping_bag_rounded,
                    color: AppColors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      shops > 1
                          ? '$count items from $shops shops'
                          : '$count ${count == 1 ? 'item' : 'items'} in basket',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.buttonText.copyWith(fontSize: 14.5),
                    ),
                  ),
                  Text(
                    'View',
                    style: AppTextStyles.buttonText.copyWith(
                      fontSize: 14.5,
                      color: AppColors.white.withValues(alpha: 0.9),
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.white,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small helper so screens can show a consistent "added" confirmation.
void showAddedToCartSnack(BuildContext context, String title, VoidCallback onView) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        backgroundColor: context.palette.text,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        content: Text(
          'Added "$title" to your basket',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.bodyMedium.copyWith(
            color: context.palette.scaffoldBg,
          ),
        ),
        action: SnackBarAction(
          label: 'View',
          textColor: AppColors.goldAccent,
          onPressed: onView,
        ),
      ),
    );
}
