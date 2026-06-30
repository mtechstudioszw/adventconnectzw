import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../theme/app_palette.dart';

/// Premium shimmer placeholders so list screens never show a bare
/// spinner (Part 3 of the master reference). Three shapes cover every
/// list in the app — products, churches, generic cards.
class ShimmerLoaders {
  ShimmerLoaders._();

  static const _base = Color(0xFFE6EBF1);
  static const _highlight = Color(0xFFF7F9FC);
  // Dark-mode shimmer tones — without these the light greys above flash as
  // bright white boxes against the dark scaffold while lists load.
  static const _baseDark = Color(0xFF1A2240);
  static const _highlightDark = Color(0xFF273156);

  static Color baseColor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? _baseDark : _base;
  static Color highlightColor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? _highlightDark
          : _highlight;

  /// A vertically stacked list of generic cards — used by Churches,
  /// Events, Jobs, Prayer feeds.
  static Widget cardList({int count = 4}) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: count,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) => _CardSkeleton(),
    );
  }

  /// Watch tab — a 16:9 hero followed by a few video-card skeletons.
  static Widget watchList({int count = 4}) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _VideoSkeleton(hero: true),
        const SizedBox(height: 16),
        for (var i = 0; i < count; i++) _VideoSkeleton(),
      ],
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
      itemBuilder: (context, index) => _ProductSkeleton(),
    );
  }
}

class _CardSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: ShimmerLoaders.baseColor(context),
      highlightColor: ShimmerLoaders.highlightColor(context),
      child: Container(
        height: 96,
        decoration: BoxDecoration(
          color: context.palette.card,
          borderRadius: BorderRadius.circular(18),
        ),
      ),
    );
  }
}

class _VideoSkeleton extends StatelessWidget {
  const _VideoSkeleton({this.hero = false});
  final bool hero;

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: ShimmerLoaders.baseColor(context),
      highlightColor: ShimmerLoaders.highlightColor(context),
      child: Padding(
        padding: EdgeInsets.only(bottom: hero ? 0 : 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Container(
                decoration: BoxDecoration(
                  color: context.palette.card,
                  borderRadius: BorderRadius.circular(hero ? 20 : 16),
                ),
              ),
            ),
            if (!hero) ...[
              const SizedBox(height: 10),
              Container(
                height: 12,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: context.palette.card,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              const SizedBox(height: 7),
              Container(
                height: 12,
                width: 140,
                decoration: BoxDecoration(
                  color: context.palette.card,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProductSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: ShimmerLoaders.baseColor(context),
      highlightColor: ShimmerLoaders.highlightColor(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Container(color: context.palette.card),
      ),
    );
  }
}
