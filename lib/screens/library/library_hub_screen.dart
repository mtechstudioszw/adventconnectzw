import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:go_router/go_router.dart';

import '../../models/devotion_model.dart';
import '../../models/youtube_video.dart';
import '../../services/devotion_service.dart';
import '../../services/quiz_progress_service.dart';
import '../../services/youtube_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/cached_image.dart';
import '../../widgets/motion/pressable.dart';
import '../../widgets/screen_shell.dart';
import 'beliefs_screen.dart';
import 'devotion_screen.dart';
import 'library_directory_screen.dart';
import 'library_saved_screen.dart';
import 'library_search_screen.dart';
import 'library_continue.dart';

/// The Library tab (owner, 29 Oct 2026 — it replaced Watch in the island).
///
/// One place for everything people read, sing, study and watch:
///   * **Continue** — where the member actually left off, read from the
///     same prefs each section already keeps. Nothing shows until there is
///     real progress; a first-time member sees the toolkit instead.
///   * **Toolkit** — every section, always visible, one tap.
///   * **Today** — today's devotion; opens [DevotionScreen].
///   * **Watch** — live streams first, then the latest videos. Watch keeps
///     all its own screens; this is the door to them.
///
/// The sections themselves still open in [LibraryScreen] (route `library`,
/// extra = tab index) so nothing that links there today changes.
class LibraryHubScreen extends StatefulWidget {
  const LibraryHubScreen({super.key, this.autoLoad = true});

  /// False in widget tests: no Supabase, no network.
  final bool autoLoad;

  @override
  State<LibraryHubScreen> createState() => _LibraryHubScreenState();
}

class _LibraryHubScreenState extends State<LibraryHubScreen> {
  Devotion? _devotion;
  List<YoutubeVideo> _live = const [];
  List<YoutubeVideo> _latest = const [];
  List<ContinueEntry> _continue = const [];

  @override
  void initState() {
    super.initState();
    if (!widget.autoLoad) return;
    _devotion = DevotionService.cachedToday();
    _live = YoutubeService.cachedLiveNow();
    _latest = _latestOf(YoutubeService.cachedFeed());
    unawaited(_load());
    for (final l in LibraryContinue.changes) {
      l.addListener(_onPrefs);
    }
  }

  @override
  void dispose() {
    if (widget.autoLoad) {
      for (final l in LibraryContinue.changes) {
        l.removeListener(_onPrefs);
      }
    }
    super.dispose();
  }

  void _onPrefs() => unawaited(_reloadContinue());

  static List<YoutubeVideo> _latestOf(List<YoutubeVideo> feed) =>
      feed.where((v) => !v.isLive).take(10).toList();

  Future<void> _load() async {
    unawaited(_reloadContinue());
    final results = await Future.wait<Object?>([
      DevotionService.fetchToday(),
      YoutubeService.fetchLiveNow(),
      YoutubeService.fetchFeed(limit: 12),
    ]);
    if (!mounted) return;
    setState(() {
      _devotion = (results[0] as Devotion?) ?? _devotion;
      _live = results[1] as List<YoutubeVideo>;
      _latest = _latestOf(results[2] as List<YoutubeVideo>);
    });
  }

  Future<void> _reloadContinue() async {
    final items = await LibraryContinue.load();
    if (mounted) setState(() => _continue = items);
  }

  void _openSection(int tab) {
    HapticFeedback.selectionClick();
    _refreshAfter(context.pushNamed('library', extra: tab));
  }

  /// This tab stays alive behind everything it opens, and the Bible and
  /// Hymnal record a position without notifying anyone — so re-read the
  /// Continue row whenever the member comes back.
  Future<void> _refreshAfter(Future<Object?> route) async {
    await route;
    if (mounted) unawaited(_reloadContinue());
  }

