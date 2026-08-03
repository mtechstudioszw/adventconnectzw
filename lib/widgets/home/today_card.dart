import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:go_router/go_router.dart';

import '../../models/devotion_model.dart';
import '../../models/hymn_model.dart';
import '../../models/library_item_model.dart';
import '../../models/sabbath_school_model.dart';
import '../../screens/library/bible_tab.dart' show BibleReaderScreen;
import '../../services/bible_service.dart';
import '../../services/hymn_service.dart';
import '../../services/library_launch_intent.dart';
import '../../services/library_service.dart';
import '../../services/sabbath_school_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';
import '../cached_image.dart';
import '../verse_share_card.dart';
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
              openLabel: 'Play this track',
              tabIndex: 4,
              playOnOpen: true,
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
                  // 186 → 224, then grown with the system text size.
                  //
                  // The devotion page carries the most text of the five
                  // (verse + reference + an Ellen White quote), and raising
                  // the fixed height was only ever half a fix: the verse
                  // already had `maxLines: 4` and an ellipsis, but a `Text`
                  // does not drop lines to fit a height — it lays out its
                  // four lines and the parent's `Clip.antiAlias` cuts off
                  // whatever does not fit. So it clipped mid-sentence
                  // instead of ellipsizing, silently and with no overflow
                  // stripe, and every step up in system text size made it
                  // worse. Scaling the box is what actually keeps the
                  // ellipsis reachable.
                  //
                  // Clamped at 1.6: past that the card would push the rest
                  // of the feed off screen, and the "Read the full
                  // devotion" hint below is the honest way out.
                  height: 224 *
                      MediaQuery.textScalerOf(context)
                          .scale(1.0)
                          .clamp(1.0, 1.6),
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
    this.action,
    required this.child,
    required this.onTap,
    this.backdrop,
  });

  final String label;
  final IconData icon;

  /// Optional action pinned to the right of the eyebrow row. Only the
  /// devotion page uses it, to share the verse as an image.
  final Widget? action;
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
                    if (action != null) ...[
                      const Spacer(),
                      action!,
                    ],
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
      // Home showed the verse and gave no way to send it on — the whole
      // point of a verse of the day. Reuses the Library's generator
      // rather than a second one, so a verse shared from Home and the
      // same verse shared from the reader produce an identical image.
      action: _ShareVerseButton(
        reference: devotion.bibleRef,
        text: devotion.bibleText,
      ),
      // Opens the Bible AT the verse, scrolled to it and highlighted —
      // rather than dropping the member at the top of the Library to find
      // it themselves, which is what tapping "verse of the day" used to do.
      onTap: () => _openVerse(context, devotion.bibleRef),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: Text(
              '"${devotion.bibleText}"',
              maxLines: 4,
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
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.caption.copyWith(
                color: AppColors.white.withValues(alpha: 0.72),
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: AppSpace.xs),
          // A card this size can never hold a full devotion, so say so
          // instead of ending on a clipped word with no way forward.
          const _OpenHint(label: 'Read the full devotion'),
        ],
      ),
    );
  }
}

/// Open the Bible reader at [reference], scrolled to the verse.
///
/// The reference is free text written by whoever authored the devotion, so
/// it can be anything from "John 3:16" to "1 Cor. 13:4". When it cannot be
/// resolved we fall back to opening the Bible tab — the old behaviour —
/// rather than guessing at a chapter and landing somewhere wrong.
Future<void> _openVerse(BuildContext context, String reference) async {
  final navigator = Navigator.of(context);
  final router = GoRouter.of(context);
  BibleReference? target;
  try {
    target = await BibleService.resolveReference(reference);
  } catch (_) {
    target = null;
  }
  if (target == null) {
    router.pushNamed('library', extra: 0);
    return;
  }
  await navigator.push(
    MaterialPageRoute(
      builder: (_) => BibleReaderScreen(
        book: target!.book,
        // BibleReaderScreen indexes chapters AND verses from 0;
        // BibleReference is 1-based because that is how references are
        // written. Convert both, or "John 3:16" lands on verse 17.
        chapter: target.chapter - 1,
        scrollToVerse: target.verse == null ? null : target.verse! - 1,
      ),
    ),
  );
}

