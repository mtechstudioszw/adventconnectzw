import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';
import 'marketplace/product_tile.dart';

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

  /// Non-scrollable column of tall post-shaped blocks — for the home
  /// feed, which lives inside an outer SingleChildScrollView.
  static Widget postColumn({int count = 2}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        children: [
          for (var i = 0; i < count; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: _PostSkeleton(),
            ),
        ],
      ),
    );
  }

  /// People rows — avatar circle + name/subtitle bars. Used by the
  /// find-friends picker and member lists.
  static Widget peopleList({int count = 8}) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: count,
      separatorBuilder: (context, index) => const SizedBox(height: 14),
      itemBuilder: (context, index) => _PersonSkeleton(),
    );
  }

  /// Two-column product grid skeleton.
  ///
  /// Borrows [ProductTile.gridDelegate] so the skeleton and the grid it
  /// stands in for cannot describe different shapes — they had already
  /// drifted apart once.
  static Widget productGrid({int count = 6}) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: ProductTile.gridDelegate,
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

class _PostSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: ShimmerLoaders.baseColor(context),
      highlightColor: ShimmerLoaders.highlightColor(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: context.palette.card,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Container(
                height: 12,
                width: 140,
                decoration: BoxDecoration(
                  color: context.palette.card,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            height: 180,
            width: double.infinity,
            decoration: BoxDecoration(
              color: context.palette.card,
              borderRadius: BorderRadius.circular(18),
            ),
          ),
        ],
      ),
    );
  }
}

class _PersonSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: ShimmerLoaders.baseColor(context),
      highlightColor: ShimmerLoaders.highlightColor(context),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: context.palette.card,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 12,
                width: 150,
                decoration: BoxDecoration(
                  color: context.palette.card,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              const SizedBox(height: 7),
              Container(
                height: 10,
                width: 96,
                decoration: BoxDecoration(
                  color: context.palette.card,
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProductSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Mirrors ProductTile's silhouette: a 3:4 photo block, then price and
    // title bars on the background. A single filled rectangle no longer
    // resembles what loads in behind it.
    return Shimmer.fromColors(
      baseColor: ShimmerLoaders.baseColor(context),
      highlightColor: ShimmerLoaders.highlightColor(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 3 / 4,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: context.palette.card,
                borderRadius: AppRadius.lgAll,
              ),
            ),
          ),
          const SizedBox(height: AppSpace.sm),
          _Bar(width: 62, height: 14, palette: context.palette.card),
          const SizedBox(height: 6),
          _Bar(width: double.infinity, height: 10, palette: context.palette.card),
          const SizedBox(height: 4),
          _Bar(width: 90, height: 10, palette: context.palette.card),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.width,
    required this.height,
    required this.palette,
  });

  final double width;
  final double height;
  final Color palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: palette,
        borderRadius: AppRadius.smAll,
      ),
    );
  }
}
