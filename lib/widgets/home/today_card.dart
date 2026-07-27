import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:go_router/go_router.dart';

import '../../models/devotion_model.dart';
import '../../models/hymn_model.dart';
import '../../models/library_item_model.dart';
import '../../models/sabbath_school_model.dart';
import '../../services/hymn_service.dart';
import '../../services/library_service.dart';
import '../../services/sabbath_school_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';
import '../cached_image.dart';
import '../motion/pressable.dart';

/// Home's spiritual anchor: one hero card carrying today's devotion, this
/// quarter's Sabbath School lesson, and a hymn / track / EGW book of the day.
///
/// This replaced three separate blocks (the devotion card, the Sabbath School
/// chip and a hymnal chip). Carrying five sources in one swipeable card is
/// the concrete "one app instead of five" pitch — YouVersion's
/// verse-of-the-day card only carries one.
///
/// Pages self-hide when their source is empty, and the hymn page is backed by
/// a bundled asset, so the card still has something to say offline.
///
/// Motion: content inside each page travels slower than the page itself
/// (parallax), off-centre pages scale and fade, and the card's gradient
/// shifts continuously as you swipe — all driven by the [PageController]'s
/// live position rather than by discrete page-change events, so it tracks
/// the finger.
class TodayCard extends StatefulWidget {
  const TodayCard({super.key, required this.devotion});

  final Devotion? devotion;

  @override
  State<TodayCard> createState() => _TodayCardState();
}

/// One page's content plus the gradient accent it pulls the card toward.
class _Slide {
  const _Slide({required this.accent, required this.child});

  /// How far the card's gradient leans from navy toward brand blue while
  /// this page is centred. Keeps every page inside the approved palette
  /// while still giving each its own temperature.
  final double accent;
  final Widget child;
}

class _TodayCardState extends State<TodayCard> {
  final PageController _pc = PageController();
  int _page = 0;
  Quarterly? _quarterly;
  Hymn? _hymn;
  LibraryItem? _track;
  LibraryItem? _book;

  @override
  void initState() {
    super.initState();
    _loadHymn();
    _loadQuarterly();
    _loadLibraryPick('music', (i) => _track = i);
    _loadLibraryPick('egw', (i) => _book = i);
  }

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  /// Day-of-epoch, used to seed every "of the day" pick. Deterministic on
  /// purpose: the whole community gets the SAME hymn, track and book on the
  /// same day, so it reads as a shared devotional, not a private shuffle.
  static int get _epochDay =>
      DateTime.now().toUtc().millisecondsSinceEpoch ~/
      Duration.millisecondsPerDay;

  Future<void> _loadHymn() async {
    try {
      final hymns = await HymnService.all();
      if (!mounted || hymns.isEmpty) return;
      setState(() => _hymn = hymns[_epochDay % hymns.length]);
    } catch (_) {
      // Bundled asset failed to parse — the card just drops this page.
    }
  }

  Future<void> _loadQuarterly() async {
    try {
      final q = await SabbathSchoolService.currentQuarterly();
      if (mounted) setState(() => _quarterly = q);
    } catch (_) {
      // Offline or Adventech down — page drops out silently.
    }
  }

  /// Picks one Library item of [kind] for today. Music and EGW share this —
  /// both are `library_items` rows with the same shape.
  Future<void> _loadLibraryPick(
    String kind,
    void Function(LibraryItem) assign,
  ) async {
    try {
      final items = await LibraryService.fetchItems(kind);
      if (!mounted || items.isEmpty) return;
      setState(() => assign(items[_epochDay % items.length]));
    } catch (_) {
      // Offline or empty shelf — the page simply doesn't appear.
    }
  }

  List<_Slide> _slides() => [
        if (widget.devotion != null)
          _Slide(accent: 0.06, child: _DevotionPage(devotion: widget.devotion!)),
        if (_quarterly != null)
          _Slide(accent: 0.22, child: _LessonPage(quarterly: _quarterly!)),
        if (_hymn != null) _Slide(accent: 0.34, child: _HymnPage(hymn: _hymn!)),
        if (_track != null)
          _Slide(
            accent: 0.48,
            child: _LibraryPickPage(
              item: _track!,
              label: 'MUSIC OF THE DAY',
              icon: Icons.headphones_outlined,
              fallbackIcon: Icons.music_note_rounded,
              openLabel: 'Play in Music',
              tabIndex: 4,
            ),
          ),
        if (_book != null)
          _Slide(
            accent: 0.28,
            child: _LibraryPickPage(
              item: _book!,
              label: 'EGW READ OF THE DAY',
              icon: Icons.auto_stories_outlined,
              fallbackIcon: Icons.menu_book_rounded,
              openLabel: 'Open the book',
              tabIndex: 3,
            ),
          ),
      ];

