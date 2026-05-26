import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/advent_news_model.dart';
import '../../services/advent_news_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/cached_image.dart';

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

  @override
  void initState() {
    super.initState();
    _item = widget.initialItem;
    if (_item == null) {
      _load();
    } else {
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

  Future<void> _share() async {
    final item = _item;
    if (item == null) return;
    final url = item.sourceUrl;
    final body = url != null && url.isNotEmpty
        ? '${item.title}\n\n${item.summary}\n\n$url'
        : '${item.title}\n\n${item.summary}\n\nSeen on Advent Connect ZW.';
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
      return const Scaffold(
        backgroundColor: AppColors.lightGrey,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primaryBlue),
        ),
      );
    }
    if (item == null) {
      return Scaffold(
        backgroundColor: AppColors.lightGrey,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.textDark),
            onPressed: () => context.canPop()
                ? context.pop()
                : context.goNamed('news'),
          ),
        ),
        body: Center(
          child: Text(
            'Story not found.',
            style: AppTextStyles.bodyMedium,
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: AppColors.lightGrey,
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
                          color: const Color.fromRGBO(26, 26, 46, 0.55),
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
                      color: AppColors.darkNavy,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    item.summary,
                    style: AppTextStyles.bodyLarge.copyWith(
                      color: const Color.fromRGBO(26, 26, 46, 0.75),
                      height: 1.55,
                      fontSize: 15,
                    ),
                  ),
                  if ((item.body ?? '').isNotEmpty) ...[
                    const SizedBox(height: 18),
                    Container(
                      height: 1,
                      color: const Color.fromRGBO(26, 26, 46, 0.08),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      item.body!,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.textDark,
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
                        color: const Color.fromRGBO(26, 26, 46, 0.65),
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
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Source link copied.',
                                  style: AppTextStyles.bodyMedium.copyWith(
                                      color: AppColors.white),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
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
              ? CachedImage(item.coverPhotoUrl!, fit: BoxFit.cover)
              : const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: AppColors.appBarGradient,
                  ),
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
                      ? context.pop()
                      : context.goNamed('news'),
                ),
                const Spacer(),
                _CircleIconButton(
                  icon: Icons.ios_share,
                  onTap: _share,
                ),
              ],
            ),
          ),
        ),
      ],
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
      color: AppColors.white,
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
                        color: const Color.fromRGBO(26, 26, 46, 0.55),
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
            color: AppColors.lightGrey,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: const Color.fromRGBO(26, 26, 46, 0.06),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: AppColors.primaryBlue, size: 16),
              const SizedBox(width: 7),
              Text(
                label,
                style: AppTextStyles.labelMedium.copyWith(
                  color: AppColors.textDark,
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
  final diff = DateTime.now().difference(then);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} hr ago';
  if (diff.inDays < 7) return '${diff.inDays} d ago';
  if (diff.inDays < 30) return '${(diff.inDays / 7).floor()} wk ago';
  return '${(diff.inDays / 30).floor()} mo ago';
}
