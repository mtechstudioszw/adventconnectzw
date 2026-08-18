import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../config/share_config.dart';
import '../../models/sabbath_school_model.dart';
import '../../services/sabbath_school_prefs.dart';
import '../../services/sabbath_school_service.dart';
import '../../services/ss_highlights_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/cached_image.dart';
import '../../widgets/motion/brand_spinner.dart';
import '../../widgets/motion/pressable.dart';
import '../../widgets/motion/staggered_reveal.dart';
import '../../widgets/verse_share_card.dart';
import 'widgets/ss_html_text.dart';

// ---------------------------------------------------------------------------
//  Lesson list — the 13 weeks of a quarter
// ---------------------------------------------------------------------------

/// The weeks inside one quarterly, with per-week completion and offline
/// download.
class SsLessonListScreen extends StatefulWidget {
  const SsLessonListScreen({
    super.key,
    required this.quarterly,
    required this.lang,
  });

  final Quarterly quarterly;
  final String lang;

  @override
  State<SsLessonListScreen> createState() => _SsLessonListScreenState();
}

class _SsLessonListScreenState extends State<SsLessonListScreen> {
  late Future<List<SsLesson>> _future;

  @override
  void initState() {
    super.initState();
    _future = SabbathSchoolService.lessons(
      widget.quarterly.id,
      lang: widget.lang,
    );
    SabbathSchoolPrefs.revision.addListener(_onPrefs);
  }

  @override
  void dispose() {
    SabbathSchoolPrefs.revision.removeListener(_onPrefs);
    super.dispose();
  }

  void _onPrefs() {
    if (mounted) setState(() {});
  }

