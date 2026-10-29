import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/fundamental_beliefs.dart';
import '../../models/hymn_model.dart';
import '../../models/library_item_model.dart';
import '../../services/bible_service.dart';
import '../../services/hymn_service.dart';
import '../../services/library_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/screen_shell.dart';
import 'beliefs_screen.dart';
import 'library_open.dart';

/// What a Library search result is.
enum LibraryHitKind { reference, verse, hymn, egw, belief }

/// Search across the Library only — Bible, hymns, EGW books and the 28
/// Beliefs. Never posts, people or listings: the master prompt keeps
/// spiritual resources apart from social search (Home's search is the
/// global one).
///
/// Everything but the EGW titles is bundled, so it works offline; the EGW
/// list comes from the same cache the shelf uses.
class LibrarySearchScreen extends StatefulWidget {
  const LibrarySearchScreen({super.key, this.autoLoad = true});

  /// False in widget tests: no EGW fetch.
  final bool autoLoad;

  /// The belief matcher, without the screen.
  static List<FundamentalBelief> matchBeliefs(String query) {
    final terms = query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    if (terms.isEmpty) return const [];
    final asNumber = int.tryParse(query.trim());
    return kFundamentalBeliefs.where((b) {
      if (asNumber != null) return b.number == asNumber;
      final hay = '${b.title} ${b.summary}'.toLowerCase();
      return terms.every(hay.contains);
    }).toList();
  }

  @override
  State<LibrarySearchScreen> createState() => _LibrarySearchScreenState();
}

