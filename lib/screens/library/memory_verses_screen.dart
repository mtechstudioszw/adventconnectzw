import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../../services/bible_service.dart';
import '../../services/memory_verse_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/screen_shell.dart';

AppBar _flatBar(String title) => AppBar(
  backgroundColor: Colors.transparent,
  elevation: 0,
  scrolledUnderElevation: 0,
  title: Text(
    title,
    style: AppTextStyles.appBarTitleFlat.copyWith(fontSize: 19),
  ),
);

/// Verses the member is learning, with practice and starter suggestions.
/// Add more from the Bible reader: select verses → Memorise.
class MemoryVersesScreen extends StatefulWidget {
  const MemoryVersesScreen({super.key});

  @override
  State<MemoryVersesScreen> createState() => _MemoryVersesScreenState();
}

class _MemoryVersesScreenState extends State<MemoryVersesScreen> {
  List<BibleBook> _books = const [];

  /// (reference, MemoryVerse.id) for each starter that resolves.
  List<(String, String)> _starters = const [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final books = await BibleService.books();
    final starters = <(String, String)>[];
    for (final ref in MemoryVerseService.starters) {
      final r = await BibleService.resolveReference(ref);
      if (r == null || r.verse == null) continue;
      final v = r.verse! - 1;
      starters.add((ref, '${r.book.index}:${r.chapter - 1}:$v-$v'));
    }
    if (mounted) {
      setState(() {
        _books = books;
        _starters = starters;
      });
    }
  }

  Future<void> _addStarter(String ref) async {
    final r = await BibleService.resolveReference(ref);
    if (r == null || r.verse == null) return;
    HapticFeedback.selectionClick();
    MemoryVerseService.add(
      book: r.book.index,
      chapter: r.chapter - 1,
      from: r.verse! - 1,
    );
  }

