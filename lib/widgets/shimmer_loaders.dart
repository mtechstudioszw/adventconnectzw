import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../theme/app_colors.dart';

/// Premium shimmer placeholders so list screens never show a bare
/// spinner (Part 3 of the master reference). Three shapes cover every
/// list in the app — products, churches, generic cards.
class ShimmerLoaders {
  ShimmerLoaders._();

  static const _base = Color(0xFFE6EBF1);
  static const _highlight = Color(0xFFF7F9FC);

  /// A vertically stacked list of generic cards — used by Churches,
  /// Events, Jobs, Prayer feeds.
  static Widget cardList({int count = 4}) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: count,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, __) => _CardSkeleton(),
    );
  }

  /// Two-column product grid skeleton.
  static Widget productGrid({int count = 6}) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.72,
      ),
      itemCount: count,
      itemBuilder: (_, __) => _ProductSkeleton(),
    );
  }
}

class _CardSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: ShimmerLoaders._base,
      highlightColor: ShimmerLoaders._highlight,
      child: Container(
        height: 96,
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(18),
        ),
      ),
    );
  }
}

class _ProductSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: ShimmerLoaders._base,
      highlightColor: ShimmerLoaders._highlight,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Container(color: AppColors.white),
      ),
    );
  }
}