  void _openDevotion() {
    HapticFeedback.selectionClick();
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => DevotionScreen(devotion: _devotion),
      ),
    );
  }

  void _openVideo(YoutubeVideo v) => context.pushNamed(
    'watch_video',
    pathParameters: {'id': v.videoId},
    extra: v,
  );

  void _push(Widget screen) {
    HapticFeedback.selectionClick();
    _refreshAfter(
      Navigator.of(
        context,
        rootNavigator: true,
      ).push<void>(MaterialPageRoute<void>(builder: (_) => screen)),
    );
  }

  List<_Tool> get _tools {
    final streak = widget.autoLoad ? QuizProgressService.currentStreak() : 0;
    return [
      _Tool('Bible', Icons.menu_book_rounded, () => _openSection(0)),
      _Tool('Sabbath School', Icons.school_rounded, () => _openSection(1)),
      _Tool('Hymnal', Icons.queue_music_rounded, () => _openSection(2)),
      _Tool('EGW', Icons.auto_stories_rounded, () => _openSection(3)),
      _Tool(
        'Watch',
        Icons.play_circle_fill_rounded,
        () => context.pushNamed('watch'),
      ),
      // The one gold mark on this screen: the streak is the thing worth
      // celebrating, and it only shows once there is one.
      _Tool(
        'Quiz',
        Icons.emoji_events_rounded,
        () => context.pushNamed('quiz'),
        badge: streak > 0 ? '$streak' : null,
        gold: true,
      ),
      _Tool(
        '28 Beliefs',
        Icons.history_edu_rounded,
        () => _push(const BeliefsScreen()),
      ),
      // Every other resource — Prayer, News, Churches, Events, Music —
      // with format, source and offline status.
      _Tool(
        'More',
        Icons.add_rounded,
        () => _push(const LibraryDirectoryScreen()),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return FlatStatusBar(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          bottom: false,
          child: RefreshIndicator(
            onRefresh: _load,
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpace.lg,
                      AppSpace.lg,
                      AppSpace.lg,
                      AppSpace.xs,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Library',
                            style: AppTextStyles.headlineMedium.copyWith(
                              color: palette.text,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        HeaderIconButton(
                          icon: Icons.bookmarks_rounded,
                          tooltip: 'Saved & downloads',
                          onTap: () => _push(const LibrarySavedScreen()),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpace.lg,
                    ),
                    child: Text(
                      'Read, sing, study and watch — all in one place.',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: palette.textMuted,
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpace.lg,
                      AppSpace.lg,
                      AppSpace.lg,
                      0,
                    ),
                    child: _SearchBar(
                      onTap: () => _push(const LibrarySearchScreen()),
                    ),
                  ),
                ),
                if (_continue.isNotEmpty) ...[
                  const _Heading('CONTINUE'),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 92,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpace.lg,
                        ),
                        itemCount: _continue.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(width: AppSpace.md),
                        itemBuilder: (context, i) => _ContinueCard(
                          item: _continue[i],
                          onTap: () =>
                              _refreshAfter(_continue[i].open(context)),
                        ),
                      ),
                    ),
                  ),
                ],
                const _Heading('YOUR TOOLKIT'),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4,
                      mainAxisSpacing: AppSpace.md,
                      crossAxisSpacing: AppSpace.sm,
                      // Tile + gap + two label lines, grown with the
                      // system font so "Sabbath School" never clips.
                      mainAxisExtent:
                          68 + 34 * MediaQuery.textScalerOf(context).scale(1),
                    ),
                    delegate: SliverChildListDelegate([
                      for (final t in _tools) _ToolTile(tool: t),
                    ]),
                  ),
                ),
                if (_devotion != null) ...[
                  const _Heading('TODAY'),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpace.lg,
                      ),
                      child: _DevotionCard(
                        devotion: _devotion!,
                        onTap: _openDevotion,
                      ),
                    ),
                  ),
                ],
                if (_live.isNotEmpty || _latest.isNotEmpty) ...[
                  _Heading(
                    'WATCH',
                    action: 'See all',
                    onAction: () => context.pushNamed('watch'),
                  ),
                  for (final v in _live.take(3))
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpace.lg,
                          0,
                          AppSpace.lg,
                          AppSpace.md,
                        ),
                        child: _LiveRow(video: v, onTap: () => _openVideo(v)),
                      ),
                    ),
                  if (_latest.isNotEmpty)
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: 150,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpace.lg,
                          ),
                          itemCount: _latest.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(width: AppSpace.md),
                          itemBuilder: (context, i) => _VideoTile(
                            video: _latest[i],
                            onTap: () => _openVideo(_latest[i]),
                          ),
                        ),
                      ),
                    ),
                ],
                // Clears the floating island.
                const SliverToBoxAdapter(child: SizedBox(height: 120)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
//  Pieces
// ---------------------------------------------------------------------------

class _Tool {
  const _Tool(
    this.label,
    this.icon,
    this.onTap, {
    this.badge,
    this.gold = false,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final String? badge;
  final bool gold;
}

class _Heading extends StatelessWidget {
  const _Heading(this.label, {this.action, this.onAction});
  final String label;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.lg,
          AppSpace.xl,
          AppSpace.sm,
          AppSpace.sm,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: AppTextStyles.overline.copyWith(
                  color: palette.textMuted,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (action != null)
              TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primaryBlue,
                  visualDensity: VisualDensity.compact,
                  textStyle: AppTextStyles.labelMedium.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: Text(action!),
              ),
          ],
        ),
      ),
    );
  }
}

