import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/hymn_model.dart';
import '../../services/cache_service.dart';
import '../../services/hymn_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/motion/branded_refresh_indicator.dart';
import '../../widgets/motion/brand_spinner.dart';
import '../../widgets/motion/pressable.dart';
import '../../widgets/motion/staggered_reveal.dart';

/// Library → Hymnal tab.
///
/// Reads the BUNDLED hymnal (see [HymnService]) so it is fully offline —
/// no spinner, no network error, no "couldn't load" message, ever. Pull to
/// refresh is the only path that touches the network, and it stays silent on
/// failure.
class HymnalTab extends StatefulWidget {
  const HymnalTab({super.key});

  @override
  State<HymnalTab> createState() => _HymnalTabState();
}

class _HymnalTabState extends State<HymnalTab>
    with AutomaticKeepAliveClientMixin {
  final _searchCtrl = TextEditingController();

  List<Hymn> _all = const [];
  bool _loading = true;
  bool _favOnly = false;
  String _query = '';
  String? _category;
  String _collection = HymnCollection.kristuMunzwiyo.key;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // Synchronous hit when another screen already warmed the asset.
    final cached = HymnService.cached();
    if (cached.isNotEmpty) {
      _all = cached;
      _loading = false;
    }
    _load();
    HymnPrefs.revision.addListener(_onPrefsChanged);
  }

  @override
  void dispose() {
    HymnPrefs.revision.removeListener(_onPrefsChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onPrefsChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final hymns = await HymnService.all();
    if (!mounted) return;
    setState(() {
      _all = hymns;
      _loading = false;
    });
  }

  /// Pull-to-refresh. Silent by design — the bundled hymns are already
  /// showing, so a failed network call must not produce a message.
  Future<void> _refresh() async {
    final changed = await HymnService.refresh();
    if (!mounted) return;
    setState(() => _all = HymnService.cached());
    if (changed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Hymnal updated.')),
      );
    }
  }

  /// Hymns in the active collection after category / favourites / search.
  List<Hymn> get _visible {
    var list = _all.where((h) => h.collection == _collection).toList();
    if (_category != null) {
      list = list.where((h) => h.category == _category).toList();
    }
    if (_favOnly) {
      final favs = HymnPrefs.favorites();
      list = list.where((h) => favs.contains(h.id)).toList();
    }
    return HymnService.searchIn(list, _query);
  }

  void _openReader(List<Hymn> list, int index) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HymnReaderScreen(hymns: list, initialIndex: index),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading && _all.isEmpty) {
      return const Center(child: BrandSpinner(size: 30));
    }

    final visible = _visible;
    final inCollection =
        _all.where((h) => h.collection == _collection).toList();
    final categories = HymnService.categoriesIn(inCollection);

    return Column(
      children: [
        _collectionSwitcher(context),
        _searchField(context),
        _toolRow(context, visible.length, categories),
        Expanded(
          child: BrandedRefreshIndicator(
            color: AppColors.primaryBlue,
            onRefresh: _refresh,
            child: visible.isEmpty
                ? _empty(context)
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: visible.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) => StaggeredReveal(
                      index: i,
                      child: _HymnTile(
                        hymn: visible[i],
                        onTap: () => _openReader(visible, i),
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  // ---- Collection switcher ------------------------------------------------

  Widget _collectionSwitcher(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: palette.inputFill,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: palette.divider),
        ),
        child: Row(
          children: [
            for (final c in HymnCollection.all)
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (_collection == c.key) return;
                    HapticFeedback.selectionClick();
                    setState(() {
                      _collection = c.key;
                      // A category from the other hymnal won't exist here.
                      _category = null;
                    });
                  },
                  child: AnimatedContainer(
                    duration: AppMotion.quick,
                    curve: AppMotion.ease,
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      gradient: _collection == c.key
                          ? AppColors.primaryGradient
                          : null,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: _collection == c.key
                          ? [
                              BoxShadow(
                                color: AppColors.primaryBlue
                                    .withValues(alpha: 0.28),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ]
                          : null,
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
    );
  }

  // ---- Search -------------------------------------------------------------

  Widget _searchField(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: TextField(
        controller: _searchCtrl,
        onChanged: (v) => setState(() => _query = v),
        textInputAction: TextInputAction.search,
        style: AppTextStyles.bodyMedium.copyWith(color: palette.text),
        decoration: InputDecoration(
          hintText: 'Type a number, title or line…',
          hintStyle: TextStyle(color: palette.textMuted),
          prefixIcon: Icon(Icons.search_rounded, color: palette.textMuted),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  icon: Icon(Icons.close_rounded, color: palette.textMuted),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _query = '');
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
    );
  }

  // ---- Tools --------------------------------------------------------------

  Widget _toolRow(
    BuildContext context,
    int count,
    List<String> categories,
  ) {
    final palette = context.palette;
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        children: [
          Center(
            child: Text(
              '$count',
              style: AppTextStyles.labelMedium.copyWith(
                color: palette.textMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          _toolChip(
            context,
            icon: Icons.favorite_rounded,
            label: 'Favourites',
            selected: _favOnly,
            onTap: () => setState(() => _favOnly = !_favOnly),
          ),
          if (categories.isNotEmpty) ...[
            const SizedBox(width: 8),
            for (final c in categories) ...[
              _toolChip(
                context,
                label: c,
                selected: _category == c,
                onTap: () => setState(
                  () => _category = _category == c ? null : c,
                ),
              ),
              const SizedBox(width: 8),
            ],
          ],
        ],
      ),
    );
  }

  Widget _toolChip(
    BuildContext context, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
    IconData? icon,
  }) {
    final palette = context.palette;
    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppMotion.quick,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryBlue : palette.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.primaryBlue : palette.divider,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 14,
                color: selected ? AppColors.white : palette.textMuted,
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: AppTextStyles.labelMedium.copyWith(
                color: selected ? AppColors.white : palette.text,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- Empty --------------------------------------------------------------

  Widget _empty(BuildContext context) {
    final palette = context.palette;
    final message = _favOnly
        ? 'No favourites in this hymnal yet.\nTap the heart while reading a hymn.'
        : _query.trim().isNotEmpty
            ? 'No hymn matches "$_query".'
            : _category != null
                ? 'No hymns in this category.'
                : '${HymnCollection.fromKey(_collection).label} hymns will '
                    'appear here once added.';
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 80),
        Icon(
          _favOnly ? Icons.favorite_border_rounded : Icons.search_off_rounded,
          size: 56,
          color: palette.textMuted,
        ),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(
              color: palette.textMuted,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
//  List tile
// ---------------------------------------------------------------------------

class _HymnTile extends StatelessWidget {
  const _HymnTile({required this.hymn, required this.onTap});

  final Hymn hymn;
  final VoidCallback onTap;

  /// First non-empty, non-marker line — a preview that tells the singer which
  /// hymn this is faster than the title alone.
  String get _firstLine {
    for (final raw in hymn.lyrics.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (RegExp(r'^\d+$').hasMatch(line)) continue;
      if (line.toUpperCase().startsWith('CHORUS')) continue;
      return line;
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final fav = HymnPrefs.favorites().contains(hymn.id);
    return PressEffect(
      child: Material(
        color: palette.card,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: palette.divider),
            ),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    hymn.number?.toString() ?? '♪',
                    style: AppTextStyles.titleSmall.copyWith(
                      color: AppColors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hymn.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.titleSmall.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (_firstLine.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          _firstLine,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: palette.textMuted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (fav)
                  const Padding(
                    padding: EdgeInsets.only(left: 6),
                    child: Icon(Icons.favorite_rounded,
                        color: AppColors.red, size: 17),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
//  Lyrics model — turns a raw lyrics blob into verses + choruses.
// ---------------------------------------------------------------------------

/// One block of a hymn: a numbered verse, or the chorus/refrain.
class HymnStanza {
  const HymnStanza({
    required this.lines,
    required this.isChorus,
    this.number,
  });

  final List<String> lines;
  final bool isChorus;
  final int? number;
}

/// Parses the free-text `lyrics` column into structured stanzas.
///
/// The uploaded hymns use two conventions, both handled here:
///  * a bare number on its own line starts a numbered verse ("1", "2", …);
///  * a line starting with CHORUS / REFRAIN marks the refrain.
///
/// Blank lines separate blocks. Anything unrecognised becomes an unnumbered
/// verse, so a hymn entered without markers still renders sensibly.
List<HymnStanza> parseStanzas(String lyrics) {
  final blocks = lyrics
      .replaceAll('\r\n', '\n')
      .split(RegExp(r'\n\s*\n'))
      .map((b) => b.trim())
      .where((b) => b.isNotEmpty)
      .toList();

  final out = <HymnStanza>[];
  var autoNumber = 0;

  for (final block in blocks) {
    final lines = block.split('\n').map((l) => l.trim()).toList();
    var isChorus = false;
    int? number;

    // Leading marker line, e.g. "1" or "CHORUS:" — consumed, not displayed.
    if (lines.isNotEmpty) {
      final first = lines.first;
      final upper = first.toUpperCase();
      if (RegExp(r'^\d+\.?$').hasMatch(first)) {
        number = int.tryParse(first.replaceAll('.', ''));
        lines.removeAt(0);
      } else if (upper.startsWith('CHORUS') || upper.startsWith('REFRAIN')) {
        isChorus = true;
        // "CHORUS:" alone is a marker; "CHORUS: Sing on" keeps its text.
        final rest = first.replaceFirst(RegExp(r'^(CHORUS|REFRAIN):?\s*',
            caseSensitive: false), '');
        if (rest.isEmpty) {
          lines.removeAt(0);
        } else {
          lines[0] = rest;
        }
      }
    }

    final body = lines.where((l) => l.isNotEmpty).toList();
    if (body.isEmpty) continue;

    if (!isChorus && number == null) number = ++autoNumber;
    if (number != null) autoNumber = number;

    out.add(HymnStanza(lines: body, isChorus: isChorus, number: number));
  }

  // A hymn with no blank-line structure at all — treat the whole thing as one
  // block rather than showing nothing.
  if (out.isEmpty && lyrics.trim().isNotEmpty) {
    return [
      HymnStanza(
        lines: lyrics.trim().split('\n').map((l) => l.trim()).toList(),
        isChorus: false,
        number: 1,
      ),
    ];
  }
  return out;
}

// ---------------------------------------------------------------------------
//  Reader
// ---------------------------------------------------------------------------

/// Full-screen hymn reader: swipe between hymns, structured verses, adjustable
/// text size, a distraction-free sepia/night mode, favourite and share.
class HymnReaderScreen extends StatefulWidget {
  const HymnReaderScreen({
    super.key,
    required this.hymns,
    required this.initialIndex,
  });

  final List<Hymn> hymns;
  final int initialIndex;

  @override
  State<HymnReaderScreen> createState() => _HymnReaderScreenState();
}

class _HymnReaderScreenState extends State<HymnReaderScreen> {
  late final PageController _pageCtrl;
  late int _index;
  double _scale = HymnPrefs.fontScale();
  bool _focusMode = HymnPrefs.focusMode();

  Hymn get _h => widget.hymns[_index];

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.hymns.length - 1);
    _pageCtrl = PageController(initialPage: _index);
    HymnPrefs.noteViewed(widget.hymns[_index].id);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  void _setScale(double v) {
    final clamped = v.clamp(0.8, 2.0);
    if (clamped == _scale) return;
    setState(() => _scale = clamped);
    HymnPrefs.setFontScale(clamped);
  }

  void _go(int delta) {
    final target = (_index + delta).clamp(0, widget.hymns.length - 1);
    if (target == _index) return;
    _pageCtrl.animateToPage(
      target,
      duration: AppMotion.standard,
      curve: AppMotion.ease,
    );
  }

  /// Focus mode = warm paper background + no chrome, for singing from the
  /// phone in a dim church.
  Color get _bg => _focusMode
      ? const Color(0xFF14110C)
      : context.palette.scaffoldBg;

  Color get _fg =>
      _focusMode ? const Color(0xFFF2E7D0) : context.palette.text;

  @override
  Widget build(BuildContext context) {
    final h = _h;
    final fav = HymnPrefs.favorites().contains(h.id);
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _focusMode ? const Color(0xFF14110C) : null,
        foregroundColor: _focusMode ? const Color(0xFFF2E7D0) : null,
        title: Text(
          h.number != null ? 'Hymn ${h.number}' : 'Hymn',
          style: AppTextStyles.appBarTitleFlat.copyWith(fontSize: 18),
        ),
        actions: [
          IconButton(
            tooltip: _focusMode ? 'Normal mode' : 'Focus mode',
            icon: Icon(_focusMode
                ? Icons.light_mode_outlined
                : Icons.dark_mode_outlined),
            onPressed: () {
              setState(() => _focusMode = !_focusMode);
              HymnPrefs.setFocusMode(_focusMode);
            },
          ),
          IconButton(
            tooltip: 'Text size',
            icon: const Icon(Icons.format_size_rounded),
            onPressed: _openTextSheet,
          ),
          IconButton(
            tooltip: fav ? 'Remove favourite' : 'Add favourite',
            icon: Icon(fav
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded),
            color: fav ? AppColors.red : null,
            onPressed: () {
              HapticFeedback.lightImpact();
              HymnPrefs.toggleFavorite(h.id);
              setState(() {});
            },
          ),
          IconButton(
            tooltip: 'Share',
            icon: const Icon(Icons.ios_share_rounded),
            onPressed: () => Share.share(
              '${h.displayTitle}\n\n${h.lyrics}\n\n'
              'Shared from Advent Connect ZW',
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: PageView.builder(
          controller: _pageCtrl,
          itemCount: widget.hymns.length,
          onPageChanged: (i) {
            setState(() => _index = i);
            HymnPrefs.noteViewed(widget.hymns[i].id);
          },
          itemBuilder: (context, i) => _page(context, widget.hymns[i]),
        ),
      ),
      bottomNavigationBar: _bottomBar(context),
    );
  }

  Widget _page(BuildContext context, Hymn h) {
    final stanzas = parseStanzas(h.lyrics);
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 30),
      children: [
        Text(
          h.title,
          style: AppTextStyles.headlineSmall.copyWith(
            fontWeight: FontWeight.w800,
            fontSize: 23 * _scale,
            color: _fg,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            if (h.number != null)
              _metaPill('#${h.number}', AppColors.primaryBlue),
            if (h.category != null && h.category!.trim().isNotEmpty) ...[
              const SizedBox(width: 6),
              _metaPill(h.category!.trim(), AppColors.goldAccent),
            ],
            const SizedBox(width: 6),
            _metaPill(h.language, AppColors.successGreen),
          ],
        ),
        const SizedBox(height: 20),
        for (final stanza in stanzas) ...[
          _stanza(stanza),
          const SizedBox(height: 18),
        ],
      ],
    );
  }

  Widget _metaPill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: _focusMode ? 0.22 : 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: AppTextStyles.labelSmall.copyWith(
          color: _focusMode ? const Color(0xFFF2E7D0) : color,
          fontWeight: FontWeight.w700,
          fontSize: 10.5,
        ),
      ),
    );
  }

  /// A verse or chorus block. The chorus gets a gold rule + italics so a
  /// singer can find it at a glance mid-song.
  Widget _stanza(HymnStanza stanza) {
    final body = SelectableText(
      stanza.lines.join('\n'),
      style: AppTextStyles.bodyLarge.copyWith(
        color: _fg,
        height: 1.85,
        fontSize: 17 * _scale,
        fontStyle: stanza.isChorus ? FontStyle.italic : FontStyle.normal,
        fontWeight: stanza.isChorus ? FontWeight.w600 : FontWeight.w400,
      ),
    );

    if (stanza.isChorus) {
      return Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: AppColors.goldAccent, width: 3),
          ),
          color: AppColors.goldAccent.withValues(alpha: 0.07),
          borderRadius: const BorderRadius.horizontal(
            right: Radius.circular(10),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'CHORUS',
              style: AppTextStyles.overline.copyWith(
                color: AppColors.goldAccent,
                fontSize: 10,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            body,
          ],
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (stanza.number != null)
          Padding(
            padding: const EdgeInsets.only(right: 12, top: 4),
            child: Text(
              '${stanza.number}',
              style: AppTextStyles.titleMedium.copyWith(
                color: AppColors.primaryBlue,
                fontWeight: FontWeight.w800,
                fontSize: 18 * _scale,
              ),
            ),
          ),
        Expanded(child: body),
      ],
    );
  }

  Widget _bottomBar(BuildContext context) {
    final palette = context.palette;
    return SafeArea(
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: _focusMode ? const Color(0xFF14110C) : palette.card,
          border: Border(top: BorderSide(color: palette.divider)),
        ),
        child: Row(
          children: [
            Expanded(
              child: IconButton(
                tooltip: 'Previous hymn',
                color: AppColors.primaryBlue,
                onPressed: _index <= 0 ? null : () => _go(-1),
                icon: const Icon(Icons.chevron_left_rounded, size: 28),
              ),
            ),
            Text(
              '${_index + 1} of ${widget.hymns.length}',
              style: AppTextStyles.labelMedium.copyWith(
                color: _focusMode
                    ? const Color(0xFFF2E7D0).withValues(alpha: 0.7)
                    : palette.textMuted,
              ),
            ),
            Expanded(
              child: IconButton(
                tooltip: 'Next hymn',
                color: AppColors.primaryBlue,
                onPressed: _index >= widget.hymns.length - 1
                    ? null
                    : () => _go(1),
                icon: const Icon(Icons.chevron_right_rounded, size: 28),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openTextSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.palette.sheet,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Text size',
                  style: AppTextStyles.titleSmall
                      .copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('A', style: TextStyle(fontSize: 13)),
                    Expanded(
                      child: Slider(
                        value: _scale,
                        min: 0.8,
                        max: 2.0,
                        divisions: 12,
                        activeColor: AppColors.primaryBlue,
                        label: '${(_scale * 100).round()}%',
                        onChanged: (v) {
                          setSheet(() {});
                          _setScale(v);
                        },
                      ),
                    ),
                    const Text('A', style: TextStyle(fontSize: 24)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
//  Local hymn prefs (favourites, font scale, focus mode, recently viewed)
// ---------------------------------------------------------------------------

class HymnPrefs {
  HymnPrefs._();
  static const _kFavorites = 'hymn_favorites_v1';
  static const _kFontScale = 'hymn_font_scale_v1';
  static const _kFocusMode = 'hymn_focus_mode_v1';
  static const _kRecent = 'hymn_recent_v1';

  static const _recentCap = 20;

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
      CacheService.writePref(_kFontScale, v.clamp(0.8, 2.0).toStringAsFixed(2));

  static bool focusMode() => CacheService.readPref(_kFocusMode) == '1';

  static Future<void> setFocusMode(bool on) =>
      CacheService.writePref(_kFocusMode, on ? '1' : '0');

  static List<String> recentIds() {
    final raw = CacheService.readPref(_kRecent);
    if (raw == null) return const [];
    try {
      return (jsonDecode(raw) as List).map((e) => e.toString()).toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> noteViewed(String id) async {
    final list = recentIds().toList()..remove(id);
    list.insert(0, id);
    if (list.length > _recentCap) list.removeRange(_recentCap, list.length);
    await CacheService.writePref(_kRecent, jsonEncode(list));
  }
}