  void _practise() => Navigator.of(context).push<void>(
    MaterialPageRoute<void>(builder: (_) => const MemoryPracticeScreen()),
  );

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return FlatStatusBar(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: _flatBar('Memory verses'),
        body: SafeArea(
          top: false,
          child: _books.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : ValueListenableBuilder<int>(
                  valueListenable: MemoryVerseService.revision,
                  builder: (context, _, _) {
                    final all = MemoryVerseService.all()
                      ..sort((a, b) => a.due.compareTo(b.due));
                    final due = MemoryVerseService.due();
                    final ids = all.map((v) => v.id).toSet();
                    // Only suggest what isn't already on the list.
                    final starters = [
                      for (final st in _starters)
                        if (!ids.contains(st.$2)) st,
                    ];
                    return ListView(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpace.lg,
                        AppSpace.sm,
                        AppSpace.lg,
                        AppSpace.xxl,
                      ),
                      children: [
                        if (all.isNotEmpty)
                          PrimaryGradientButton(
                            label: due.isEmpty
                                ? 'Nothing due — practise anyway'
                                : 'Practise ${due.length} verse${due.length == 1 ? '' : 's'}',
                            icon: Icons.psychology_alt_rounded,
                            onTap: _practise,
                          )
                        else
                          Text(
                            'Learn Scripture by heart. Each time you practise, '
                            'more words are hidden, and a verse comes back '
                            'less often as you learn it. Start with one below, '
                            'or select verses in the Bible and tap Memorise.',
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: palette.textMuted,
                            ),
                          ),
                        if (all.isNotEmpty) ...[
                          _label(context, 'YOUR VERSES · ${all.length}'),
                          for (final v in all)
                            _VerseRow(
                              verse: v,
                              reference: MemoryVerseService.reference(
                                v,
                                _books,
                              ),
                            ),
                        ],
                        if (starters.isNotEmpty) ...[
                          _label(
                            context,
                            all.isEmpty
                                ? 'START WITH ONE OF THESE'
                                : 'SUGGESTED',
                          ),
                          Wrap(
                            spacing: AppSpace.sm,
                            runSpacing: AppSpace.sm,
                            children: [
                              for (final (ref, _) in starters)
                                ActionChip(
                                  avatar: Icon(
                                    Icons.add_rounded,
                                    size: 16,
                                    color: palette.brandBlue,
                                  ),
                                  label: Text(ref),
                                  backgroundColor: palette.card,
                                  side: BorderSide(color: palette.divider),
                                  onPressed: () => _addStarter(ref),
                                ),
                            ],
                          ),
                        ],
                        if (ids.isNotEmpty) ...[
                          const SizedBox(height: AppSpace.lg),
                          Text(
                            'Saved on this phone. Signing out clears it.',
                            style: AppTextStyles.caption.copyWith(
                              color: palette.textMuted,
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
        ),
      ),
    );
  }

  static Widget _label(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(top: AppSpace.xl, bottom: AppSpace.sm),
    child: Text(
      text,
      style: AppTextStyles.overline.copyWith(
        color: context.palette.textMuted,
        letterSpacing: 1.2,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _VerseRow extends StatelessWidget {
  const _VerseRow({required this.verse, required this.reference});
  final MemoryVerse verse;
  final String reference;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final known = verse.level >= MemoryVerseService.maxLevel;
    final dueNow = !verse.due.isAfter(DateTime.now());
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Container(
        decoration: BoxDecoration(
          color: palette.card,
          borderRadius: BorderRadius.circular(AppRadius.card),
          boxShadow: AppShadows.card(context),
        ),
        child: ListTile(
          title: Text(
            reference,
            style: AppTextStyles.labelLarge.copyWith(
              color: palette.text,
              fontWeight: FontWeight.w700,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                for (var i = 1; i <= MemoryVerseService.maxLevel; i++)
                  Container(
                    width: 14,
                    height: 6,
                    margin: const EdgeInsets.only(right: 3),
                    decoration: BoxDecoration(
                      color: i <= verse.level
                          ? AppColors.primaryBlue
                          : palette.cardMuted,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                const SizedBox(width: AppSpace.sm),
                Flexible(
                  child: Text(
                    known
                        ? 'Known'
                        : dueNow
                        ? 'Due now'
                        : 'Next: ${_when(verse.due)}',
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption.copyWith(
                      color: palette.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
          trailing: IconButton(
            tooltip: 'Remove',
            icon: Icon(Icons.delete_outline_rounded, color: palette.textMuted),
            onPressed: () {
              MemoryVerseService.remove(verse.id);
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('Removed $reference.')));
            },
          ),
        ),
      ),
    );
  }

  static String _when(DateTime d) {
    final today = DateTime.now();
    final days = DateTime(
      d.year,
      d.month,
      d.day,
    ).difference(DateTime(today.year, today.month, today.day)).inDays;
    if (days <= 1) return 'tomorrow';
    if (days < 7) return 'in $days days';
    final weeks = (days / 7).round();
    return weeks == 1 ? 'in a week' : 'in $weeks weeks';
  }
}

/// Practice: the verse with words hidden for its level. Say it, reveal,
/// then "Again" or "Got it".
class MemoryPracticeScreen extends StatefulWidget {
  const MemoryPracticeScreen({super.key});

  @override
  State<MemoryPracticeScreen> createState() => _MemoryPracticeScreenState();
}

class _MemoryPracticeScreenState extends State<MemoryPracticeScreen> {
  late final List<MemoryVerse> _queue;
  List<BibleBook> _books = const [];
  int _index = 0;
  bool _revealed = false;
  ({String text, String translation})? _text;
  int _gotIt = 0;

  @override
  void initState() {
    super.initState();
    final due = MemoryVerseService.due();
    _queue = due.isNotEmpty
        ? due
        : (MemoryVerseService.all()..sort((a, b) => a.due.compareTo(b.due)));
    BibleService.books().then((b) {
      if (!mounted) return;
      _books = b;
      _loadText();
    });
  }

  Future<void> _loadText() async {
    if (_index >= _queue.length) return;
    setState(() => _text = null);
    final t = await MemoryVerseService.text(_queue[_index], _books);
    if (mounted) setState(() => _text = t);
  }

  void _answer(bool gotIt) {
    HapticFeedback.selectionClick();
    MemoryVerseService.review(_queue[_index].id, gotIt: gotIt);
    if (gotIt) _gotIt++;
    setState(() {
      _index++;
      _revealed = false;
    });
    _loadText();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final done = _index >= _queue.length;
    return FlatStatusBar(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: _flatBar(
          done ? 'Practice done' : 'Verse ${_index + 1} of ${_queue.length}',
        ),
        body: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.lg,
              AppSpace.sm,
              AppSpace.lg,
              AppSpace.lg,
            ),
            child: done
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.emoji_events_rounded,
                          size: 56,
                          color: AppColors.goldAccent,
                        ),
                        const SizedBox(height: AppSpace.md),
                        Text(
                          _queue.isEmpty
                              ? 'No verses yet.'
                              : 'You knew $_gotIt of ${_queue.length}.',
                          style: AppTextStyles.titleMedium.copyWith(
                            color: palette.text,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: AppSpace.lg),
                        PrimaryGradientButton(
                          label: 'Back to my verses',
                          onTap: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  )
                : _card(context, palette),
          ),
        ),
      ),
    );
  }

  Widget _card(BuildContext context, AppPalette palette) {
    final v = _queue[_index];
    final t = _text;
    final words = t?.text.split(RegExp(r'\s+')) ?? const <String>[];
    final hidden = _revealed
        ? const <int>{}
        : MemoryVerseService.hiddenWords(v.id, words.length, v.level);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _books.isEmpty ? '' : MemoryVerseService.reference(v, _books),
          style: AppTextStyles.headlineSmall.copyWith(
            color: palette.text,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (t != null)
          Text(
            t.translation,
            style: AppTextStyles.caption.copyWith(color: palette.textMuted),
          ),
        const SizedBox(height: AppSpace.lg),
        Expanded(
          child: SingleChildScrollView(
            child: Container(
              padding: const EdgeInsets.all(AppSpace.lg),
              decoration: BoxDecoration(
                color: palette.card,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                boxShadow: AppShadows.card(context),
              ),
              child: t == null
                  ? const Center(child: CircularProgressIndicator())
                  : Wrap(
                      spacing: 6,
                      runSpacing: 10,
                      children: [
                        for (var i = 0; i < words.length; i++)
                          hidden.contains(i)
                              ? Container(
                                  // Width follows the word, so the blank
                                  // hints at its length.
                                  width: 10.0 * words[i].length.clamp(2, 9),
                                  height: 22,
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryBlue.withValues(
                                      alpha: 0.14,
                                    ),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                )
                              : Text(
                                  words[i],
                                  style: AppTextStyles.bodyLarge.copyWith(
                                    color: palette.text,
                                    height: 1.4,
                                  ),
                                ),
                      ],
                    ),
            ),
          ),
        ),
        const SizedBox(height: AppSpace.lg),
        if (!_revealed)
          PrimaryGradientButton(
            label: hidden.isEmpty ? 'I read it' : 'Show the verse',
            icon: Icons.visibility_rounded,
            onTap: t == null ? null : () => setState(() => _revealed = true),
          )
        else
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _answer(false),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    foregroundColor: palette.text,
                    side: BorderSide(color: palette.divider),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.button),
                    ),
                  ),
                  child: const Text('Again'),
                ),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: PrimaryGradientButton(
                  label: 'Got it',
                  icon: Icons.check_rounded,
                  onTap: () => _answer(true),
                ),
              ),
            ],
          ),
      ],
    );
  }
}