/// Share affordance on the devotion page's eyebrow row.
///
/// Its own tap target inside a card that is itself tappable, so the
/// GestureDetector has to sit ABOVE the Pressable in the tree — which it
/// does, being a child of the shell rather than a sibling.
class _ShareVerseButton extends StatelessWidget {
  const _ShareVerseButton({required this.reference, required this.text});

  final String reference;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Share this verse',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          VerseShareSheet.open(context, reference: reference, text: text);
        },
        child: Padding(
          // Padding rather than a fixed box: this sits in a row of text
          // that grows with the system font.
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.sm,
            vertical: AppSpace.xs,
          ),
          child: Icon(
            Icons.ios_share_rounded,
            size: 15,
            color: AppColors.white.withValues(alpha: 0.85),
          ),
        ),
      ),
    );
  }
}

class _LessonPage extends StatelessWidget {
  const _LessonPage({required this.quarterly});
  final Quarterly quarterly;

  @override
  Widget build(BuildContext context) {
    final cover = quarterly.cover ?? '';
    return _PageShell(
      label: 'SABBATH SCHOOL',
      icon: Icons.school_outlined,
      onTap: () {
        LibraryLaunchIntent.quarterlyId = quarterly.id;
        context.pushNamed('library', extra: 1);
      },
      backdrop: cover.isEmpty ? null : _ArtBackdrop(url: cover),
      // The quarterly cover now appears as a real thumbnail, not only as a
      // wash behind the text. At 26% opacity under a 92% navy scrim the
      // backdrop was effectively invisible, so this page looked like the one
      // slide with no artwork — which is exactly what it was reported as.
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CoverTile(
            url: cover,
            fallbackIcon: Icons.school_rounded,
            // Quarterly covers are portrait book jackets, unlike the square
            // album art the music and EGW pages carry.
            width: 52,
            height: 68,
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
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
          ),
        ],
      ),
    );
  }
}

/// Shared artwork tile for the Today pages — quarterly jackets, album art and
/// book covers all land here so they degrade the same way.
class _CoverTile extends StatelessWidget {
  const _CoverTile({
    required this.url,
    required this.fallbackIcon,
    this.width = 62,
    this.height = 62,
  });

  final String url;
  final IconData fallbackIcon;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final fallback = Icon(fallbackIcon, color: AppColors.white, size: 26);
    return Container(
      width: width,
      height: height,
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
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
      child: url.isEmpty
          ? fallback
          : CachedImage(
              url,
              fit: BoxFit.cover,
              width: width,
              height: height,
              errorBuilder: (_, _, _) => fallback,
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
      // Carries the hymn's id so the reader opens on THIS hymn rather
      // than the member landing in the hymnal to search for the thing
      // they just tapped.
      onTap: () {
        LibraryLaunchIntent.hymnId = hymn.id;
        context.pushNamed('library', extra: 2);
      },
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
    this.playOnOpen = false,
  });

  final LibraryItem item;
  final String label;
  final IconData icon;
  final IconData fallbackIcon;
  final String openLabel;
  final int tabIndex;

  /// Music of the day starts playing THIS track on arrival instead of just
  /// opening the Music tab — tapping a named track and landing in an
  /// undifferentiated catalogue was the complaint.
  final bool playOnOpen;

  void _open(BuildContext context) {
    // Both kinds now name their target. Music starts playing; a book
    // opens in the reader. Which field is set is what tells the receiving
    // tab this was a deep link rather than an ordinary visit.
    if (playOnOpen) {
      LibraryLaunchIntent.musicItemId = item.id;
    } else {
      LibraryLaunchIntent.egwItemId = item.id;
    }
    context.pushNamed('library', extra: tabIndex);
  }

  @override
  Widget build(BuildContext context) {
    final cover = item.coverUrl ?? '';
    final author = (item.author ?? '').trim();
    return _PageShell(
      label: label,
      icon: icon,
      onTap: () => _open(context),
      backdrop: cover.isEmpty ? null : _ArtBackdrop(url: cover),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CoverTile(url: cover, fallbackIcon: fallbackIcon),
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
            // Raised from 0.26 — under the navy scrim below, the artwork was
            // reading as noise rather than as a picture.
            opacity: 0.42,
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