  Color get _accent => widget.quarterly.colorPrimary != null
      ? Color(widget.quarterly.colorPrimary!)
      : AppColors.primaryBlue;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: FutureBuilder<List<SsLesson>>(
        future: _future,
        builder: (context, snap) {
          final lessons = snap.data ?? const <SsLesson>[];
          return CustomScrollView(
            slivers: [
              _appBar(context),
              if (snap.connectionState == ConnectionState.waiting)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: BrandSpinner(size: 30)),
                )
              else if (lessons.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _empty(context),
                )
              else ...[
                if ((widget.quarterly.description).isNotEmpty)
                  SliverToBoxAdapter(child: _description(context)),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
                  sliver: SliverList.separated(
                    itemCount: lessons.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, i) => StaggeredReveal(
                      index: i,
                      child: _LessonCard(
                        lesson: lessons[i],
                        quarterly: widget.quarterly,
                        lang: widget.lang,
                        accent: _accent,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  /// Collapsing header using the quarterly's splash art — gives each quarter
  /// a distinct identity the moment it opens.
  Widget _appBar(BuildContext context) {
    final splash = widget.quarterly.splash ?? widget.quarterly.cover;
    return SliverAppBar(
      expandedHeight: 232,
      pinned: true,
      backgroundColor: _accent,
      foregroundColor: AppColors.white,
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.fromLTRB(52, 0, 16, 14),
        title: Text(
          widget.quarterly.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.appBarTitleFlat.copyWith(
            fontSize: 15,
            color: AppColors.white,
          ),
        ),
        background: Stack(
          fit: StackFit.expand,
          children: [
            if (splash != null)
              CachedImage(splash, fit: BoxFit.cover)
            else
              ColoredBox(color: _accent),
            // Scrim so the pinned title stays legible over any artwork.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.15),
                    Colors.black.withValues(alpha: 0.72),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 44,
              child: Text(
                widget.quarterly.humanDate,
                style: AppTextStyles.labelMedium.copyWith(
                  color: AppColors.white.withValues(alpha: 0.9),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _description(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: _ExpandableText(
        text: widget.quarterly.description,
        style: AppTextStyles.bodyMedium.copyWith(
          color: palette.textMuted,
          height: 1.6,
        ),
      ),
    );
  }

  Widget _empty(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.wifi_off_rounded, size: 52, color: palette.textMuted),
          const SizedBox(height: 14),
          Text(
            'Could not load these lessons.\nConnect once and they stay offline.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium
                .copyWith(color: palette.textMuted, height: 1.6),
          ),
        ],
      ),
    );
  }
}

/// "Read more" text that expands in place.
class _ExpandableText extends StatefulWidget {
  const _ExpandableText({required this.text, required this.style});
  final String text;
  final TextStyle style;

  @override
  State<_ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<_ExpandableText> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      behavior: HitTestBehavior.opaque,
      child: AnimatedSize(
        duration: AppMotion.standard,
        curve: AppMotion.ease,
        alignment: Alignment.topCenter,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.text,
              maxLines: _expanded ? null : 3,
              overflow: _expanded ? null : TextOverflow.ellipsis,
              style: widget.style,
            ),
            const SizedBox(height: 4),
            Text(
              _expanded ? 'Show less' : 'Read more',
              style: AppTextStyles.labelSmall.copyWith(
                color: AppColors.primaryBlue,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
//  Lesson card
// ---------------------------------------------------------------------------

/// One week: number badge, title, date range, completion ring and a download
/// button that pre-fetches the whole week for offline reading.
class _LessonCard extends StatefulWidget {
  const _LessonCard({
    required this.lesson,
    required this.quarterly,
    required this.lang,
    required this.accent,
  });

  final SsLesson lesson;
  final Quarterly quarterly;
  final String lang;
  final Color accent;

  @override
  State<_LessonCard> createState() => _LessonCardState();
}

class _LessonCardState extends State<_LessonCard> {
  List<SsDay> _days = const [];
  bool _downloading = false;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _loadDays();
  }

  /// Days are needed for the progress ring, so read them from cache without
  /// forcing a network round trip per card.
  Future<void> _loadDays() async {
    final days = await SabbathSchoolService.days(
      widget.quarterly.id,
      widget.lesson.id,
      lang: widget.lang,
    );
    if (mounted) setState(() => _days = days);
  }

  Future<void> _download() async {
    setState(() {
      _downloading = true;
      _progress = 0;
    });
    final ok = await SabbathSchoolService.downloadLesson(
      widget.quarterly.id,
      widget.lesson.id,
      lang: widget.lang,
      onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      },
    );
    if (!mounted) return;
    setState(() => _downloading = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'Week ${widget.lesson.weekNumber} saved for offline.'
            : 'Could not save the whole week. Try again on a better signal.'),
      ),
    );
  }

  void _open() {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SsDayReaderScreen(
          lang: widget.lang,
          quarterlyId: widget.quarterly.id,
          quarterlyTitle: widget.quarterly.title,
          lessonId: widget.lesson.id,
          lessonTitle: widget.lesson.title,
          days: _days,
          initialIndex: _todayIndex(),
        ),
      ),
    );
  }

  /// Open on today's reading when the week is current, else the first day.
  int _todayIndex() {
    for (var i = 0; i < _days.length; i++) {
      if (_days[i].isToday) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final paths = _days.map((d) => d.readPath).toList();
    final done = SabbathSchoolPrefs.readCount(paths);
    final total = paths.length;
    final complete = total > 0 && done == total;
    final isCurrent = widget.lesson.isCurrent;

    return PressEffect(
      child: Material(
        color: isCurrent
            ? AppColors.primaryBlue.withValues(alpha: 0.06)
            : palette.card,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _open,
          child: Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isCurrent ? AppColors.primaryBlue : palette.divider,
                width: isCurrent ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                _weekBadge(done, total, complete),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (isCurrent)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Text(
                            'THIS WEEK',
                            style: AppTextStyles.overline.copyWith(
                              color: AppColors.primaryBlue,
                              fontSize: 9,
                              letterSpacing: 1.1,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      Text(
                        widget.lesson.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.titleSmall.copyWith(
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _dateRange(),
                        style: AppTextStyles.bodySmall
                            .copyWith(color: palette.textMuted),
                      ),
                    ],
                  ),
                ),
                _downloadButton(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Week number inside a progress ring — completion is legible at a glance
  /// without reading any text.
  Widget _weekBadge(int done, int total, bool complete) {
    final value = total == 0 ? 0.0 : done / total;
    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: value),
              duration: AppMotion.entrance,
              curve: AppMotion.easeOut,
              builder: (context, v, _) => CircularProgressIndicator(
                value: v,
                strokeWidth: 3,
                backgroundColor: context.palette.divider,
                valueColor: AlwaysStoppedAnimation<Color>(
                  complete ? AppColors.successGreen : AppColors.primaryBlue,
                ),
              ),
            ),
          ),
          if (complete)
            const Icon(Icons.check_rounded,
                color: AppColors.successGreen, size: 22)
          else
            Text(
              '${widget.lesson.weekNumber}',
              style: AppTextStyles.titleSmall.copyWith(
                fontWeight: FontWeight.w800,
                color: AppColors.primaryBlue,
              ),
            ),
        ],
      ),
    );
  }

  Widget _downloadButton(BuildContext context) {
    if (_downloading) {
      return SizedBox(
        width: 40,
        height: 40,
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              value: _progress == 0 ? null : _progress,
              strokeWidth: 2.4,
              color: AppColors.primaryBlue,
            ),
          ),
        ),
      );
    }
    final cached = _days.isNotEmpty &&
        _days.every((d) => SabbathSchoolService.isDayCached(d.readPath));
    return IconButton(
      tooltip: cached ? 'Available offline' : 'Save for offline',
      icon: Icon(
        cached ? Icons.download_done_rounded : Icons.download_outlined,
        size: 20,
        color: cached
            ? AppColors.successGreen
            : context.palette.textMuted,
      ),
      onPressed: cached ? null : _download,
    );
  }

  String _dateRange() {
    final s = widget.lesson.startDate;
    final e = widget.lesson.endDate;
    if (s == null || e == null) return 'Week ${widget.lesson.weekNumber}';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final sm = months[s.month - 1];
    final em = months[e.month - 1];
    return s.month == e.month
        ? '$sm ${s.day} – ${e.day}'
        : '$sm ${s.day} – $em ${e.day}';
  }
}

