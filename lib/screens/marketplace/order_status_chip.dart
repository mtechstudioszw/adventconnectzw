import 'package:flutter/material.dart';

import '../../models/order_model.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';

/// One status vocabulary, shared by the buyer's order list and the
/// seller's inbox — so "confirmed" can never mean two different things
/// depending on which side of the transaction you're on.
class OrderStatusChip extends StatelessWidget {
  const OrderStatusChip({super.key, required this.status});

  final String status;

  static Color colorFor(String status) => switch (status) {
    'pending' => AppColors.goldAccent,
    'confirmed' => AppColors.primaryBlue,
    'completed' => AppColors.successGreen,
    'cancelled' => AppColors.red,
    _ => AppColors.primaryBlue,
  };

  static IconData iconFor(String status) => switch (status) {
    'pending' => Icons.hourglass_top_rounded,
    'confirmed' => Icons.handshake_outlined,
    'completed' => Icons.check_circle_outline_rounded,
    'cancelled' => Icons.cancel_outlined,
    _ => Icons.circle_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final color = colorFor(status);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.sm + 2,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppRadius.pillAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(iconFor(status), size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            MarketOrder.labelFor(status),
            style: AppTextStyles.labelSmall.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