BoxDecoration _cardDecoration(BuildContext context) => BoxDecoration(
  color: context.palette.card,
  borderRadius: BorderRadius.circular(AppRadius.card),
  boxShadow: AppShadows.card(context),
);

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.item, required this.onTap});
  final ContinueEntry item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Pressable(
      onTap: onTap,
      child: Container(
        width: 230,
        padding: const EdgeInsets.all(AppSpace.md),
        decoration: _cardDecoration(context),
        child: Row(
          children: [
            _IconChip(icon: item.icon),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.kind.toUpperCase(),
                    style: AppTextStyles.overline.copyWith(
                      color: palette.brandBlue,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.titleSmall.copyWith(
                      color: palette.text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (item.subtitle.isNotEmpty)
                    Text(
                      item.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption.copyWith(
                        color: palette.textMuted,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IconChip extends StatelessWidget {
  const _IconChip({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: AppColors.primaryBlue.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.button),
      ),
      child: Icon(icon, color: context.palette.brandBlue, size: 24),
    );
  }
}

class _ToolTile extends StatelessWidget {
  const _ToolTile({required this.tool});
  final _Tool tool;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Semantics(
      button: true,
      label: tool.badge == null
          ? tool.label
          : '${tool.label}, ${tool.badge} day streak',
      excludeSemantics: true,
      child: Pressable(
        onTap: tool.onTap,
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: _cardDecoration(context),
                  alignment: Alignment.center,
                  child: Icon(
                    tool.icon,
                    size: 28,
                    color: tool.gold
                        ? AppColors.goldAccent
                        : context.palette.brandBlue,
                  ),
                ),
                if (tool.badge != null)
                  Positioned(
                    right: -4,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.goldAccent,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        border: Border.all(color: palette.card, width: 2),
                      ),
                      child: Text(
                        '🔥${tool.badge}',
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.darkNavy,
                          fontWeight: FontWeight.w700,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpace.sm),
            Text(
              tool.label,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.caption.copyWith(
                color: palette.text,
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DevotionCard extends StatelessWidget {
  const _DevotionCard({required this.devotion, required this.onTap});
  final Devotion devotion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpace.lg),
        decoration: _cardDecoration(context),
        child: Row(
          children: [
            const _IconChip(icon: Icons.wb_twilight_rounded),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "TODAY'S DEVOTION",
                    style: AppTextStyles.overline.copyWith(
                      color: palette.brandBlue,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '"${devotion.bibleText}"',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: palette.text,
                      fontStyle: FontStyle.italic,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    devotion.bibleRef,
                    style: AppTextStyles.caption.copyWith(
                      color: palette.textMuted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: palette.textMuted),
          ],
        ),
      ),
    );
  }
}

class _LiveRow extends StatelessWidget {
  const _LiveRow({required this.video, required this.onTap});
  final YoutubeVideo video;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpace.md),
        decoration: _cardDecoration(context),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: SizedBox(
                width: 96,
                height: 54,
                child: (video.thumbnailUrl ?? '').isEmpty
                    ? ColoredBox(color: palette.cardMuted)
                    : CachedImage(video.thumbnailUrl!, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.red,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text(
                      'LIVE',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 10,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    video.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.labelLarge.copyWith(
                      color: palette.text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    video.channelTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption.copyWith(
                      color: palette.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VideoTile extends StatelessWidget {
  const _VideoTile({required this.video, required this.onTap});
  final YoutubeVideo video;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Pressable(
      onTap: onTap,
      child: SizedBox(
        width: 200,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: SizedBox(
                width: 200,
                height: 112,
                child: (video.thumbnailUrl ?? '').isEmpty
                    ? ColoredBox(color: palette.cardMuted)
                    : CachedImage(video.thumbnailUrl!, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              video.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.caption.copyWith(
                color: palette.text,
                fontWeight: FontWeight.w600,
                height: 1.25,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Looks like a field; opens [LibrarySearchScreen], which owns the real
/// one (and the keyboard).
class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Semantics(
      button: true,
      label: 'Search the Library',
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap,
        pressedScale: 0.98,
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
          decoration: BoxDecoration(
            color: palette.card,
            borderRadius: BorderRadius.circular(AppRadius.button),
            boxShadow: AppShadows.card(context),
          ),
          child: Row(
            children: [
              Icon(Icons.search_rounded, color: palette.textMuted),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Text(
                  'Search verses, hymns, books, beliefs',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: palette.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