// ---------------------------------------------------------------------------
//  Day reader
// ---------------------------------------------------------------------------

/// Reads one lesson week day by day: swipe between days, tap any scripture
/// reference to read the passage inline, mark days complete, keep a note.
class SsDayReaderScreen extends StatefulWidget {
  const SsDayReaderScreen({
    super.key,
    required this.lang,
    required this.quarterlyId,
    required this.quarterlyTitle,
    required this.lessonId,
    required this.lessonTitle,
    required this.days,
    required this.initialIndex,
    this.singleDayPath,
    this.singleDayTitle,
  });

  final String lang;
  final String quarterlyId;
  final String quarterlyTitle;
  final String lessonId;
  final String lessonTitle;
  final List<SsDay> days;
  final int initialIndex;

  /// When opened straight from "Continue reading" we may not have the week's
  /// day list yet — these let the reader open that one day immediately while
  /// the rest loads.
  final String? singleDayPath;
  final String? singleDayTitle;

  @override
  State<SsDayReaderScreen> createState() => _SsDayReaderScreenState();
}

class _SsDayReaderScreenState extends State<SsDayReaderScreen> {
  late PageController _pageCtrl;
  late List<SsDay> _days;

  /// Day id → its fetched content, populated by each `_DayPage` as it
  /// loads. The share sheet reads verses from here rather than fetching
  /// them again for a day already on screen.
  final Map<String, SsDayContent> _contentById = {};
  late int _index;
  double _scale = SabbathSchoolPrefs.fontScale();

