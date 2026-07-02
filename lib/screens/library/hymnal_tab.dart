import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/hymn_model.dart';
import '../../services/cache_service.dart';
import '../../services/hymn_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/motion/branded_refresh_indicator.dart';
import '../../widgets/motion/brand_spinner.dart';

/// Library → Hymnal tab. Structured hymns searchable by number / title /
/// lyrics (modern hymnal style), with a favorites filter and an in-app
/// lyrics reader (font size + share). Content is upload-driven (`hymns`).
class HymnalTab extends StatefulWidget {
  const HymnalTab({super.key});

  @override
  State<HymnalTab> createState() => _HymnalTabState();
}

class _HymnalTabState extends State<HymnalTab>
    with AutomaticKeepAliveClientMixin {
  final _searchCtrl = TextEditingController();
  List<Hymn> _all = const [];
  List<Hymn> _shown = const [];
  bool _loading = true;
  bool _favOnly = false;
  String _collection = HymnCollection.kristuMunzwiyo.key;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
    HymnPrefs.revision.addListener(_onFav);
  }

  @override
  void dispose() {
    HymnPrefs.revision.removeListener(_onFav);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onFav() {
    if (mounted && _favOnly) setState(_applyFilter);
  }

  Future<void> _load() async {
    final hymns = await HymnService.all();
    if (!mounted) return;
    setState(() {
      _all = hymns;
      _shown = hymns;
      _loading = false;
    });
  }

  /// Pull-to-refresh: bust the cached hymn list and refetch, so hymns the admin
  /// just added (or removed) show up without restarting the app.
  Future<void> _refresh() async {
    HymnService.invalidate();
    final hymns = await HymnService.all();
    if (!mounted) return;
    setState(() {
      _all = hymns;
      _shown = hymns;
      _searchCtrl.clear();
    });
  }

  Future<void> _onQuery(String q) async {
    final results = await HymnService.search(q);
    if (!mounted) return;
    setState(() {
      _shown = results;
      _applyFilter();
    });
  }

  void _applyFilter() {
    if (_favOnly) {
      final favs = HymnPrefs.favorites();
      _shown = _shown.where((h) => favs.contains(h.id)).toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final palette = context.palette;
    if (_loading) {
      return const Center(child: BrandSpinner(size: 30));
    }
    if (_all.isEmpty) {
      return BrandedRefreshIndicator(
        color: AppColors.primaryBlue,
        onRefresh: _refresh,
        child: _empty(context),
      );
    }
    final base =
        (_favOnly
                ? _shown.where((h) => HymnPrefs.favorites().contains(h.id))
                : _shown)
            .where((h) => h.collection == _collection)
            .toList();
    return Column(
      children: [
        // Hymnal switcher: Kristu MuNzwiyo (Shona) ↔ SDA Hymnal (English).
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: palette.inputFill,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                for (final c in HymnCollection.all)
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() => _collection = c.key),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: _collection == c.key
                              ? AppColors.primaryBlue
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Column(
                          children: [
                            Text(
                              c.label,
                              style: AppTextStyles.labelMedium.copyWith(
                                color: _collection == c.key
                                    ? AppColors.white
                                    : palette.text,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              c.subtitle,
                              style: AppTextStyles.labelSmall.copyWith(
                                color: _collection == c.key
                                    ? AppColors.white.withValues(alpha: 0.85)
                                    : palette.textMuted,
                                fontSize: 10.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: TextField(
            controller: _searchCtrl,
            onChanged: _onQuery,
            textInputAction: TextInputAction.search,
            style: AppTextStyles.bodyMedium.copyWith(color: palette.text),
            decoration: InputDecoration(
              hintText: 'Search number, title or lyrics…',
              hintStyle: TextStyle(color: palette.textMuted),
              prefixIcon: Icon(Icons.search, color: palette.textMuted),
              suffixIcon: _searchCtrl.text.isEmpty
                  ? null
                  : IconButton(
                      icon: Icon(Icons.close, color: palette.textMuted),
                      onPressed: () {
                        _searchCtrl.clear();
                        _onQuery('');
                      },
                    ),
              filled: true,
              fillColor: palette.inputFill,
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: palette.divider),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: palette.divider),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text(
                '${base.length} hymn(s)',
                style: AppTextStyles.labelMedium.copyWith(
                  color: palette.textMuted,
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Refresh hymns',
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.refresh, color: palette.textMuted, size: 20),
                onPressed: _refresh,
              ),
              const SizedBox(width: 4),
              FilterChip(
                label: const Text('Favorites'),
                selected: _favOnly,
                onSelected: (v) => setState(() {
                  _favOnly = v;
                  _applyFilter();
                }),
                selectedColor: AppColors.primaryBlue.withValues(alpha: 0.15),
                checkmarkColor: AppColors.primaryBlue,
                backgroundColor: palette.card,
                labelStyle: AppTextStyles.labelMedium.copyWith(
                  color: _favOnly ? AppColors.primaryBlue : palette.text,
                ),
                side: BorderSide(color: palette.divider),
              ),
            ],
          ),
        ),
        Expanded(
          child: BrandedRefreshIndicator(
            color: AppColors.primaryBlue,
            onRefresh: _refresh,
            child: base.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      const SizedBox(height: 80),
                      Center(
                        child: Text(
                          _favOnly
                              ? 'No favorites yet.'
                              : _searchCtrl.text.trim().isEmpty
                              ? '${HymnCollection.fromKey(_collection).label} hymns will appear here once added.'
                              : 'No hymns match.',
                          textAlign: TextAlign.center,
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: palette.textMuted,
                          ),
                        ),
                      ),
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: base.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) => _hymnTile(context, base, i),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _hymnTile(BuildContext context, List<Hymn> hymns, int index) {
    final palette = context.palette;
    final h = hymns[index];
    final fav = HymnPrefs.favorites().contains(h.id);
    return Material(
      color: palette.card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                _HymnReaderScreen(hymns: hymns, initialIndex: index),
          ),
        ),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: palette.divider),
          ),
          child: Row(
            children: [
              if (h.number != null)
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${h.number}',
                    style: AppTextStyles.labelMedium.copyWith(
                      color: AppColors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              if (h.number != null) const SizedBox(width: 12),
              Expanded(
                child: Text(
                  h.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.titleSmall.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (fav)
                const Icon(Icons.favorite, color: AppColors.red, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Widget _empty(BuildContext context) {
    final palette = context.palette;
    return ListView(
      children: [
        const SizedBox(height: 100),
        Icon(Icons.queue_music_outlined, size: 60, color: palette.textMuted),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(
            'Hymns will appear here once they\'re added.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(color: palette.textMuted),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
//  Hymn reader (lyrics + font size + favorite + share)
// ---------------------------------------------------------------------------

class _HymnReaderScreen extends StatefulWidget {
  const _HymnReaderScreen({required this.hymns, required this.initialIndex});

  /// The list being browsed, so the reader can SWIPE between hymns.
  final List<Hymn> hymns;
  final int initialIndex;

  @override
  State<_HymnReaderScreen> createState() => _HymnReaderScreenState();
}

class _HymnReaderScreenState extends State<_HymnReaderScreen> {
  double _scale = HymnPrefs.fontScale();
  late final PageController _pageCtrl;
  late int _index;

  Hymn get _h => widget.hymns[_index];

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.hymns.length - 1);
    _pageCtrl = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  void _setScale(double v) {
    final clamped = v.clamp(0.8, 1.8);
    if (clamped == _scale) return;
    setState(() => _scale = clamped);
    HymnPrefs.setFontScale(clamped);
  }

  void _go(int delta) {
    final target = (_index + delta).clamp(0, widget.hymns.length - 1);
    if (target == _index) return;
    _pageCtrl.animateToPage(
      target,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final h = _h;
    final fav = HymnPrefs.favorites().contains(h.id);
    return Scaffold(
      backgroundColor: palette.scaffoldBg,
      appBar: AppBar(
        title: Text(
          h.number != null ? 'Hymn ${h.number}' : 'Hymn',
          style: AppTextStyles.appBarTitle.copyWith(fontSize: 18),
        ),
        foregroundColor: AppColors.white,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.appBarGradient),
        ),
        actions: [
          // Reliable A- / A+ text sizing (replaces the old bottom slider,
          // which felt fiddly). Persists via HymnPrefs.
          IconButton(
            tooltip: 'Smaller text',
            icon: const Icon(Icons.text_decrease),
            onPressed: _scale <= 0.8 ? null : () => _setScale(_scale - 0.1),
          ),
          IconButton(
            tooltip: 'Larger text',
            icon: const Icon(Icons.text_increase),
            onPressed: _scale >= 1.8 ? null : () => _setScale(_scale + 0.1),
          ),
          IconButton(
            tooltip: fav ? 'Remove favourite' : 'Add favourite',
            icon: Icon(fav ? Icons.favorite : Icons.favorite_border),
            color: fav ? AppColors.red : AppColors.white,
            onPressed: () {
              HymnPrefs.toggleFavorite(h.id);
              setState(() {});
            },
          ),
          IconButton(
            tooltip: 'Share',
            icon: const Icon(Icons.share_outlined),
            onPressed: () => Share.share(
              '${h.displayTitle}\n\n${h.lyrics}\n\nShared from Advent Connect ZW',
            ),
          ),
        ],
      ),
      // Swipe left/right to flip between hymns (like turning pages).
      body: SafeArea(
        top: false,
        child: PageView.builder(
          controller: _pageCtrl,
          itemCount: widget.hymns.length,
          onPageChanged: (i) => setState(() => _index = i),
          itemBuilder: (context, i) => _hymnPage(context, widget.hymns[i]),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: SizedBox(
          height: 50,
          child: Row(
            children: [
              Expanded(
                child: IconButton(
                  tooltip: 'Previous hymn',
                  color: AppColors.primaryBlue,
                  onPressed: _index <= 0 ? null : () => _go(-1),
                  icon: const Icon(Icons.chevron_left),
                ),
              ),
              Text(
                '${_index + 1} of ${widget.hymns.length}',
                style: AppTextStyles.labelMedium.copyWith(
                  color: palette.textMuted,
                ),
              ),
              Expanded(
                child: IconButton(
                  tooltip: 'Next hymn',
                  color: AppColors.primaryBlue,
                  onPressed: _index >= widget.hymns.length - 1
                      ? null
                      : () => _go(1),
                  icon: const Icon(Icons.chevron_right),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hymnPage(BuildContext context, Hymn h) {
    final palette = context.palette;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            h.title,
            style: AppTextStyles.headlineSmall.copyWith(
              fontWeight: FontWeight.w800,
              fontSize: 22 * _scale,
              color: palette.text,
            ),
          ),
          if (h.category != null && h.category!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              h.category!,
              style: AppTextStyles.labelMedium.copyWith(
                color: AppColors.primaryBlue,
              ),
            ),
          ],
          const SizedBox(height: 18),
          SelectableText(
            h.lyrics,
            style: AppTextStyles.bodyLarge.copyWith(
              color: palette.text,
              height: 1.8,
              fontSize: 17 * _scale,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
//  Local hymn prefs (favorites + font scale)
// ---------------------------------------------------------------------------

class HymnPrefs {
  HymnPrefs._();
  static const _kFavorites = 'hymn_favorites_v1';
  static const _kFontScale = 'hymn_font_scale_v1';
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static Set<String> favorites() {
    final raw = CacheService.readPref(_kFavorites);
    if (raw == null) return <String>{};
    try {
      return (jsonDecode(raw) as List).map((e) => e.toString()).toSet();
    } catch (_) {
      return <String>{};
    }
  }

  static Future<void> toggleFavorite(String id) async {
    final set = favorites();
    set.contains(id) ? set.remove(id) : set.add(id);
    await CacheService.writePref(_kFavorites, jsonEncode(set.toList()));
    revision.value++;
  }

  static double fontScale() =>
      double.tryParse(CacheService.readPref(_kFontScale) ?? '') ?? 1.0;

  static Future<void> setFontScale(double v) =>
      CacheService.writePref(_kFontScale, v.clamp(0.8, 1.8).toStringAsFixed(2));
}
