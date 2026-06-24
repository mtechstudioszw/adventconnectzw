import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/hymn_model.dart';
import '../../services/cache_service.dart';
import '../../services/hymn_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';

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
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primaryBlue));
    }
    if (_all.isEmpty) {
      return _empty(context);
    }
    final base = _favOnly
        ? _shown.where((h) => HymnPrefs.favorites().contains(h.id)).toList()
        : _shown;
    return Column(
      children: [
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
              Text('${base.length} hymn(s)',
                  style: AppTextStyles.labelMedium
                      .copyWith(color: palette.textMuted)),
              const Spacer(),
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
                    color: _favOnly ? AppColors.primaryBlue : palette.text),
                side: BorderSide(color: palette.divider),
              ),
            ],
          ),
        ),
        Expanded(
          child: base.isEmpty
              ? Center(
                  child: Text(
                      _favOnly ? 'No favorites yet.' : 'No hymns match.',
                      style: AppTextStyles.bodyMedium
                          .copyWith(color: palette.textMuted)),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  itemCount: base.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) => _hymnTile(context, base[i]),
                ),
        ),
      ],
    );
  }

  Widget _hymnTile(BuildContext context, Hymn h) {
    final palette = context.palette;
    final fav = HymnPrefs.favorites().contains(h.id);
    return Material(
      color: palette.card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => _HymnReaderScreen(hymn: h),
        )),
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
                  child: Text('${h.number}',
                      style: AppTextStyles.labelMedium.copyWith(
                          color: AppColors.white, fontWeight: FontWeight.w800)),
                ),
              if (h.number != null) const SizedBox(width: 12),
              Expanded(
                child: Text(h.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.titleSmall
                        .copyWith(fontWeight: FontWeight.w600)),
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
          child: Text('Hymns will appear here once they\'re added.',
              textAlign: TextAlign.center,
              style:
                  AppTextStyles.bodyMedium.copyWith(color: palette.textMuted)),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
//  Hymn reader (lyrics + font size + favorite + share)
// ---------------------------------------------------------------------------

class _HymnReaderScreen extends StatefulWidget {
  const _HymnReaderScreen({required this.hymn});
  final Hymn hymn;

  @override
  State<_HymnReaderScreen> createState() => _HymnReaderScreenState();
}

class _HymnReaderScreenState extends State<_HymnReaderScreen> {
  double _scale = HymnPrefs.fontScale();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final h = widget.hymn;
    final fav = HymnPrefs.favorites().contains(h.id);
    return Scaffold(
      backgroundColor: palette.scaffoldBg,
      appBar: AppBar(
        title: Text(h.number != null ? 'Hymn ${h.number}' : 'Hymn',
            style: AppTextStyles.appBarTitle.copyWith(fontSize: 18)),
        foregroundColor: AppColors.white,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.appBarGradient),
        ),
        actions: [
          IconButton(
            icon: Icon(fav ? Icons.favorite : Icons.favorite_border),
            color: fav ? AppColors.red : AppColors.white,
            onPressed: () {
              HymnPrefs.toggleFavorite(h.id);
              setState(() {});
            },
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined),
            onPressed: () => Share.share(
                '${h.displayTitle}\n\n${h.lyrics}\n\nShared from Advent Connect ZW'),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(h.title,
                  style: AppTextStyles.headlineSmall.copyWith(
                      fontWeight: FontWeight.w800,
                      fontSize: 22 * _scale,
                      color: palette.text)),
              if (h.category != null && h.category!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(h.category!,
                    style: AppTextStyles.labelMedium
                        .copyWith(color: AppColors.primaryBlue)),
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
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('A', style: TextStyle(fontSize: 14)),
              Expanded(
                child: Slider(
                  value: _scale,
                  min: 0.8,
                  max: 1.8,
                  divisions: 10,
                  activeColor: AppColors.primaryBlue,
                  onChanged: (v) {
                    setState(() => _scale = v);
                    HymnPrefs.setFontScale(v);
                  },
                ),
              ),
              const Text('A', style: TextStyle(fontSize: 24)),
            ],
          ),
        ),
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
