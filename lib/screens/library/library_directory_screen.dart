import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../config/platform_flags.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';
import 'beliefs_screen.dart';
import 'devotion_screen.dart';

/// One resource in the directory.
class DirectoryEntry {
  const DirectoryEntry({
    required this.title,
    required this.icon,
    required this.category,
    required this.format,
    required this.source,
    required this.language,
    required this.offline,
    required this.open,
  });

  final String title;
  final IconData icon;
  final String category;
  final String format;

  /// Who the content comes from — provenance, per the master prompt.
  final String source;
  final String language;

  /// Plain words: "Built in", "Downloadable", "Needs internet".
  final String offline;
  final void Function(BuildContext context) open;
}

/// The Library's "More": every resource the app actually has, with its
/// category, format, source, language and whether it works offline.
///
/// Only real, working content is listed (master prompt: never present
/// unavailable content as complete). Adventist heritage, the Church
/// Manual, the Yearbook, study guides and children's resources are not
/// here because the app does not have that content yet — they need a
/// licensed source first, not a placeholder row.
class LibraryDirectoryScreen extends StatelessWidget {
  const LibraryDirectoryScreen({super.key});

  static void _push(BuildContext context, Widget screen) => Navigator.of(
    context,
    rootNavigator: true,
  ).push<void>(MaterialPageRoute<void>(builder: (_) => screen));