class _LibrarySearchScreenState extends State<LibrarySearchScreen> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  LibraryHitKind? _filter;
  bool _busy = false;
  int _seq = 0;

  BibleReference? _reference;
  List<BibleSearchHit> _verses = const [];
  List<Hymn> _hymns = const [];
  List<LibraryItem> _egw = const [];
  List<FundamentalBelief> _beliefs = const [];
  List<LibraryItem> _egwAll = const [];

  @override
  void initState() {
    super.initState();
    if (widget.autoLoad) {
      LibraryService.fetchItems('egw_book').then((items) {
        if (mounted) _egwAll = items;
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _run);
  }

  Future<void> _run() async {
    final q = _ctrl.text.trim();
    final seq = ++_seq;
    if (q.length < 2) {
      setState(() {
        _reference = null;
        _verses = const [];
        _hymns = const [];
        _egw = const [];
        _beliefs = const [];
        _busy = false;
      });
      return;
    }
    setState(() => _busy = true);
    final lower = q.toLowerCase();
    final results = await Future.wait<Object?>([
      BibleService.resolveReference(q),
      // Verse text only for words, not for "John 3".
      RegExp(r'\d').hasMatch(q)
          ? Future.value(const <BibleSearchHit>[])
          : BibleService.search(q, limit: 40),
      HymnService.search(q),
    ]);
    if (!mounted || seq != _seq) return;
    setState(() {
      _busy = false;
      _reference = results[0] as BibleReference?;
      _verses = results[1] as List<BibleSearchHit>;
      _hymns = (results[2] as List<Hymn>).take(30).toList();
      _egw = _egwAll
          .where(
            (i) => '${i.title} ${i.author ?? ''}'.toLowerCase().contains(lower),
          )
          .toList();
      _beliefs = LibrarySearchScreen.matchBeliefs(q);
    });
  }

  int _count(LibraryHitKind kind) => switch (kind) {
    LibraryHitKind.reference => _reference == null ? 0 : 1,
    LibraryHitKind.verse => _verses.length,
    LibraryHitKind.hymn => _hymns.length,
    LibraryHitKind.egw => _egw.length,
    LibraryHitKind.belief => _beliefs.length,
  };

  bool _show(LibraryHitKind kind) =>
      _count(kind) > 0 &&
      (_filter == null ||
          _filter == kind ||
          // "Bible" covers a reference and verse text.
          (_filter == LibraryHitKind.verse &&
              kind == LibraryHitKind.reference));

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final q = _ctrl.text.trim();
    final total = LibraryHitKind.values.fold<int>(0, (n, k) => n + _count(k));

    final rows = <Widget>[];
    void section(String title, List<Widget> tiles) {
      rows.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.lg,
            AppSpace.lg,
            AppSpace.lg,
            AppSpace.xs,
          ),
          child: Text(
            title,
            style: AppTextStyles.overline.copyWith(
              color: palette.textMuted,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
      rows.addAll(tiles);
    }

    if (_show(LibraryHitKind.reference)) {
      final r = _reference!;
      final label =
          '${r.book.name} ${r.chapter}${r.verse == null ? '' : ':${r.verse}'}';
      section('GO TO', [
        _Hit(
          icon: Icons.menu_book_rounded,
          title: label,
          subtitle: 'Open in the Bible',
          onTap: () => LibraryOpen.verse(
            context,
            r.book,
            r.chapter - 1,
            verse: r.verse == null ? null : r.verse! - 1,
          ),
        ),
      ]);
    }
    if (_show(LibraryHitKind.belief)) {
      section('28 BELIEFS', [
        for (final b in _beliefs)
          _Hit(
            icon: Icons.history_edu_rounded,
            title: '${b.number}. ${b.title}',
            subtitle: b.group,
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => BeliefDetailScreen(belief: b),
              ),
            ),
          ),
      ]);
    }
    if (_show(LibraryHitKind.hymn)) {
      section('HYMNS', [
        for (final h in _hymns)
          _Hit(
            icon: Icons.queue_music_rounded,
            title: h.title,
            // The book as well as the number: each hymnal numbers its own.
            subtitle: h.category == null
                ? h.reference
                : '${h.reference} · ${h.category}',
            onTap: () => LibraryOpen.hymn(context, h),
          ),
      ]);
    }
    if (_show(LibraryHitKind.egw)) {
      section('ELLEN G. WHITE BOOKS', [
        for (final b in _egw)
          _Hit(
            icon: Icons.auto_stories_rounded,
            title: b.title,
            subtitle: b.author ?? 'Ellen G. White',
            onTap: () => LibraryOpen.egwBook(context, b.id),
          ),
      ]);
    }
    if (_show(LibraryHitKind.verse)) {
      section(
        _verses.length >= 40 ? 'BIBLE VERSES (FIRST 40)' : 'BIBLE VERSES',
        [
          for (final v in _verses)
            _Hit(
              icon: Icons.format_quote_rounded,
              title: v.reference,
              subtitle: v.text,
              maxSubtitleLines: 2,
              onTap: () =>
                  LibraryOpen.verse(context, v.book, v.chapter, verse: v.verse),
            ),
        ],
      );
    }

    return FlatStatusBar(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          titleSpacing: 0,
          title: TextField(
            controller: _ctrl,
            autofocus: widget.autoLoad,
            onChanged: _onChanged,
            textInputAction: TextInputAction.search,
            style: AppTextStyles.bodyMedium.copyWith(color: palette.text),
            decoration: InputDecoration(
              hintText: 'Verses, John 3:16, hymns, books, beliefs',
              hintStyle: AppTextStyles.bodyMedium.copyWith(
                color: palette.textMuted,
              ),
              filled: true,
              fillColor: palette.inputFill,
              isDense: true,
              prefixIcon: Icon(Icons.search_rounded, color: palette.textMuted),
              suffixIcon: q.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        _ctrl.clear();
                        _run();
                      },
                    ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.button),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          actions: const [SizedBox(width: AppSpace.lg)],
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
                  children: [
                    for (final (label, kind) in const [
                      ('All', null),
                      ('Bible', LibraryHitKind.verse),
                      ('Hymns', LibraryHitKind.hymn),
                      ('EGW', LibraryHitKind.egw),
                      ('Beliefs', LibraryHitKind.belief),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: AppSpace.sm),
                        child: ChoiceChip(
                          label: Text(label),
                          selected: _filter == kind,
                          onSelected: (_) => setState(() => _filter = kind),
                          selectedColor: AppColors.primaryBlue,
                          backgroundColor: palette.card,
                          side: BorderSide(
                            color: _filter == kind
                                ? AppColors.primaryBlue
                                : palette.divider,
                          ),
                          showCheckmark: false,
                          labelStyle: AppTextStyles.labelMedium.copyWith(
                            color: _filter == kind
                                ? AppColors.white
                                : palette.text,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (_busy) const LinearProgressIndicator(minHeight: 2),
              Expanded(
                child: q.length < 2
                    ? _Hint(
                        text:
                            'Search the Bible (words or a reference), the '
                            'hymnal by number or line, Ellen G. White books '
                            'and the 28 Fundamental Beliefs.',
                      )
                    : (!_busy && total == 0)
                    ? _Hint(text: 'Nothing in the Library matches "$q".')
                    : ListView(
                        padding: const EdgeInsets.only(bottom: AppSpace.xxl),
                        children: rows,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpace.xl),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: AppTextStyles.bodyMedium.copyWith(
          color: context.palette.textMuted,
        ),
      ),
    );
  }
}

class _Hit extends StatelessWidget {
  const _Hit({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.maxSubtitleLines = 1,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final int maxSubtitleLines;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.primaryBlue.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Icon(icon, color: palette.brandBlue, size: 20),
      ),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTextStyles.labelLarge.copyWith(
          color: palette.text,
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Text(
        subtitle,
        maxLines: maxSubtitleLines,
        overflow: TextOverflow.ellipsis,
        style: AppTextStyles.caption.copyWith(color: palette.textMuted),
      ),
    );
  }
}
