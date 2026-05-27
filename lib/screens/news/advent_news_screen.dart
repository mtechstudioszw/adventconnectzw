import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/advent_news_model.dart';
import '../../services/advent_news_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/cached_image.dart';

/// Editorial Advent News feed — distinct from the user post feed.
/// Hosted at /news; reached from the home hero card and the home
/// header icon. Categorised so members can filter to what they care
/// about most (trending / announcements / global SDA / etc).
class AdventNewsScreen extends StatefulWidget {
  const AdventNewsScreen({super.key});

  @override
  State<AdventNewsScreen> createState() => _AdventNewsScreenState();
}

class _AdventNewsScreenState extends State<AdventNewsScreen> {
  bool _loading = true;
  List<AdventNews> _items = const [];
  NewsCategory? _activeCategory;
  bool _canPublish = false;

  @override
  void initState() {
    super.initState();
    _load();
    _resolveCanPublish();
  }

  Future<void> _resolveCanPublish() async {
    final ok = await AdventNewsService.canPublish();
    if (!mounted) return;
    setState(() => _canPublish = ok);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final items = await AdventNewsService.fetchNews(category: _activeCategory);
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  Future<void> _selectCategory(NewsCategory? next) async {
    if (next == _activeCategory) return;
    setState(() => _activeCategory = next);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightGrey,
      // Admin-only FAB to open the in-app news publisher. Gated by
      // AdventNewsService.canPublish (which mirrors the RLS rule:
      // super admin OR approved church admin). Anyone else just sees
      // the regular news feed with no Post button.
      floatingActionButton: _canPublish
          ? FloatingActionButton.extended(
              onPressed: () async {
                final published =
                    await context.pushNamed<bool>('post_news');
                if (published == true && mounted) await _load();
              },
              backgroundColor: AppColors.primaryBlue,
              foregroundColor: AppColors.white,
              icon: const Icon(Icons.edit_note),
              label: const Text('Post news'),
            )
          : null,
      body: Column(
        children: [
          _buildHero(context),
          _buildCategoryChips(),
          Expanded(
            child: RefreshIndicator(
              color: AppColors.primaryBlue,
              onRefresh: _load,
              child: _buildBody(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHero(BuildContext context) {
    return ClipPath(
      clipper: _HeroClipper(),
      child: Container(
        decoration: const BoxDecoration(gradient: AppColors.appBarGradient),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _CircleIconButton(
                      icon: Icons.arrow_back,
                      onTap: () => context.canPop()
                          ? context.pop()
                          : context.goNamed('home'),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  AppColors.goldAccent.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: AppColors.goldAccent,
                                width: 0.8,
                              ),
                            ),
                            child: Text(
                              'NEWS',
                              style: AppTextStyles.labelSmall.copyWith(
                                color: AppColors.goldAccent,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Advent News',
                        style: AppTextStyles.displayMedium.copyWith(
                          color: AppColors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'What\'s trending in the Adventist community in Zimbabwe.',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.white.withValues(alpha: 0.78),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryChips() {
    return Container(
      color: AppColors.lightGrey,
      child: SizedBox(
        height: 52,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          children: [
            _CategoryChip(
              label: 'All',
              selected: _activeCategory == null,
              onTap: () => _selectCategory(null),
            ),
            for (final c in NewsCategory.values) ...[
              const SizedBox(width: 8),
              _CategoryChip(
                label: c.label,
                selected: _activeCategory == c,
                onTap: () => _selectCategory(c),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _items.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primaryBlue),
      );
    }
    if (_items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 80),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlue.withValues(alpha: 0.10),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.newspaper_outlined,
                      color: AppColors.primaryBlue,
                      size: 40,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'No news yet',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.headlineMedium.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _activeCategory == null
                        ? 'Check back soon. Editorial coverage of the '
                            'Adventist community in Zimbabwe will start '
                            'landing here.'
                        : 'No stories in this category yet. Try another '
                            'category or check back later.',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: const Color.fromRGBO(26, 26, 46, 0.6),
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      itemCount: _items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final item = _items[i];
        // The first card renders as a hero (taller cover) — like a
        // magazine front cover. Everything else is a compact row.
        if (i == 0) {
          return _NewsHeroCard(
            item: item,
            onTap: () => _openDetails(item),
          );
        }
        return _NewsRowCard(
          item: item,
          onTap: () => _openDetails(item),
        );
      },
    );
  }

  void _openDetails(AdventNews item) {
    context.pushNamed(
      'news_details',
      pathParameters: {'id': item.id},
      extra: item,
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.primaryBlue : AppColors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? AppColors.primaryBlue
                  : const Color.fromRGBO(26, 26, 46, 0.1),
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: AppTextStyles.labelMedium.copyWith(
              color: selected ? AppColors.white : AppColors.textDark,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _NewsHeroCard extends StatelessWidget {
  const _NewsHeroCard({required this.item, required this.onTap});

  final AdventNews item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if ((item.coverPhotoUrl ?? '').isEmpty)
                    Container(
                      decoration: const BoxDecoration(
                        gradient: AppColors.appBarGradient,
                      ),
                      child: Center(
                        child: Icon(
                          Icons.newspaper,
                          color: AppColors.white.withValues(alpha: 0.55),
                          size: 56,
                        ),
                      ),
                    )
                  else
                    CachedImage(
                      item.coverPhotoUrl!,
                      fit: BoxFit.cover,
                    ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.55),
                            ],
                            stops: const [0.45, 1.0],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 12,
                    left: 12,
                    child: Row(
                      children: [
                        _CategoryPill(
                          label: item.category.label.toUpperCase(),
                          highlighted: true,
                        ),
                        if (item.isPinned) ...[
                          const SizedBox(width: 6),
                          _CategoryPill(
                            label: 'PINNED',
                            highlighted: true,
                            color: AppColors.goldAccent,
                          ),
                        ],
                      ],
                    ),
                  ),
                  Positioned(
                    left: 14,
                    right: 14,
                    bottom: 14,
                    child: Text(
                      item.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.headlineSmall.copyWith(
                        color: AppColors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 19,
                        height: 1.25,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.summary,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: const Color.fromRGBO(26, 26, 46, 0.78),
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(
                        Icons.schedule,
                        size: 13,
                        color: Color.fromRGBO(26, 26, 46, 0.5),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _relative(item.publishedAt),
                        style: AppTextStyles.labelSmall.copyWith(
                          color: const Color.fromRGBO(26, 26, 46, 0.55),
                          fontSize: 11.5,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'Read',
                        style: AppTextStyles.labelMedium.copyWith(
                          color: AppColors.primaryBlue,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(width: 2),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: AppColors.primaryBlue,
                        size: 20,
                      ),
                    ],
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

class _NewsRowCard extends StatelessWidget {
  const _NewsRowCard({required this.item, required this.onTap});

  final AdventNews item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 96,
                height: 96,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: (item.coverPhotoUrl ?? '').isEmpty
                      ? const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: AppColors.appBarGradient,
                          ),
                          child: Center(
                            child: Icon(
                              Icons.newspaper,
                              color: AppColors.white,
                              size: 26,
                            ),
                          ),
                        )
                      : CachedImage(item.coverPhotoUrl!, fit: BoxFit.cover),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _CategoryPill(label: item.category.label.toUpperCase()),
                    const SizedBox(height: 6),
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.titleMedium.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.summary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: const Color.fromRGBO(26, 26, 46, 0.6),
                        fontSize: 12.5,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _relative(item.publishedAt),
                      style: AppTextStyles.labelSmall.copyWith(
                        color: const Color.fromRGBO(26, 26, 46, 0.5),
                        fontSize: 11,
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
  const _CategoryPill({
    required this.label,
    this.highlighted = false,
    this.color,
  });

  final String label;
  final bool highlighted;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? AppColors.primaryBlue;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: highlighted
            ? tint.withValues(alpha: 0.92)
            : tint.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: AppTextStyles.labelSmall.copyWith(
          color: highlighted
              ? (color == AppColors.goldAccent
                  ? AppColors.darkNavy
                  : AppColors.white)
              : tint,
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
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

class _HeroClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height - 24);
    path.quadraticBezierTo(
      size.width / 2,
      size.height,
      size.width,
      size.height - 24,
    );
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
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
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.white.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppColors.white.withValues(alpha: 0.10),
            ),
          ),
          child: Icon(icon, color: AppColors.white, size: 18),
        ),
      ),
    );
  }
}
