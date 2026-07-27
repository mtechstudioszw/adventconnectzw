import 'package:flutter/material.dart';

import '../../services/cart_service.dart';
import '../screen_shell.dart';

/// Header basket button. Rebuilds off [CartService.revision] so the count
/// is live everywhere it's mounted without any screen having to remember
/// to refresh it.
///
/// This badge is now the *only* basket feedback in the app. The floating
/// "N items in basket" bar and the "Added to your basket" snackbar that used
/// to live in this file were both removed: between them they restated this
/// count twice, and the bar permanently covered a row of products.
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
