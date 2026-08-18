import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/advent_news_model.dart';
import '../../services/advent_news_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/cached_image.dart';
import '../../widgets/full_image_viewer.dart';
import '../../widgets/motion/brand_spinner.dart';

/// Article view for a single Advent News piece. Arrives either with
/// the full [initialItem] pre-loaded from the list screen, or just an
/// id (push notification deep link path) — in which case we fetch.
class AdventNewsDetailsScreen extends StatefulWidget {
  const AdventNewsDetailsScreen({
    super.key,
    required this.newsId,
    this.initialItem,
  });

  final String newsId;
  final AdventNews? initialItem;

  @override
  State<AdventNewsDetailsScreen> createState() =>
      _AdventNewsDetailsScreenState();
}

class _AdventNewsDetailsScreenState extends State<AdventNewsDetailsScreen> {
  AdventNews? _item;
  bool _loading = false;
  // True once this story was edited or deleted, so the list we return to
  // refreshes (fixes "deleted post lingers / delete twice").
  bool _changed = false;

  /// What to read next. Loaded separately from the article and never
  /// awaited alongside it — the story must paint the moment it can, and a
  /// section below the fold has no business delaying that.
  List<AdventNews> _related = const [];

  @override
  void initState() {
    super.initState();
    _item = widget.initialItem;
    if (_item == null) {
      _load();
    } else {
      unawaited(_loadRelated());
      // Fire a quiet background refresh so opened-from-cache stories
      // get the latest body / source link if the article has been
      // edited since the list paint.
      _refreshQuietly();
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final fresh = await AdventNewsService.fetchNewsById(widget.newsId);
    if (!mounted) return;
    setState(() {
      _item = fresh;
      _loading = false;
    });
    unawaited(_loadRelated());
  }

  /// Best-effort: an empty rail simply doesn't render, so a failure here
  /// costs the reader nothing and must never surface an error over an
  /// article they are in the middle of.
  Future<void> _loadRelated() async {
    final item = _item;
    if (item == null) return;
    final more = await AdventNewsService.fetchRelated(
      item.id,
      category: item.category,
    );
    if (!mounted) return;
    setState(() => _related = more);
  }

  Future<void> _refreshQuietly() async {
    final fresh = await AdventNewsService.fetchNewsById(widget.newsId);
    if (!mounted || fresh == null) return;
    setState(() => _item = fresh);
  }

  Future<void> _openSource() async {
    final url = _item?.sourceUrl;
    if (url == null || url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not open the source link.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    }
  }

  bool get _isOwner {
    final me = AuthService.currentUser;
    final authorId = _item?.authorId;
    if (me == null || authorId == null || authorId.isEmpty) return false;
    return me.id == authorId;
  }

  Future<void> _editStory() async {
    final item = _item;
    if (item == null) return;
    // The composer now returns a bool (true = saved). Re-fetch the fresh
    // row instead of relying on a returned object so the details view and
    // the list never show stale edits.
    final changed = await context.pushNamed<bool>('post_news', extra: item);
    if (!mounted) return;
    if (changed == true) {
      _changed = true;
      _refreshQuietly();
    }
  }

  Future<void> _confirmDelete() async {
    final item = _item;
    if (item == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.palette.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          'Delete this story?',
          style: AppTextStyles.titleMedium.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          'It will be removed from the feed for everyone. This can\'t be undone.',
          style: AppTextStyles.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: AppTextStyles.labelMedium.copyWith(
                color: ctx.palette.text,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Delete',
              style: AppTextStyles.labelMedium.copyWith(color: AppColors.red),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await AdventNewsService.deleteNews(item.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.successGreen,
          content: Text(
            'Story deleted.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
      if (context.canPop()) {
        context.pop(true); // signal the list to refresh
      } else {
        context.goNamed('news');
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.red,
          content: Text(
            'Could not delete. You may not have permission.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    }
  }

  void _showOwnerMenu() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.palette.sheet,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: ctx.palette.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: const Icon(
                  Icons.edit_outlined,
                  color: AppColors.primaryBlue,
                ),
                title: Text(
                  'Edit story',
                  style: AppTextStyles.bodyLarge.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _editStory();
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: AppColors.red),
                title: Text(
                  'Delete story',
                  style: AppTextStyles.bodyLarge.copyWith(
                    color: AppColors.red,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmDelete();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _share() async {
    final item = _item;
    if (item == null) return;
    // Send recipients to the live Play Store listing (installers get the
    // app; people who already have it see "Open" on the listing).
    const appUrl =
        'https://play.google.com/store/apps/details?id=io.supabase.adventconnectzw.advent_connect_zw';
    final body =
        '${item.title}\n\n${item.summary}\n\nRead more on Adventist Super App: $appUrl';
    try {
      await Share.share(body, subject: item.title);
    } catch (_) {
      // share_plus errors are usually "no installed share targets" —
      // not worth bothering the user about.
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = _item;
    if (item == null && _loading) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: const Center(child: BrandSpinner(size: 30)),
      );
    }
    if (item == null) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: context.palette.text),
            onPressed: () => context.canPop()
                ? context.pop(_changed)
                : context.goNamed('news'),
          ),
        ),
        body: Center(
          child: Text('Story not found.', style: AppTextStyles.bodyMedium),
        ),
      );
    }
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _buildHero(item, context)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _CategoryPill(label: item.category.label.toUpperCase()),
                      const SizedBox(width: 8),
                      Text(
                        _relative(item.publishedAt),
                        style: AppTextStyles.labelSmall.copyWith(
                          color: context.palette.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    item.title,
                    style: AppTextStyles.displayMedium.copyWith(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                      color: context.palette.text,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    item.summary,
                    style: AppTextStyles.bodyLarge.copyWith(
                      color: context.palette.text,
                      height: 1.55,
                      fontSize: 15,
                    ),
                  ),
                  if ((item.body ?? '').isNotEmpty) ...[
                    const SizedBox(height: 18),
                    Container(height: 1, color: context.palette.divider),
                    const SizedBox(height: 18),
                    Text(
                      item.body!,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: context.palette.text,
                        height: 1.65,
                        fontSize: 15,
                      ),
                    ),
                  ],
                  if ((item.authorName ?? '').isNotEmpty) ...[
                    const SizedBox(height: 22),
                    Text(
                      'By ${item.authorName}',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: context.palette.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  if ((item.sourceUrl ?? '').isNotEmpty) ...[
                    const SizedBox(height: 18),
                    _SourceLinkCard(
                      label: item.sourceLabel ?? 'Open original source',
                      url: item.sourceUrl!,
                      onTap: _openSource,
                    ),
                  ],
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: _ActionButton(
                          icon: Icons.share_outlined,
                          label: 'Share',
                          onTap: _share,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _ActionButton(
                          icon: Icons.link,
                          label: 'Copy link',
                          onTap: () async {
                            final url = item.sourceUrl;
                            if (url == null || url.isEmpty) return;
                            await Clipboard.setData(ClipboardData(text: url));
                            if (!mounted) return;
                            // ignore: use_build_context_synchronously
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Source link copied.',
                                  style: AppTextStyles.bodyMedium.copyWith(
                                    color: AppColors.white,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                  if (_related.isNotEmpty) _buildKeepReading(context),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// "Keep reading" — the whole of the suggested-news work.
  ///
  /// Before this, finishing an article left the reader on a page whose only
  /// exits were Back and the source link, so an Advent News session was
  /// exactly one story long no matter how much had been published.
  ///
  /// A vertical list, not a horizontal rail: these are headlines, and a
  /// headline clipped to a 200px card is a headline nobody can judge. Three
  /// readable titles beat six unreadable ones.
  Widget _buildKeepReading(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 28),
        Divider(color: palette.divider, height: 1),
        const SizedBox(height: 20),
        Text(
          'KEEP READING',
          style: AppTextStyles.labelSmall.copyWith(
            color: AppColors.primaryBlue,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.4,
            fontSize: 10.5,
          ),
        ),
        const SizedBox(height: 12),
        for (final n in _related.take(4)) ...[
          _RelatedNewsRow(
            item: n,
            onTap: () {
              // pushReplacement, not push: tapping through five articles
              // should not build a five-deep stack the reader has to unwind
              // one Back press at a time to get out of Advent News.
              // 'news_details', NOT 'advent_news_details' — the route is
              // nested under /news as ':id'. GoRouter throws on an unknown
              // name, which is precisely how Settings → Help center shipped
              // broken (see help_center_screen.dart). Pinned by a test.
              context.pushReplacementNamed(
                'news_details',
                pathParameters: {'id': n.id},
                extra: n,
              );
            },
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildHero(AdventNews item, BuildContext context) {
    final hasCover = (item.coverPhotoUrl ?? '').isNotEmpty;
    return Stack(
      children: [
        SizedBox(
          width: double.infinity,
          height: 280,
          child: hasCover
              ? GestureDetector(
                  onTap: () =>
                      FullImageViewer.show(context, item.coverPhotoUrl),
                  child: CachedImage(item.coverPhotoUrl!, fit: BoxFit.cover),
                )
              : const DecoratedBox(
                  decoration: BoxDecoration(gradient: AppColors.appBarGradient),
                  child: Center(
                    child: Icon(
                      Icons.newspaper,
                      color: AppColors.white,
                      size: 72,
                    ),
                  ),
                ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.20),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: [
                _CircleIconButton(
                  icon: Icons.arrow_back,
                  onTap: () => context.canPop()
                      ? context.pop(_changed)
                      : context.goNamed('news'),
                ),
                const Spacer(),
                if (_isOwner)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _CircleIconButton(
                      icon: Icons.more_horiz,
                      onTap: _showOwnerMenu,
                    ),
                  ),
                _CircleIconButton(icon: Icons.ios_share, onTap: _share),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One "keep reading" suggestion: thumbnail, headline, category + age.
///
/// The headline gets two lines and the full remaining width, because a
/// headline is the only thing a reader uses to decide. The thumbnail is
/// square and small on purpose — this is a list of stories, not a second
/// magazine spread competing with the article above it.
class _RelatedNewsRow extends StatelessWidget {
  const _RelatedNewsRow({required this.item, required this.onTap});

  final AdventNews item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final cover = item.coverPhotoUrl ?? '';
    return Material(
      color: palette.card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 68,
                  height: 68,
                  child: cover.isEmpty
                      ? Container(
                          color: AppColors.primaryBlue.withValues(alpha: 0.08),
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.newspaper_outlined,
                            size: 22,
                            color:
                                AppColors.primaryBlue.withValues(alpha: 0.55),
                          ),
                        )
                      : CachedImage(cover, fit: BoxFit.cover),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${item.category.label} · ${_relative(item.publishedAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.labelSmall.copyWith(
                        color: palette.textMuted,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryPill extends StatelessWidget {
  const _CategoryPill({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primaryBlue.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: AppTextStyles.labelSmall.copyWith(
          color: AppColors.primaryBlue,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _SourceLinkCard extends StatelessWidget {
  const _SourceLinkCard({
    required this.label,
    required this.url,
    required this.onTap,
  });

  final String label;
  final String url;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.palette.card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppColors.primaryBlue.withValues(alpha: 0.18),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.public,
                  color: AppColors.primaryBlue,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: AppTextStyles.titleMedium.copyWith(
                        color: AppColors.primaryBlue,
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: context.palette.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.open_in_new,
                color: AppColors.primaryBlue,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 10),
          decoration: BoxDecoration(
            color: context.palette.cardMuted,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.palette.divider),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: AppColors.primaryBlue, size: 16),
              const SizedBox(width: 7),
              Text(
                label,
                style: AppTextStyles.labelMedium.copyWith(
                  color: context.palette.text,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color.fromRGBO(0, 0, 0, 0.35),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: AppColors.white, size: 20),
        ),
      ),
    );
  }
}

String _relative(DateTime then) {
  // Real timestamp first, relative label second — readers can tell at
  // a glance both *when* the story was posted and how recent that is.
  final local = then.toLocal();
  final absolute = _absolute(local);
  final diff = DateTime.now().difference(then);
  final String relative;
  if (diff.inMinutes < 1) {
    relative = 'just now';
  } else if (diff.inMinutes < 60) {
    relative = '${diff.inMinutes} min ago';
  } else if (diff.inHours < 24) {
    relative = '${diff.inHours} hr ago';
  } else if (diff.inDays < 7) {
    relative = '${diff.inDays} d ago';
  } else if (diff.inDays < 30) {
    relative = '${(diff.inDays / 7).floor()} wk ago';
  } else {
    relative = '${(diff.inDays / 30).floor()} mo ago';
  }
  return '$absolute · $relative';
}

String _absolute(DateTime t) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final now = DateTime.now();
  final isSameDay =
      t.year == now.year && t.month == now.month && t.day == now.day;
  final time = _formatTime12(t);
  if (isSameDay) return 'Today $time';
  final yesterday = now.subtract(const Duration(days: 1));
  final isYesterday =
      t.year == yesterday.year &&
      t.month == yesterday.month &&
      t.day == yesterday.day;
  if (isYesterday) return 'Yesterday $time';
  if (t.year == now.year) {
    return '${months[t.month - 1]} ${t.day} · $time';
  }
  return '${months[t.month - 1]} ${t.day}, ${t.year}';
}

String _formatTime12(DateTime t) {
  final hour24 = t.hour;
  final hour12 = hour24 == 0 ? 12 : (hour24 > 12 ? hour24 - 12 : hour24);
  final minutes = t.minute.toString().padLeft(2, '0');
  final suffix = hour24 < 12 ? 'AM' : 'PM';
  return '$hour12:$minutes $suffix';
}