  @override
  void initState() {
    super.initState();
    _days = widget.days;
    _index = widget.initialIndex.clamp(0, _days.isEmpty ? 0 : _days.length - 1);
    _pageCtrl = PageController(initialPage: _index);
    if (_days.isEmpty) _loadDays();
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  /// Recovers the day list when entered via "Continue reading".
  Future<void> _loadDays() async {
    final days = await SabbathSchoolService.days(
      widget.quarterlyId,
      widget.lessonId,
      lang: widget.lang,
    );
    if (!mounted || days.isEmpty) return;
    var start = 0;
    if (widget.singleDayPath != null) {
      final i = days.indexWhere((d) => d.readPath == widget.singleDayPath);
      if (i >= 0) start = i;
    }
    setState(() {
      _days = days;
      _index = start;
      _pageCtrl.dispose();
      _pageCtrl = PageController(initialPage: start);
    });
  }

  SsDay? get _day => (_index >= 0 && _index < _days.length)
      ? _days[_index]
      : null;

  void _setScale(double v) {
    final clamped = v.clamp(0.8, 2.0);
    if (clamped == _scale) return;
    setState(() => _scale = clamped);
    SabbathSchoolPrefs.setFontScale(clamped);
  }

  @override
  Widget build(BuildContext context) {
    final day = _day;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Lesson ${int.tryParse(widget.lessonId) ?? widget.lessonId}',
              style: AppTextStyles.appBarTitleFlat.copyWith(fontSize: 15),
            ),
            Text(
              widget.lessonTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.labelSmall.copyWith(
                color: AppColors.white.withValues(alpha: 0.75),
                fontSize: 11,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Text size',
            icon: const Icon(Icons.format_size_rounded),
            onPressed: _openTextSheet,
          ),
          IconButton(
            tooltip: 'Notes',
            icon: const Icon(Icons.edit_note_rounded),
            onPressed: day == null ? null : () => _openNote(day),
          ),
          IconButton(
            tooltip: 'Share',
            icon: const Icon(Icons.ios_share_rounded),
            onPressed: day == null ? null : () => _openShareSheet(day),
          ),
        ],
      ),
      body: _days.isEmpty
          ? const Center(child: BrandSpinner(size: 30))
          : Column(
              children: [
                _dayStrip(context),
                Expanded(
                  child: PageView.builder(
                    controller: _pageCtrl,
                    itemCount: _days.length,
                    onPageChanged: (i) => setState(() => _index = i),
                    itemBuilder: (context, i) => _DayPage(
                      key: ValueKey(_days[i].readPath),
                      day: _days[i],
                      fontScale: _scale,
                      onRead: () => _noteProgress(_days[i]),
                      onLoaded: (c) => _contentById[_days[i].id] = c,
                    ),
                  ),
                ),
              ],
            ),
      bottomNavigationBar: day == null ? null : _completeBar(context, day),
    );
  }

  void _noteProgress(SsDay day) {
    SabbathSchoolPrefs.setLastRead(
      lang: widget.lang,
      quarterlyId: widget.quarterlyId,
      quarterlyTitle: widget.quarterlyTitle,
      lessonId: widget.lessonId,
      lessonTitle: widget.lessonTitle,
      dayPath: day.readPath,
      dayTitle: day.title,
    );
  }

  /// Horizontal day selector — the week at a glance, with today marked and
  /// completed days ticked.
  Widget _dayStrip(BuildContext context) {
    final palette = context.palette;
    const labels = ['Sab', 'Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri'];
    return SizedBox(
      height: 68,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        itemCount: _days.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final day = _days[i];
          final selected = i == _index;
          final read = SabbathSchoolPrefs.isRead(day.readPath);
          final label = day.date != null
              ? labels[day.date!.weekday % 7]
              : '${i + 1}';
          return Pressable(
            onTap: () => _pageCtrl.animateToPage(
              i,
              duration: AppMotion.standard,
              curve: AppMotion.ease,
            ),
            child: AnimatedContainer(
              duration: AppMotion.quick,
              width: 52,
              decoration: BoxDecoration(
                gradient: selected ? AppColors.primaryGradient : null,
                color: selected ? null : palette.card,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(
                  color: day.isToday && !selected
                      ? AppColors.goldAccent
                      : selected
                          ? AppColors.primaryBlue
                          : palette.divider,
                  width: day.isToday && !selected ? 1.5 : 1,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: AppTextStyles.labelSmall.copyWith(
                      color: selected ? AppColors.white : palette.textMuted,
                      fontWeight: FontWeight.w700,
                      fontSize: 10.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  if (read)
                    Icon(
                      Icons.check_circle_rounded,
                      size: 15,
                      color: selected
                          ? AppColors.white
                          : AppColors.successGreen,
                    )
                  else
                    Text(
                      day.date != null ? '${day.date!.day}' : '·',
                      style: AppTextStyles.labelMedium.copyWith(
                        color: selected ? AppColors.white : palette.text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _completeBar(BuildContext context, SsDay day) {
    final read = SabbathSchoolPrefs.isRead(day.readPath);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Pressable(
          onTap: () {
            HapticFeedback.lightImpact();
            SabbathSchoolPrefs.toggleRead(day.readPath);
            setState(() {});
          },
          child: AnimatedContainer(
            duration: AppMotion.standard,
            curve: AppMotion.ease,
            height: 50,
            decoration: BoxDecoration(
              gradient: read ? null : AppColors.primaryGradient,
              color: read
                  ? AppColors.successGreen.withValues(alpha: 0.12)
                  : null,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(
                color: read ? AppColors.successGreen : Colors.transparent,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedSwitcher(
                  duration: AppMotion.quick,
                  child: Icon(
                    read
                        ? Icons.check_circle_rounded
                        : Icons.check_circle_outline_rounded,
                    key: ValueKey(read),
                    color: read ? AppColors.successGreen : AppColors.white,
                    size: 21,
                  ),
                ),
                const SizedBox(width: 9),
                Text(
                  read ? 'Completed' : 'Mark as read',
                  style: AppTextStyles.buttonText.copyWith(
                    color: read ? AppColors.successGreen : AppColors.white,
                  ),
                ),
              ],
            ),
          ),
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
                Text('Text size',
                    style: AppTextStyles.titleSmall
                        .copyWith(fontWeight: FontWeight.w700)),
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

  /// Share the day: as a link, or as a branded image of one of its verses.
  ///
  /// The founder asked for "the same for sabbath school" as the Bible
  /// (17 Aug) — a shareable image carrying the app logo. A whole day's
  /// reading is far too long for a card, but the day already ships its
  /// scripture in `SsDayContent.bible`, and a verse is exactly the shape
  /// the card was built for.
  ///
  /// The list only appears when there is a choice to make: one verse goes
  /// straight to the card, several offer a pick, none falls back to the
  /// plain link. Nobody should have to choose from a list of one.
  Future<void> _openShareSheet(SsDay day) async {
    final verses = _contentById[day.id]?.bible ?? const <String, String>{};
    final palette = context.palette;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: palette.sheet,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: Icon(Icons.link_rounded, color: palette.textMuted),
              title: Text(
                'Share a link',
                style: AppTextStyles.bodyMedium.copyWith(color: palette.text),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                Share.share(
                  '${widget.lessonTitle} — ${day.title}\n\n'
                  'Sabbath School on Adventist Super App:\n$appDownloadUrl',
                );
              },
            ),
            if (verses.isNotEmpty) ...[
              Divider(height: 1, color: palette.divider),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                child: Text(
                  'SHARE A VERSE AS AN IMAGE',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: palette.textMuted,
                    letterSpacing: 1.3,
                    fontWeight: FontWeight.w800,
                    fontSize: 10.5,
                  ),
                ),
              ),
              // Bounded: a day can carry a dozen references and the sheet
              // must not push its own first option off the screen.
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.45,
                ),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final entry in verses.entries)
                      ListTile(
                        dense: true,
                        leading: Icon(
                          Icons.format_quote_rounded,
                          color: AppColors.primaryBlue,
                          size: 20,
                        ),
                        title: Text(
                          entry.key,
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: palette.text,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          ssPlainText(entry.value),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.labelSmall.copyWith(
                            color: palette.textMuted,
                          ),
                        ),
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          _shareVerse(entry.key, entry.value);
                        },
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _shareVerse(String reference, String html) {
    final text = ssPlainText(html);
    if (text.isEmpty) return;
    VerseShareSheet.open(
      context,
      reference: reference,
      text: text,
      // Not "KJV": the lesson feed serves whichever translation the
      // language edition uses, and naming the wrong one on a shared image
      // would be worse than naming none.
      attribution: 'Sabbath School',
    );
  }

  void _openNote(SsDay day) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.palette.sheet,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => _DayNoteSheet(day: day),
    );
  }
}

/// The note editor, owning its own controller.
///
/// Founder, 19 Aug 2026: *"tt sabbath school error comes when reading n u
/// click the pencil icon n click back the screens turns red"* — the
/// `'_dependents.isEmpty': is not true` crash.
///
/// This used to be a plain `builder:` closure over a controller created
/// beside it:
///
///     final controller = TextEditingController(...);
///     await showModalBottomSheet(...);
///     controller.dispose();
///
/// `showModalBottomSheet`'s future completes when the route is POPPED, not
/// when it has finished leaving — the sheet is still mounted for the whole
/// exit transition. So `dispose()` ran on a controller that a live
/// `EditableText` was still listening to, and the field then failed on its
/// way out while it was still registered as a dependent of the inherited
/// widgets it had read (`Directionality`, `MediaQuery`, the focus markers).
/// When the route's elements finally unmounted,
/// `InheritedElement.debugDeactivated()` asserted `_dependents.isEmpty` and
/// the screen went red. `autofocus: true` made it reliable rather than
/// occasional, because the field was always the focused one being torn down.
///
/// Owning the controller in a `State` ties its lifetime to the widget's, so
/// it is disposed when the element actually unmounts — after the
/// transition, in the right order, by the framework.
class _DayNoteSheet extends StatefulWidget {
  const _DayNoteSheet({required this.day});

  final SsDay day;

  @override
  State<_DayNoteSheet> createState() => _DayNoteSheetState();
}

class _DayNoteSheetState extends State<_DayNoteSheet> {
  late final TextEditingController _controller = TextEditingController(
    text: SabbathSchoolPrefs.note(widget.day.readPath) ?? '',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    // Not awaited: the sheet closes on the frame the member taps Save. The
    // write is a Hive flush and nothing on screen depends on it — see the
    // reading-settings fix for what awaiting it costs.
    SabbathSchoolPrefs.setNote(widget.day.readPath, _controller.text);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 18,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 18,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Your note — ${widget.day.title}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.titleSmall
                  .copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            maxLines: 6,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'What stood out to you today?',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _save,
              child: const Text('Save note'),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
//  One day's content
// ---------------------------------------------------------------------------

class _DayPage extends StatefulWidget {
  const _DayPage({
    super.key,
    required this.day,
    required this.fontScale,
    required this.onRead,
    required this.onLoaded,
  });

  final SsDay day;
  final double fontScale;
  final VoidCallback onRead;

  /// Reports the fetched content up to the screen, so the app bar's share
  /// sheet can offer the day's verses without fetching them a second time.
  final ValueChanged<SsDayContent> onLoaded;

  @override
  State<_DayPage> createState() => _DayPageState();
}

class _DayPageState extends State<_DayPage>
    with AutomaticKeepAliveClientMixin {
  SsDayContent? _content;
  bool _loading = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final content = await SabbathSchoolService.dayContent(widget.day.readPath);
    if (!mounted) return;
    setState(() {
      _content = content;
      _loading = false;
    });
    widget.onRead();
    if (content != null) widget.onLoaded(content);

    // Reconcile this day's highlights with the account, AFTER the text is
    // on screen. Not awaited and never blocking: the local mirror already
    // painted, so this only ever corrects it — a highlight removed on
    // another device disappearing, or one made offline finally landing.
    unawaited(SsHighlights.load(widget.day.readPath));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final palette = context.palette;
    if (_loading) return const Center(child: BrandSpinner(size: 28));
    final content = _content;
    if (content == null) {
      return Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.wifi_off_rounded, size: 46, color: palette.textMuted),
            const SizedBox(height: 12),
            Text(
              'This day is not downloaded yet.\nConnect once to read it.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium
                  .copyWith(color: palette.textMuted, height: 1.6),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
      children: [
        if (widget.day.date != null)
          Text(
            _formatDate(widget.day.date!),
            style: AppTextStyles.overline.copyWith(
              color: AppColors.primaryBlue,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
            ),
          ),
        const SizedBox(height: 6),
        Text(
          content.title,
          style: AppTextStyles.headlineSmall.copyWith(
            fontWeight: FontWeight.w800,
            fontSize: 24 * widget.fontScale,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 18),
        // Highlights follow the ACCOUNT here, unlike EGW's — founder's call,
        // 19 Aug 2026. The reader rebuilds from `SsHighlights.revision`, so
        // a tap paints on the next frame and the network catches up after.
        ValueListenableBuilder<int>(
          valueListenable: SsHighlights.revision,
          builder: (context, _, _) => SsHtmlText(
            html: content.contentHtml,
            fontScale: widget.fontScale,
            highlights: SsHighlights.forDay(widget.day.readPath),
            onHighlightTap: (sentence) {
              SsHighlights.toggle(widget.day.readPath, sentence);
              HapticFeedback.selectionClick();
            },
            onVerseTap: (ref, label) =>
                _showVerse(context, content, ref, label),
          ),
        ),
      ],
    );
  }

  /// Tapping an inline reference opens the passage from the day's own bundled
  /// verse map — no network, works offline, and keeps the reader in place.
  void _showVerse(
    BuildContext context,
    SsDayContent content,
    String ref,
    String label,
  ) {
    final html = content.bible[ref];
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.palette.sheet,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.5,
        maxChildSize: 0.9,
        minChildSize: 0.3,
        builder: (ctx, scrollCtrl) => ListView(
          controller: scrollCtrl,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          children: [
            Row(
              children: [
                const Icon(Icons.menu_book_rounded,
                    color: AppColors.primaryBlue, size: 19),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: AppTextStyles.titleSmall
                        .copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (html == null)
              Text(
                'This passage was not included with the lesson. '
                'Open it in the Bible tab.',
                style: AppTextStyles.bodyMedium
                    .copyWith(color: context.palette.textMuted, height: 1.6),
              )
            else
              SsHtmlText(html: html, fontScale: widget.fontScale),
          ],
        ),
      ),
    );
  }

  static String _formatDate(DateTime d) {
    const days = [
      'MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY',
      'FRIDAY', 'SATURDAY', 'SUNDAY',
    ];
    const months = [
      'JANUARY', 'FEBRUARY', 'MARCH', 'APRIL', 'MAY', 'JUNE',
      'JULY', 'AUGUST', 'SEPTEMBER', 'OCTOBER', 'NOVEMBER', 'DECEMBER',
    ];
    return '${days[d.weekday - 1]} · ${months[d.month - 1]} ${d.day}';
  }
}
