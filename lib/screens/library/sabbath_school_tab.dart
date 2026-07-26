import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/sabbath_school_model.dart';
import '../../services/sabbath_school_prefs.dart';
import '../../services/sabbath_school_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/cached_image.dart';
import '../../widgets/motion/brand_spinner.dart';
import '../../widgets/motion/branded_refresh_indicator.dart';
import '../../widgets/motion/pressable.dart';
import '../../widgets/motion/staggered_reveal.dart';
import 'ss_lesson_screen.dart';

/// Library → Sabbath School tab.
///
/// Lessons come from Adventech's public API (the same feed the official
/// Sabbath School app uses) in ~90 languages, Shona by default. Everything
/// read once is cached, so a downloaded quarter works with no connection.
class SabbathSchoolTab extends StatefulWidget {
  const SabbathSchoolTab({super.key});

  @override
  State<SabbathSchoolTab> createState() => _SabbathSchoolTabState();
}

class _SabbathSchoolTabState extends State<SabbathSchoolTab>
    with AutomaticKeepAliveClientMixin {
  late String _lang;
  Future<List<Quarterly>>? _future;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _lang = SabbathSchoolService.language();
    _future = SabbathSchoolService.quarterlies(lang: _lang);
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

  Future<void> _refresh() async {
    final future = SabbathSchoolService.quarterlies(lang: _lang);
    setState(() => _future = future);
    await future;
  }

  Future<void> _switchLanguage(String code) async {
    if (code == _lang) return;
    await SabbathSchoolService.setLanguage(code);
    if (!mounted) return;
    setState(() {
      _lang = code;
      _future = SabbathSchoolService.quarterlies(lang: code);
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return BrandedRefreshIndicator(
      color: AppColors.primaryBlue,
      onRefresh: _refresh,
      child: FutureBuilder<List<Quarterly>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: BrandSpinner(size: 30));
          }
          final all = snap.data ?? const <Quarterly>[];
          if (all.isEmpty) return _empty(context);

          // Adult quarterlies lead; other groups (Youth, Primary…) follow.
          final current = all.firstWhere(
            (q) => q.isCurrent,
            orElse: () => all.first,
          );
          final rest = all.where((q) => q.id != current.id).take(24).toList();

          return CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: _languageBar(context)),
              SliverToBoxAdapter(child: _continueCard(context)),
              SliverToBoxAdapter(child: _CurrentQuarterHero(
                quarterly: current,
                lang: _lang,
              )),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 26, 16, 10),
                  child: Text(
                    'More quarters',
                    style: AppTextStyles.titleSmall.copyWith(
                      fontWeight: FontWeight.w700,
                      color: context.palette.text,
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                sliver: SliverList.separated(
                  itemCount: rest.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) => StaggeredReveal(
                    index: i,
                    child: _QuarterRow(quarterly: rest[i], lang: _lang),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ---- Language -----------------------------------------------------------

  Widget _languageBar(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
      child: Pressable(
        onTap: _openLanguagePicker,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: palette.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: palette.divider),
          ),
          child: Row(
            children: [
              const Icon(Icons.translate_rounded,
                  size: 19, color: AppColors.primaryBlue),
              const SizedBox(width: 10),
              Text(
                'Language',
                style: AppTextStyles.labelMedium
                    .copyWith(color: palette.textMuted),
              ),
              const Spacer(),
              Text(
                _langName(_lang),
                style: AppTextStyles.labelMedium.copyWith(
                  color: palette.text,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.expand_more_rounded, color: palette.textMuted),
            ],
          ),
        ),
      ),
    );
  }

  /// Best-effort label before the live list resolves.
  String _langName(String code) {
    const known = {
      'sn': 'Shona',
      'en': 'English',
      'nd': 'Ndebele',
      'af': 'Afrikaans',
      'pt': 'Português',
      'sw': 'Kiswahili',
    };
    return known[code] ?? code.toUpperCase();
  }

  Future<void> _openLanguagePicker() async {
    final palette = context.palette;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: palette.sheet,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SizedBox(
        height: MediaQuery.sizeOf(ctx).height * 0.75,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Row(
                children: [
                  Text(
                    'Lesson language',
                    style: AppTextStyles.titleSmall
                        .copyWith(fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  Text(
                    'Shona is the default',
                    style: AppTextStyles.labelSmall
                        .copyWith(color: palette.textMuted),
                  ),
                ],
              ),
            ),
            Divider(color: palette.divider, height: 1),
            Expanded(
              child: FutureBuilder<List<SsLanguage>>(
                future: SabbathSchoolService.languages(),
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return const Center(child: BrandSpinner(size: 26));
                  }
                  final langs = snap.data!;
                  return ListView.builder(
                    itemCount: langs.length,
                    itemBuilder: (context, i) {
                      final l = langs[i];
                      final selected = l.code == _lang;
                      return ListTile(
                        title: Text(
                          l.name,
                          style: AppTextStyles.bodyMedium.copyWith(
                            fontWeight:
                                selected ? FontWeight.w700 : FontWeight.w500,
                            color:
                                selected ? AppColors.primaryBlue : palette.text,
                          ),
                        ),
                        subtitle: Text(
                          l.code.toUpperCase(),
                          style: AppTextStyles.labelSmall
                              .copyWith(color: palette.textMuted),
                        ),
                        trailing: selected
                            ? const Icon(Icons.check_circle_rounded,
                                color: AppColors.primaryBlue)
                            : null,
                        onTap: () {
                          Navigator.of(ctx).pop();
                          _switchLanguage(l.code);
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- Continue reading ---------------------------------------------------

  Widget _continueCard(BuildContext context) {
    final last = SabbathSchoolPrefs.lastRead();
    if (last == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Pressable(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SsDayReaderScreen(
              lang: last['lang']?.toString() ?? _lang,
              quarterlyId: last['quarterly_id']?.toString() ?? '',
              quarterlyTitle: last['quarterly_title']?.toString() ?? '',
              lessonId: last['lesson_id']?.toString() ?? '',
              lessonTitle: last['lesson_title']?.toString() ?? '',
              days: const [],
              initialIndex: 0,
              singleDayPath: last['day_path']?.toString(),
              singleDayTitle: last['day_title']?.toString(),
            ),
          ),
        ),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryBlue.withValues(alpha: 0.3),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              const Icon(Icons.play_circle_fill_rounded,
                  color: AppColors.white, size: 34),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Continue reading',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: AppColors.white.withValues(alpha: 0.85),
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      last['day_title']?.toString() ?? 'Lesson',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.titleSmall.copyWith(
                        color: AppColors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Dismiss',
                icon: Icon(Icons.close_rounded,
                    color: AppColors.white.withValues(alpha: 0.8), size: 18),
                onPressed: () => SabbathSchoolPrefs.clearLastRead(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _empty(BuildContext context) {
    final palette = context.palette;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 90),
        Icon(Icons.wifi_off_rounded, size: 58, color: palette.textMuted),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(
            'Lessons need a connection the first time.\n'
            'Once opened, they stay available offline.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(
              color: palette.textMuted,
              height: 1.6,
            ),
          ),
        ),
        const SizedBox(height: 18),
        Center(
          child: Pressable(
            onTap: _refresh,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                'Try again',
                style: AppTextStyles.buttonText
                    .copyWith(color: AppColors.white),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
//  Current quarter hero
// ---------------------------------------------------------------------------

/// Large cover card for the active quarter, tinted with the quarterly's own
/// accent colour so each quarter feels like its own book.
class _CurrentQuarterHero extends StatelessWidget {
  const _CurrentQuarterHero({required this.quarterly, required this.lang});

  final Quarterly quarterly;
  final String lang;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final accent = quarterly.colorPrimary != null
        ? Color(quarterly.colorPrimary!)
        : AppColors.primaryBlue;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Pressable(
        onTap: () => _openLessons(context),
        child: Container(
          decoration: BoxDecoration(
            color: palette.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: palette.divider),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.22),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        width: 92,
                        height: 130,
                        child: quarterly.cover != null
                            ? CachedImage(quarterly.cover!, fit: BoxFit.cover)
                            : ColoredBox(
                                color: accent,
                                child: const Icon(Icons.menu_book_rounded,
                                    color: AppColors.white, size: 36),
                              ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (quarterly.isCurrent)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.successGreen
                                    .withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(7),
                              ),
                              child: Text(
                                'THIS QUARTER',
                                style: AppTextStyles.overline.copyWith(
                                  color: AppColors.successGreen,
                                  fontSize: 9,
                                  letterSpacing: 1.1,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          const SizedBox(height: 7),
                          Text(
                            quarterly.title,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.titleMedium.copyWith(
                              fontWeight: FontWeight.w800,
                              height: 1.25,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            quarterly.humanDate,
                            style: AppTextStyles.bodySmall
                                .copyWith(color: palette.textMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                child: SizedBox(
                  width: double.infinity,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      'Open lessons',
                      style: AppTextStyles.buttonText
                          .copyWith(color: AppColors.white),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openLessons(BuildContext context) {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SsLessonListScreen(quarterly: quarterly, lang: lang),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
//  Quarter row (older quarters)
// ---------------------------------------------------------------------------

class _QuarterRow extends StatelessWidget {
  const _QuarterRow({required this.quarterly, required this.lang});

  final Quarterly quarterly;
  final String lang;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return PressEffect(
      child: Material(
        color: palette.card,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  SsLessonListScreen(quarterly: quarterly, lang: lang),
            ),
          ),
          child: Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: palette.divider),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: SizedBox(
                    width: 46,
                    height: 64,
                    child: quarterly.cover != null
                        ? CachedImage(quarterly.cover!, fit: BoxFit.cover)
                        : const DecoratedBox(
                            decoration: BoxDecoration(
                                gradient: AppColors.primaryGradient),
                            child: Icon(Icons.menu_book_rounded,
                                color: AppColors.white, size: 20),
                          ),
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        quarterly.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.titleSmall
                            .copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        quarterly.humanDate,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodySmall
                            .copyWith(color: palette.textMuted),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: palette.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
