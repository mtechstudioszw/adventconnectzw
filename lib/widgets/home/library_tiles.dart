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
/// Replaces two things at once: the five ~48dp chips (each carrying a 10pt
/// label — the smallest text on the screen was advertising the app's whole
/// consolidation pitch) and the standalone Quiz Arena card below them.
///
/// Ordering is deliberate. On a 360dp screen four tiles fit fully and the
/// fifth peeks, which is what invites the scroll — so **Quiz sits fourth**,
/// fully visible. This row is still the ONLY route into `/quiz`; don't
/// reorder it out of view without adding another entry point.
class LibraryTiles extends StatelessWidget {
  const LibraryTiles({super.key});

  static const double _tile = 78;

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
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
        itemCount: _items.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpace.sm + 2),
        itemBuilder: (context, i) {
          final (label, icon, tab, hero) = _items[i];
          // Only six items and they all build at once, so a stagger here
          // can't replay on scroll the way it would in a long lazy list.
          return StaggeredReveal(
            index: i,
            rise: 12,
            interval: const Duration(milliseconds: 40),
            child: _Tile(
              label: label,
              icon: icon,
              hero: hero,
              onTap: () => tab < 0
                  ? context.pushNamed('quiz')
                  : context.pushNamed('library', extra: tab),
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
        pressedScale: 0.92,
        child: SizedBox(
          width: LibraryTiles._tile,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  gradient: hero ? AppColors.primaryGradient : null,
                  color: hero
                      ? null
                      : AppColors.primaryBlue.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: hero
                      ? null
                      : Border.all(color: palette.divider, width: 1),
                  boxShadow: hero
                      ? [
                          BoxShadow(
                            color: AppColors.primaryBlue.withValues(
                              alpha: 0.28,
                            ),
                            blurRadius: 14,
                            offset: const Offset(0, 6),
                          ),
                        ]
                      : null,
                ),
                alignment: Alignment.center,
                child: Icon(
                  icon,
                  size: 26,
                  color: hero ? AppColors.white : AppColors.primaryBlue,
                ),
              ),
              const SizedBox(height: AppSpace.sm),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: AppTextStyles.labelMedium.copyWith(
                  color: palette.text,
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