  /// Live page position — fractional while the finger is mid-swipe.
  double get _pageValue {
    if (_pc.hasClients && _pc.position.haveDimensions) {
      return _pc.page ?? _page.toDouble();
    }
    return _page.toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final slides = _slides();
    if (slides.isEmpty) return const SizedBox.shrink();
    final animate = AppMotion.enabled(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
      child: AnimatedBuilder(
        animation: _pc,
        builder: (context, _) {
          // Blend the gradient between the two pages either side of the
          // current position, so the colour shifts continuously as you swipe.
          final p = _pageValue.clamp(0.0, (slides.length - 1).toDouble());
          final lo = p.floor().clamp(0, slides.length - 1);
          final hi = p.ceil().clamp(0, slides.length - 1);
          final accent = lo == hi
              ? slides[lo].accent
              : slides[lo].accent +
                  (slides[hi].accent - slides[lo].accent) * (p - lo);
          final end = Color.lerp(
            const Color(0xFF1A2F5A),
            AppColors.primaryBlue,
            accent,
          )!;

          return Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.darkNavy, end],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(AppRadius.lg),
              boxShadow: AppShadows.card(context),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 186,
                  child: PageView.builder(
                    controller: _pc,
                    itemCount: slides.length,
                    onPageChanged: (i) {
                      HapticFeedback.selectionClick();
                      setState(() => _page = i);
                    },
                    itemBuilder: (context, i) {
                      if (!animate) return slides[i].child;
                      // Parallax: content lags the page it rides on, and
                      // shrinks + fades as it leaves the centre.
                      final delta = (_pageValue - i).clamp(-1.0, 1.0);
                      final away = delta.abs();
                      return Opacity(
                        opacity: (1 - away * 0.7).clamp(0.0, 1.0),
                        child: Transform.translate(
                          offset: Offset(-delta * 46, 0),
                          child: Transform.scale(
                            scale: 1 - away * 0.06,
                            child: slides[i].child,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                _Dots(
                  count: slides.length,
                  position: _pageValue.clamp(
                    0.0,
                    (slides.length - 1).toDouble(),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Shared chrome for every page: eyebrow label, body, tap target.
class _PageShell extends StatelessWidget {
  const _PageShell({
    required this.label,
    required this.icon,
    required this.child,
    required this.onTap,
    this.backdrop,
  });

  final String label;
  final IconData icon;
  final Widget child;
  final VoidCallback onTap;

  /// Optional full-bleed art sitting behind the text at low opacity.
  final Widget? backdrop;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      pressedScale: 0.985,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ?backdrop,
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.lg,
              AppSpace.lg,
              AppSpace.lg,
              AppSpace.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      icon,
                      size: 14,
                      color: AppColors.white.withValues(alpha: 0.75),
                    ),
                    const SizedBox(width: AppSpace.sm),
                    Text(
                      label,
                      style: AppTextStyles.labelSmall.copyWith(
                        color: AppColors.white.withValues(alpha: 0.75),
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpace.md),
                Expanded(child: child),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DevotionPage extends StatelessWidget {
  const _DevotionPage({required this.devotion});
  final Devotion devotion;

  @override
  Widget build(BuildContext context) {
    return _PageShell(
      label: "TODAY'S DEVOTION",
      icon: Icons.wb_twilight_rounded,
      onTap: () => context.pushNamed('library', extra: 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: Text(
              '"${devotion.bibleText}"',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.white,
                height: 1.45,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
          const SizedBox(height: AppSpace.sm),
          Text(
            devotion.bibleRef,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.labelMedium.copyWith(
              color: AppColors.white.withValues(alpha: 0.9),
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              '${devotion.egwQuote}  — Ellen G. White, ${devotion.egwSource}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.caption.copyWith(
                color: AppColors.white.withValues(alpha: 0.72),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LessonPage extends StatelessWidget {
  const _LessonPage({required this.quarterly});
  final Quarterly quarterly;

  @override
  Widget build(BuildContext context) {
    return _PageShell(
      label: 'SABBATH SCHOOL',
      icon: Icons.school_outlined,
      onTap: () => context.pushNamed('library', extra: 1),
      backdrop: (quarterly.cover ?? '').isEmpty
          ? null
          : _ArtBackdrop(url: quarterly.cover!),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: Text(
              quarterly.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.titleLarge.copyWith(
                color: AppColors.white,
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
          ),
          const SizedBox(height: AppSpace.xs + 2),
          Text(
            quarterly.humanDate,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.caption.copyWith(
              color: AppColors.white.withValues(alpha: 0.75),
            ),
          ),
          const Spacer(),
          const _OpenHint(label: 'Open this quarter'),
        ],
      ),
    );
  }
}

class _HymnPage extends StatelessWidget {
  const _HymnPage({required this.hymn});
  final Hymn hymn;

  @override
  Widget build(BuildContext context) {
    // First non-empty lyric line as a taster.
    final firstLine = hymn.lyrics
        .split('\n')
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty, orElse: () => '');
    return _PageShell(
      label: 'HYMN OF THE DAY',
      icon: Icons.queue_music_outlined,
      onTap: () => context.pushNamed('library', extra: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: Text(
              hymn.displayTitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.titleLarge.copyWith(
                color: AppColors.white,
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
          ),
          if (firstLine.isNotEmpty) ...[
            const SizedBox(height: AppSpace.sm),
            Flexible(
              child: Text(
                firstLine,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.white.withValues(alpha: 0.75),
                  height: 1.4,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
          const Spacer(),
          const _OpenHint(label: 'Open in hymnal'),
        ],
      ),
    );
  }
}

/// Music-of-the-day and EGW-read-of-the-day. Both are `library_items` rows,
/// so they share one page: cover thumbnail, title, author, and the same
/// blurred-art backdrop treatment.
class _LibraryPickPage extends StatelessWidget {
  const _LibraryPickPage({
    required this.item,
    required this.label,
    required this.icon,
    required this.fallbackIcon,
    required this.openLabel,
    required this.tabIndex,
  });

  final LibraryItem item;
  final String label;
  final IconData icon;
  final IconData fallbackIcon;
  final String openLabel;
  final int tabIndex;

  @override
  Widget build(BuildContext context) {
    final cover = item.coverUrl ?? '';
    final author = (item.author ?? '').trim();
    return _PageShell(
      label: label,
      icon: icon,
      onTap: () => context.pushNamed('library', extra: tabIndex),
      backdrop: cover.isEmpty ? null : _ArtBackdrop(url: cover),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 62,
            height: 62,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              color: AppColors.white.withValues(alpha: 0.12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: cover.isEmpty
                ? Icon(fallbackIcon, color: AppColors.white, size: 26)
                : CachedImage(
                    cover,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        Icon(fallbackIcon, color: AppColors.white, size: 26),
                  ),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Flexible(
                  child: Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.titleLarge.copyWith(
                      color: AppColors.white,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                ),
                if (author.isNotEmpty) ...[
                  const SizedBox(height: AppSpace.xs),
                  Text(
                    author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.white.withValues(alpha: 0.75),
                    ),
                  ),
                ],
                const Spacer(),
                _OpenHint(label: openLabel),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Cover art bled behind a page at low opacity, with a scrim so white text
/// stays legible no matter how bright the artwork is.
class _ArtBackdrop extends StatelessWidget {
  const _ArtBackdrop({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Opacity(
            opacity: 0.26,
            child: CachedImage(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  AppColors.darkNavy.withValues(alpha: 0.92),
                  AppColors.darkNavy.withValues(alpha: 0.45),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OpenHint extends StatelessWidget {
  const _OpenHint({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.labelMedium.copyWith(
              color: AppColors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const Icon(
          Icons.chevron_right_rounded,
          size: 18,
          color: AppColors.white,
        ),
      ],
    );
  }
}

/// Page dots that track the swipe continuously — the active pill stretches
/// toward the next dot as you drag, instead of snapping on page change.
class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.position});
  final int count;
  final double position;

  @override
  Widget build(BuildContext context) {
    if (count <= 1) return const SizedBox(height: AppSpace.md);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md, top: AppSpace.xs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < count; i++)
            () {
              // 1.0 when this dot is centred, 0.0 once a full page away.
              final near = (1 - (position - i).abs()).clamp(0.0, 1.0);
              return Container(
                width: 6 + 12 * near,
                height: 6,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: AppColors.white.withValues(
                    alpha: 0.32 + 0.63 * near,
                  ),
                  borderRadius: BorderRadius.circular(3),
                ),
              );
            }(),
        ],
      ),
    );
  }
}