  static List<DirectoryEntry> get entries => [
    DirectoryEntry(
      title: 'Bible',
      icon: Icons.menu_book_rounded,
      category: 'Scripture',
      format: 'Text · audio Bible',
      source: 'KJV built in; other translations online',
      language: 'English and more online',
      offline: 'KJV built in',
      open: (c) => c.pushNamed('library', extra: 0),
    ),
    DirectoryEntry(
      title: 'Sabbath School',
      icon: Icons.school_rounded,
      category: 'Bible study',
      format: 'Daily lessons',
      source: 'Adventech (Sabbath School lessons)',
      language: 'About 90 languages',
      offline: 'Needs internet',
      open: (c) => c.pushNamed('library', extra: 1),
    ),
    DirectoryEntry(
      title: 'Hymnal',
      icon: Icons.queue_music_rounded,
      category: 'Worship',
      format: 'Lyrics',
      source: 'SDA Hymnal and Kristu Munzwiyo, built in',
      language: 'English and Shona',
      offline: 'Built in',
      open: (c) => c.pushNamed('library', extra: 2),
    ),
    DirectoryEntry(
      title: 'Ellen G. White books',
      icon: Icons.auto_stories_rounded,
      category: 'Spirit of Prophecy',
      format: 'Reflowable books (EPUB), PDF fallback',
      source: 'Ellen G. White writings',
      language: 'English',
      offline: 'Downloadable',
      open: (c) => c.pushNamed('library', extra: 3),
    ),
    DirectoryEntry(
      title: '28 Fundamental Beliefs',
      icon: Icons.history_edu_rounded,
      category: 'Beliefs',
      format: 'Summaries · Bible texts',
      source: 'App summaries; official text at adventist.org',
      language: 'English',
      offline: 'Built in',
      open: (c) => _push(c, const BeliefsScreen()),
    ),
    DirectoryEntry(
      title: 'Reading plans',
      icon: Icons.event_note_rounded,
      category: 'Bible study',
      format: 'Daily readings · reminders',
      source: 'Plans made from the Bible in the app',
      language: 'Follows your Bible',
      offline: 'Built in',
      open: (c) => c.pushNamed('reading_plans'),
    ),
    DirectoryEntry(
      title: 'Memory verses',
      icon: Icons.psychology_alt_rounded,
      category: 'Learning',
      format: 'Spaced practice',
      source: 'Verses you choose',
      language: 'Follows your Bible',
      offline: 'Built in',
      open: (c) => c.pushNamed('memory_verses'),
    ),
    DirectoryEntry(
      title: 'Sabbath hours',
      icon: Icons.wb_twilight_rounded,
      category: 'Sabbath',
      format: 'Sundown times · Friday reminder',
      source: 'Calculated on your phone',
      language: 'English',
      offline: 'Built in',
      open: (c) => c.pushNamed('sabbath_hours'),
    ),
    DirectoryEntry(
      title: "Today's devotion",
      icon: Icons.wb_twilight_rounded,
      category: 'Devotional',
      format: 'Verse · EGW reading',
      source: 'Daily devotion',
      language: 'English',
      offline: 'Needs internet',
      open: (c) => _push(c, const DevotionScreen()),
    ),
    DirectoryEntry(
      title: 'Watch',
      icon: Icons.play_circle_fill_rounded,
      category: 'Video',
      format: 'Live services · sermons · Shorts',
      source: 'Church and ministry YouTube channels',
      language: 'Mixed',
      offline: 'Needs internet',
      open: (c) => c.pushNamed('watch'),
    ),
    DirectoryEntry(
      title: 'Bible quiz',
      icon: Icons.emoji_events_rounded,
      category: 'Learning',
      format: 'Daily challenge · live matches',
      source: 'App quiz',
      language: 'English',
      offline: 'Needs internet',
      open: (c) => c.pushNamed('quiz'),
    ),
    DirectoryEntry(
      title: 'Prayer',
      icon: Icons.volunteer_activism_rounded,
      category: 'Prayer',
      format: 'Requests · praying with others',
      source: 'Members of the app',
      language: 'Mixed',
      offline: 'Needs internet',
      open: (c) => c.pushNamed('prayer'),
    ),
    if (!kHideMusic)
      DirectoryEntry(
        title: 'Music',
        icon: Icons.headphones_rounded,
        category: 'Worship',
        format: 'Audio',
        source: 'Uploaded worship music',
        language: 'Mixed',
        offline: 'Needs internet',
        open: (c) => c.pushNamed('library', extra: 4),
      ),
    DirectoryEntry(
      title: 'News',
      icon: Icons.newspaper_rounded,
      category: 'Church life',
      format: 'Articles',
      source: 'Adventist news',
      language: 'English',
      offline: 'Needs internet',
      open: (c) => c.pushNamed('news'),
    ),
    DirectoryEntry(
      title: 'Churches',
      icon: Icons.church_rounded,
      category: 'Directory',
      format: 'Church listings · map',
      source: 'Churches registered in the app',
      language: 'English',
      offline: 'Needs internet',
      open: (c) => c.pushNamed('churches'),
    ),
    DirectoryEntry(
      title: 'Events',
      icon: Icons.event_rounded,
      category: 'Church life',
      format: 'Camp meetings · crusades · more',
      source: 'Churches and members',
      language: 'English',
      offline: 'Needs internet',
      open: (c) => c.pushNamed('events'),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final list = entries;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'All resources',
          style: AppTextStyles.appBarTitleFlat.copyWith(fontSize: 19),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.lg,
            AppSpace.sm,
            AppSpace.lg,
            AppSpace.xxl,
          ),
          itemCount: list.length,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpace.sm),
          itemBuilder: (context, i) {
            final e = list[i];
            return Material(
              color: palette.card,
              borderRadius: BorderRadius.circular(AppRadius.card),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.card),
                onTap: () => e.open(context),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpace.md),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.primaryBlue.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        child: Icon(e.icon, color: palette.brandBlue),
                      ),
                      const SizedBox(width: AppSpace.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              e.category.toUpperCase(),
                              style: AppTextStyles.overline.copyWith(
                                color: palette.brandBlue,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              e.title,
                              style: AppTextStyles.labelLarge.copyWith(
                                color: palette.text,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${e.format} · ${e.language}',
                              style: AppTextStyles.caption.copyWith(
                                color: palette.textMuted,
                              ),
                            ),
                            Text(
                              e.source,
                              style: AppTextStyles.caption.copyWith(
                                color: palette.textMuted,
                              ),
                            ),
                            const SizedBox(height: AppSpace.xs),
                            _OfflineTag(text: e.offline),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _OfflineTag extends StatelessWidget {
  const _OfflineTag({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final online = text == 'Needs internet';
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: online
            ? palette.chipBg
            : AppColors.successGreen.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            online ? Icons.wifi_rounded : Icons.offline_pin_rounded,
            size: 12,
            color: online ? palette.textMuted : palette.brandGreen,
          ),
          const SizedBox(width: 4),
          Text(
            text,
            style: AppTextStyles.caption.copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: online ? palette.textMuted : palette.brandGreen,
            ),
          ),
        ],
      ),
    );
  }
}
