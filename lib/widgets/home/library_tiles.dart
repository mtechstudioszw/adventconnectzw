import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';
import '../motion/pressable.dart';
import '../motion/staggered_reveal.dart';

/// The Library launcher on Home.
///
/// A single row of compact pills — icon and label side by side, ~44dp tall.
///
/// It was previously a row of 58dp icon squares with the label stacked
/// underneath, 92dp in total. Sitting directly beneath the 224dp Today card
/// that meant well over 300dp of the first screen was chrome before the feed
/// began, and six saturated squares competed with the card above them for
/// attention when this row is navigation, not a hero. Laying each entry out
/// horizontally halves the height and matches the chip vocabulary already used
/// on the Marketplace.
///
/// Ordering is deliberate: **Quiz sits fourth** so it lands inside the first
/// screenful, and it keeps the brand gradient so it still reads as the one
/// highlight.
///
/// This row was the ONLY route into `/quiz` until Aug 2026, when a quiz action
/// was added to the Library screen's app bar. It is still the PRIMARY one and
/// the only one on the home feed — the app-bar action is a second door for
/// people already inside the Library, not a replacement — so the warning
/// stands: don't reorder this tile out of view.
class LibraryTiles extends StatelessWidget {
  const LibraryTiles({super.key});

  /// Row height. The pill itself is 40dp; the rest is room for its
  /// SHADOW.
  ///
  /// This was 44, which left 4dp — and the Quiz pill casts a 12dp blur at
  /// a 5dp offset, so its glow was being sliced off by the list viewport
  /// and the whole row read as cramped and slightly misaligned against
  /// the sections above and below it. 64 clears the shadow and gives the
  /// row the same optical breathing space as the cards around it.
  static const double _rowHeight = 64;

  // (label, icon, library tab index, isHero). Tab indexes map 1:1 onto
  // LibraryScreen's TabBar order — keep the two in sync.
  // Quiz uses index -1 because it routes to `/quiz`, not the Library.
  static const _items = <(String, IconData, int, bool)>[
    ('Bible', Icons.menu_book_rounded, 0, false),
    ('Sabbath', Icons.school_rounded, 1, false),
    ('Hymnal', Icons.queue_music_rounded, 2, false),
    ('Quiz', Icons.emoji_events_rounded, -1, true),
    ('Music', Icons.headphones_rounded, 4, false),
    ('EGW', Icons.auto_stories_rounded, 3, false),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _rowHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
        itemCount: _items.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpace.md),
        itemBuilder: (context, i) {
          final (label, icon, tab, hero) = _items[i];
          // Only six items and they all build at once, so a stagger here
          // can't replay on scroll the way it would in a long lazy list.
          return StaggeredReveal(
            index: i,
            rise: 12,
            interval: const Duration(milliseconds: 40),
            // Centred in the row. A horizontal list hands its children
            // loose vertical constraints, so the 40dp pill would sit
            // against the TOP of the 64dp row and put all the slack
            // underneath it — the row would look pushed up against the
            // card above.
            child: Center(
              child: _Tile(
                label: label,
                icon: icon,
                hero: hero,
                onTap: () => tab < 0
                    ? context.pushNamed('quiz')
                    : context.pushNamed('library', extra: tab),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.label,
    required this.icon,
    required this.hero,
    required this.onTap,
  });

  final String label;
  final IconData icon;

  /// The one tile that gets a full brand gradient instead of a tinted fill.
  final bool hero;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Semantics(
      button: true,
      label: label,
      child: Pressable(
        onTap: onTap,
        haptics: true,
        pressedScale: 0.94,
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
          decoration: BoxDecoration(
            gradient: hero ? AppColors.primaryGradient : null,
            color: hero ? null : palette.card,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: hero ? null : Border.all(color: palette.divider),
            boxShadow: hero
                ? [
                    BoxShadow(
                      color: AppColors.primaryBlue.withValues(alpha: 0.28),
                      blurRadius: 12,
                      offset: const Offset(0, 5),
                    ),
                  ]
                : AppShadows.card(context),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: hero ? AppColors.white : AppColors.primaryBlue,
              ),
              const SizedBox(width: AppSpace.sm - 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.labelMedium.copyWith(
                  color: hero ? AppColors.white : palette.text,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
