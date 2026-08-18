import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../models/egw_book_model.dart';
import '../../services/cache_service.dart';
import '../../services/egw_highlights.dart';
import '../../services/egw_paginator.dart';
import '../../services/egw_reader_prefs.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/verse_share_card.dart';

/// The reflowable EGW reader.
///
/// Replaces `PdfViewerScreen` for any book with an EPUB. The founder's
/// brief was "remove the pdf feel, make it premium", and everything here
/// follows from having TEXT instead of rendered page images:
///
///   * real typography — the app's own Poppins, a measured column, proper
///     leading, and a first-line indent that follows the book's own
///     `standard-indented` convention;
///   * Day / Sepia / Night as real grounds, not an inverted scan;
///   * type size that reflows instead of zooming a fixed page;
///   * select any passage → a branded quote card citing the CANONICAL page;
///   * scripture the source already tagged, rendered as a live link.
///
/// One chapter is one scroll view. Chapters are separate routes rather than
/// one giant list because the books run to 46M characters across the shelf
/// and a single `ListView` of every paragraph would make jumping to a
/// chapter an O(n) scroll.
class EgwReaderScreen extends StatefulWidget {
  const EgwReaderScreen({
    super.key,
    required this.book,
    required this.bookId,
    this.initialChapter,
  });

  final EgwBook book;

  /// Stable id for progress keys — the Library item id, not the title.
  final String bookId;

  final int? initialChapter;

  @override
  State<EgwReaderScreen> createState() => _EgwReaderScreenState();
}

class _EgwReaderScreenState extends State<EgwReaderScreen> {
  late int _chapter;
  late PageController _pager = PageController();

  /// The current chapter, cut into screen-sized pages.
  List<EgwPage> _pages = const [];

  /// Identity of the layout the current [_pages] were measured for.
  /// Re-measuring is only correct when the viewport, type size or chapter
  /// changes — doing it every build would repaginate on every frame of the
  /// turn.
  String _pagesKey = '';

  /// Chrome hides while reading and comes back on a tap, so the page is the
  /// only thing on screen — the single biggest difference between "a reader"
  /// and "a document viewer".
  bool _chromeVisible = true;

  /// Live selection, kept for the "Share quote" action.
  String _selection = '';

  /// The page the pager has settled on.
  ///
  /// A `ValueNotifier` and not `setState`, because the ONLY thing on screen
  /// that depends on it is the "Page 4 of 12" counter in the bottom bar.
  /// `onPageChanged` used to call `setState`, which rebuilt the whole
  /// reader — including the `PageView`'s `itemBuilder`, which re-creates
  /// every `TextSpan` on all three live pages — in the middle of the fling.
  /// That is the founder's *"page animation when swipping is abit lagging"*
  /// (18 Aug 2026): the jank landed exactly at the moment the page crossed.
  final ValueNotifier<int> _pageIndex = ValueNotifier<int>(0);

  /// Where a pointer went down, so a tap can be told from a scroll.
  Offset? _pointerDown;

  /// Set when a paragraph has just claimed a tap as a highlight.
  ///
  /// The page-wide chrome toggle is a raw `Listener`, which sees every
  /// pointer up whether or not a gesture consumed it. Hit testing dispatches
  /// innermost-first, so a paragraph's `onTapUp` has already run by the time
  /// the outer listener is called — without this, tapping a sentence would
  /// highlight it AND hide the chrome in the same tap.
  bool _tapClaimedByText = false;

  /// The statements the member has picked, in reading order.
  ///
  /// Founder, 18 Aug 2026: *"the moment i click the text should highlight n
  /// there a big share button to share image or text of the quote… n option
  /// to highlight more sentence like how u highlight bible verse"*.
  ///
  /// So a tap does three things at once — highlights the statement, opens
  /// the share bar, and leaves the bar open so the NEXT tap extends the
  /// quote rather than starting a new one. That is the Bible tab's own
  /// multi-verse behaviour, applied to sentences: a statement here is what
  /// a verse is there, which is why the boundary rule ends on a full stop.
  final List<_Picked> _quote = [];

  /// Where reading stopped, as `chapter` or `chapter|anchor`.
  ///
  /// `pref:`-prefixed on purpose. This is a place in a public-domain book,
  /// not personal content, and it belongs to the handset — losing it on
  /// sign-out would be the same "it forgot where I was" the founder is
  /// reporting. See [EgwHighlights] for the case that goes the other way.
  String get _positionKey => 'pref:egw_pos:${widget.bookId}';

  /// The place to jump to once the chapter has been measured, if any.
  ///
  /// Founder, 18 Aug 2026: *"when reading egw books its not caching when u
  /// end reading so it will continue from there"*. Only the CHAPTER was
  /// ever stored, so reopening a book dropped you at the top of a chapter
  /// you might be forty pages into.
  ///
  /// The page number itself is the wrong thing to store: the reader
  /// repaginates on every type-size, orientation or viewport change, so
  /// "page 12" means a different place by the next session. What is stable
  /// is the TEXT the page started on — the same reasoning that made
  /// [EgwHighlights] store passages rather than offsets — so that is the
  /// anchor, and it is re-found by matching.
  String? _pendingAnchor;

  /// How much of the page's opening text identifies it. Long enough to be
  /// unique inside a chapter, short enough to survive the parser collapsing
  /// whitespace differently.
  static const int _anchorLength = 60;

  @override
  void initState() {
    super.initState();
    final stored = CacheService.readPref(_positionKey) ?? '';
    final divider = stored.indexOf('|');
    // Older builds wrote a bare chapter index; it still reads correctly.
    final chapterPart = divider < 0 ? stored : stored.substring(0, divider);
    if (divider >= 0) {
      final anchor = stored.substring(divider + 1);
      if (anchor.isNotEmpty) _pendingAnchor = anchor;
    }
    _chapter = widget.initialChapter ?? int.tryParse(chapterPart) ?? 0;
    // A chapter named by the caller is a deliberate jump, not a resume.
    if (widget.initialChapter != null) _pendingAnchor = null;
    _chapter = _chapter.clamp(0, widget.book.chapters.length - 1);
  }

  @override
  void dispose() {
    _pager.dispose();
    _pageIndex.dispose();
    super.dispose();
  }

  void _goTo(int index) {
    if (index < 0 || index >= widget.book.chapters.length) return;
    setState(() {
      _chapter = index;
      _chromeVisible = true;
      _pagesKey = ''; // force a re-measure for the new chapter
      _pendingAnchor = null;
      _quote.clear();
      // A fresh controller so the new chapter opens on its first page
      // without animating a turn across the whole old chapter.
      _pager.dispose();
      _pager = PageController();
    });
    _pageIndex.value = 0;
    _savePosition(0);
    HapticFeedback.selectionClick();
  }

  EgwChapter get _current => widget.book.chapters[_chapter];

  /// Records the chapter and the words the given page opens on.
  ///
  /// Not awaited, and deliberately so: `writePref` reaches Hive's in-memory
  /// keystore before its first `await`, so the position is already readable
  /// on this frame, and nothing on screen may wait on a disk flush while a
  /// page is turning. That await is what froze the reading-settings sheet.
  void _savePosition(int page) {
    final anchor = _anchorFor(page);
    CacheService.writePref(
      _positionKey,
      anchor == null ? '$_chapter' : '$_chapter|$anchor',
    ).catchError(
      (Object e) => debugPrint('EgwReader: could not save position: $e'),
    );
  }

  /// The opening words of [page], as stored.
  String? _anchorFor(int page) {
    if (page < 0 || page >= _pages.length) return null;
    for (final block in _pages[page].blocks) {
      final text = block.text.trim();
      if (text.isEmpty) continue;
      final cut = text.length < _anchorLength ? text.length : _anchorLength;
      // Newlines would survive into the stored value and break the split on
      // `|`-free reads; the book's own wrapping is not part of the anchor.
      return text.substring(0, cut).replaceAll(RegExp(r'\s+'), ' ');
    }
    return null;
  }

  /// The page [anchor] now falls on, after however the chapter re-measured.
  int _pageForAnchor(String anchor) {
    // First choice: a page that OPENS on those words, which is where the
    // member actually was when the type size has not changed.
    for (var i = 0; i < _pages.length; i++) {
      if (_anchorFor(i) == anchor) return i;
    }
    // The type size or the screen changed, so the cuts moved. The page that
    // CONTAINS the words is the honest answer — it is the same paragraph.
    for (var i = 0; i < _pages.length; i++) {
      final text = _pages[i].blocks
          .map((b) => b.text)
          .join(' ')
          .replaceAll(RegExp(r'\s+'), ' ');
      if (text.contains(anchor)) return i;
    }
    return 0;
  }

  /// Re-measures the chapter when — and only when — the layout it was
  /// measured against has actually changed.
  void _repaginate(Size viewport, double scale) {
    if (viewport.width <= 0 || viewport.height <= 0) return;
    final key = '$_chapter|${viewport.width.round()}x'
        '${viewport.height.round()}|$scale';
    if (key == _pagesKey) return;
    _pagesKey = key;
    _pages = EgwPaginator.paginate(
      chapter: _current,
      chapterIndex: _chapter,
      viewport: viewport,
      bodyStyle: _bodyStyle(scale),
      headingStyle: _headingStyle(scale),
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
    );
    _restoreOrKeepPlace();
  }

  /// Puts the member back where they were — on open, and after a re-measure.
  ///
  /// A type-size change re-cuts the whole chapter under them, and without
  /// this the pager keeps its page NUMBER, which after a re-measure points
  /// at completely different words. Holding the anchor instead means the
  /// paragraph stays put and the pages move around it.
  void _restoreOrKeepPlace() {
    final anchor = _pendingAnchor ?? _anchorFor(_pageIndex.value);
    _pendingAnchor = null;
    if (anchor == null || _pages.isEmpty) return;
    final target = _pageForAnchor(anchor);
    if (target == 0 && _pageIndex.value == 0) return;

    // Everything here waits for the end of the frame. `_repaginate` runs
    // inside `LayoutBuilder`'s builder, so touching a notifier or the
    // controller now would be a markNeedsBuild during build — and on a
    // first open the pager has no clients yet in any case.
    //
    // `jumpToPage`, not `animateTo`: reopening a book should LAND on the
    // page, not scroll to it past forty pages of someone else's reading.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _pageIndex.value = target;
      if (!_pager.hasClients) return;
      if (_pager.page?.round() == target) return;
      _pager.jumpToPage(target);
    });
  }

  /// The two styles pagination measures with. The renderer uses these same
  /// getters — if the two ever drift, pages overflow.
  TextStyle _bodyStyle(double scale) => AppTextStyles.bodyLarge.copyWith(
    fontSize: 17.5 * scale,
    height: 1.62,
    fontWeight: FontWeight.w400,
  );

  TextStyle _headingStyle(double scale) =>
      AppTextStyles.headlineMedium.copyWith(
        fontSize: 24 * scale,
        fontWeight: FontWeight.w700,
        height: 1.25,
      );

  /// A tap toggles the chrome. It does NOT turn the page.
  ///
  /// Founder, 18 Aug 2026: *"remove touching screen then goes to next
  /// page"*. Tapping the outer third used to turn, alongside the swipe.
  /// Two things were wrong with it. It fires on the gesture people make
  /// while READING — resting a thumb, dismissing the keyboard, reaching for
  /// the top bar — so the page jumped on its own; and it is the same
  /// gesture as tapping a sentence to highlight it, which is the next thing
  /// this reader owes him. A tap cannot mean both.
  ///
  /// Swiping still turns, which is what the pagination was built for.
  void _onPointerUp(PointerUpEvent e) {
    final start = _pointerDown;
    _pointerDown = null;
    if (_tapClaimedByText) {
      _tapClaimedByText = false;
      return;
    }
    if (start == null) return;
    // A drag is a swipe or a text selection, not a tap.
    if ((e.position - start).distance > 12) return;

    // A tap on the margin while a quote is open finishes it. The share bar
    // is a mode, and every mode needs a way out that is not a button hunt.
    if (_quote.isNotEmpty) {
      setState(_quote.clear);
      return;
    }

    setState(() => _chromeVisible = !_chromeVisible);
  }

  /// 1-based page within the chapter, clamped so the trailing
  /// end-of-chapter card does not read as "page 13 of 12".
  int _pageNumber(int index) => (index + 1).clamp(1, math.max(1, _pages.length));

  // ---- Build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: EgwReaderPrefs.revision,
      builder: (context, _, _) {
        final theme = EgwReaderPrefs.resolve(context);
        final palette = EgwReadingPalette.of(theme);
        final scale = EgwReaderPrefs.scale();

        return AnnotatedRegion<SystemUiOverlayStyle>(
          // The reading ground is not the app's ground, so the status bar
          // icons have to be told about it — a sepia page under a dark app
          // theme would otherwise get invisible icons. This is the same
          // trap that broke the Watch header when navy went flat.
          value: palette.brightness == Brightness.dark
              ? SystemUiOverlayStyle.light
              : SystemUiOverlayStyle.dark,
          child: Scaffold(
            backgroundColor: palette.page,
            body: SafeArea(
              child: Stack(
                children: [
                  Positioned.fill(child: _page(palette, scale)),
                  if (_chromeVisible) _topBar(palette),
                  // The quote bar REPLACES the bottom chrome while a
                  // statement is picked. Two stacked bars would bury the
                  // Share button the founder asked to be big, and the page
                  // counter is not what anybody is looking at mid-quote.
                  if (_quote.isNotEmpty)
                    _quoteBar(palette)
                  else if (_chromeVisible)
                    _bottomBar(palette),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Horizontal padding of the text column, and the width pagination
  /// measures against. Kept in one place so the measurer and the renderer
  /// cannot drift — if they do, pages overflow.
  static const double _hPad = 24;
  static const double _vPad = 28;

  /// Space held for the chrome bars.
  ///
  /// Reserved ALWAYS, whether the chrome is showing or not. The bars fade
  /// over their own gutter rather than reflowing the text, because
  /// repaginating every time somebody taps the screen would be both slow
  /// and disorienting — the page you were reading would rewrap under you.
  /// The first line used to sit under the top bar for exactly this reason.
  static const double _topChrome = 56;
  static const double _bottomChrome = 60;

  Widget _page(EgwReadingPalette palette, double scale) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // A measured column: full-bleed text is uncomfortable on a phone
        // and unreadable on a tablet.
        final columnWidth =
            (constraints.maxWidth - _hPad * 2).clamp(0.0, 680.0);
        final viewport = Size(
          columnWidth,
          constraints.maxHeight -
              _vPad * 2 -
              _topChrome -
              _bottomChrome,
        );

        _repaginate(viewport, scale);

        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (e) => _pointerDown = e.position,
          onPointerUp: _onPointerUp,
          child: SelectionArea(
            // Selection is what turns a page into a quotable source. The
            // text is captured here rather than read off the menu, because
            // `SelectableRegionState` keeps its selection private and
            // `onSelectionChanged` is the supported way to see it.
            onSelectionChanged: (c) => _selection = c?.plainText ?? '',
            contextMenuBuilder: (context, state) => _quoteMenu(context, state),
            child: PageView.builder(
              controller: _pager,
              // Vertical drags are left alone so text selection still works.
              itemCount: _pages.length + 1,
              onPageChanged: (i) {
                HapticFeedback.selectionClick();
                // NO setState. The only thing that depends on the page
                // number is the counter in the bottom bar, and rebuilding
                // the whole reader — which re-runs `itemBuilder` and
                // rebuilds every span on three live pages — lands in the
                // middle of the fling. See [_pageIndex].
                _pageIndex.value = i;
                _savePosition(i);
              },
              itemBuilder: (context, i) {
                final child = i == _pages.length
                    ? _endOfChapter(palette)
                    : _renderPage(_pages[i], palette, scale, columnWidth);
                // The turn animates a transform over this subtree every
                // frame. Without a boundary the whole page — thousands of
                // laid-out glyphs — is re-rasterised on each of them.
                return _turn(
                  i,
                  constraints.maxWidth,
                  RepaintBoundary(child: child),
                  palette,
                );
              },
            ),
          ),
        );
      },
    );
  }

  /// The page-turn itself (founder, 17 Aug: "like an actual book").
  ///
  /// `PageView` slides both pages sideways, which reads as a carousel, not
  /// a book. So the translation is CANCELLED for every page — each one
  /// stays exactly where it is — and the outgoing page instead rotates
  /// about its left edge, lifting off the one beneath. That is the motion a
  /// paper page actually makes.
  ///
  /// Deliberately driven by the drag rather than played as a fixed
  /// animation: the page is under the finger the whole way, so the motion
  /// costs no time. It is the real act, not a celebration of it.
  ///
  /// **Toned down 18 Aug 2026** — founder: *"the swipe animation is too much
  /// fix tt one or remove it"*. The lift was ~99° of rotation with heavy
  /// perspective, so mid-turn the outgoing page went nearly edge-on and the
  /// text on it sheared into an unreadable wedge every single turn. What
  /// makes it read as paper is the hinge at the left edge and the shading,
  /// not the depth of the angle — so the angle is now shallow and the
  /// shading light. The metaphor survives ("like an actual book", his own
  /// request the day before); the theatre does not.
  Widget _turn(
    int index,
    double width,
    Widget child,
    EgwReadingPalette palette,
  ) {
    return AnimatedBuilder(
      animation: _pager,
      child: child,
      builder: (context, inner) {
        var page = _pager.initialPage.toDouble();
        if (_pager.hasClients && _pager.position.haveDimensions) {
          page = _pager.page ?? page;
        }
        final delta = index - page;

        // Only the two pages either side of the fold are on stage.
        if (delta.abs() > 1.01) return const SizedBox.shrink();

        // Undo PageView's own sliding so the page sits still.
        final pinned = Transform.translate(
          offset: Offset(-delta * width, 0),
          child: inner,
        );

        if (delta > 0) {
          // The page underneath, revealed as the one above lifts. A touch
          // of shade sells the depth without a visible seam.
          final reveal = (1 - delta).clamp(0.0, 1.0);
          return Stack(
            children: [
              pinned,
              Positioned.fill(
                child: IgnorePointer(
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.10 * (1 - reveal)),
                  ),
                ),
              ),
            ],
          );
        }

        final t = (-delta).clamp(0.0, 1.0);
        return Transform(
          alignment: Alignment.centerLeft,
          transform: Matrix4.identity()
            // Perspective — without it the rotation reads as a horizontal
            // squash rather than a page lifting toward you. Shallower than
            // it was, in step with the smaller angle: the two together are
            // what decide how much the text on the moving page distorts.
            ..setEntry(3, 2, 0.0007)
            // ~29°, down from ~99°. At the old angle the outgoing page went
            // close to edge-on and its text sheared into an unreadable
            // wedge on every turn — that is the "too much".
            ..rotateY(-t * math.pi * 0.16),
          child: Stack(
            children: [
              pinned,
              // The turning page darkens as it lifts, which is what makes it
              // read as paper catching the light. Halved with the angle;
              // the shading is now doing most of the work of selling it.
              Positioned.fill(
                child: IgnorePointer(
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.12 * t),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _renderPage(
    EgwPage page,
    EgwReadingPalette palette,
    double scale,
    double columnWidth,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        _hPad,
        _vPad + _topChrome,
        _hPad,
        _vPad + _bottomChrome,
      ),
      child: Center(
        child: SizedBox(
          width: columnWidth,
          // A plain Column, deliberately.
          //
          // A SingleChildScrollView was tried here as an overflow cushion
          // and removed: it puts a second scrollable inside the PageView
          // under one SelectionArea, and the drag-to-select autoscroll then
          // asserts "drag target size is larger than scrollable size".
          //
          // It was also the wrong instinct. Pagination measures the exact
          // spans this paints, with a small margin held back, so a page
          // that does not fit is a MEASUREMENT BUG — and an overflow stripe
          // is how that bug gets noticed instead of silently swallowed.
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final b in page.blocks) _block(b, palette, scale),
            ],
          ),
        ),
      ),
    );
  }

  Widget _block(EgwBlock block, EgwReadingPalette palette, double scale) {
    if (block.kind == EgwBlockKind.heading) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 22, top: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              block.text.trim(),
              style: AppTextStyles.headlineMedium.copyWith(
                color: palette.text,
                fontSize: 24 * scale,
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 14),
            Container(width: 44, height: 2, color: palette.accent),
          ],
        ),
      );
    }

    final isQuote = block.kind == EgwBlockKind.blockquote;
    final isVerse = block.kind == EgwBlockKind.verse;

    // Text.rich, NOT SelectableText.rich: the whole page is already wrapped
    // in a SelectionArea, which makes ordinary Text selectable. Nesting a
    // SelectableText inside it double-handles the gesture — it swallows the
    // tap, so tapping the words did nothing while tapping the margin
    // toggled the chrome. A reader has to respond to a tap anywhere.
    final body = Text.rich(
      TextSpan(children: _inline(block, palette, scale)),
      style: AppTextStyles.bodyLarge.copyWith(
        color: palette.text,
        // 17.5 at 1.0 — a book measure, not a UI label. Leading is 1.62,
        // which is what long-form reading wants; the app's default 1.4 is
        // tuned for short strings.
        fontSize: 17.5 * scale,
        height: 1.62,
        fontWeight: FontWeight.w400,
      ),
      textAlign: isVerse ? TextAlign.center : TextAlign.left,
    );

    // Founder, 18 Aug 2026: *"when click text in egw it should highlight a
    // statement from were it starts to where it end n u can hight many
    // statements"*. A tap lands on a paragraph, so the paragraph is what
    // handles it — the surrounding page keeps the chrome toggle.
    //
    // `Builder` rather than a GlobalKey: its context resolves to the
    // Text.rich's own RenderParagraph, which is the thing that can turn a
    // touch point into a character offset. Minting GlobalKeys per block
    // would be one per paragraph per page, and two identical paragraphs in
    // a chapter would collide.
    final tappable = Builder(
      builder: (ctx) => GestureDetector(
        onTapUp: (details) => _highlightSentenceAt(ctx, block, details),
        child: body,
      ),
    );

    return Padding(
      padding: EdgeInsets.only(
        bottom: isVerse ? 18 : 16,
        left: isQuote ? 18 : 0,
      ),
      child: isQuote
          ? Container(
              padding: const EdgeInsets.only(left: 16),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: palette.accent, width: 2.5),
                ),
              ),
              child: tappable,
            )
          : tappable,
    );
  }

  /// Turns a tap inside a paragraph into a highlighted statement.
  ///
  /// Tapping a sentence that is already highlighted removes it, so the
  /// gesture that made a highlight is the one that takes it away.
  void _highlightSentenceAt(
    BuildContext ctx,
    EgwBlock block,
    TapUpDetails details,
  ) {
    final render = _paragraphUnder(ctx.findRenderObject());
    if (render == null) return;

    final local = render.globalToLocal(details.globalPosition);
    if (!(Offset.zero & render.size).contains(local)) return;

    final painted = render.getPositionForOffset(local).offset;
    final offset = _blockOffsetOf(block, painted);
    final range = EgwHighlights.sentenceAt(block.text, offset);
    final sentence = block.text.substring(range.start, range.end).trim();
    if (sentence.length < 3) return;

    _tapClaimedByText = true;
    HapticFeedback.selectionClick();

    final picked = _Picked(
      text: sentence,
      // Where it sits in the chapter, so several statements share out into
      // reading order however they were tapped. Taps come in whatever order
      // the eye finds them; a quote has to read top to bottom.
      blockStart: _blockStartInChapter(block),
      offset: range.start,
    );

    final already = _quote.indexWhere((p) => p.text == sentence);
    if (already >= 0) {
      // Tapping a picked statement drops it — the gesture that made the
      // highlight is the one that takes it away.
      _quote.removeAt(already);
      EgwHighlights.remove(widget.bookId, _current.id, sentence);
      setState(() {});
      return;
    }

    // Tapping a statement highlighted in an EARLIER session re-opens it as
    // the live quote rather than deleting it out from under a tap that was
    // almost certainly meant as "share this one".
    if (EgwHighlights.has(widget.bookId, _current.id, sentence) &&
        _quote.isEmpty) {
      setState(() => _quote.add(picked));
      return;
    }

    EgwHighlights.add(widget.bookId, _current.id, sentence);
    setState(() {
      _quote
        ..add(picked)
        ..sort();
      // The share bar takes the bottom of the screen; the chrome would sit
      // under it.
      _chromeVisible = false;
    });
  }

  /// Where [block] starts within the chapter, in characters.
  ///
  /// A page's blocks may be SLICES of the chapter's, so identity does not
  /// work here and neither does an index. Matching on the text does, and it
  /// is only ever run on a tap.
  int _blockStartInChapter(EgwBlock block) {
    final needle = block.text;
    var at = 0;
    for (final b in _current.blocks) {
      final index = b.text.indexOf(needle);
      if (index >= 0) return at + index;
      at += b.text.length;
    }
    return at;
  }

  /// The picked statements as one quotable passage.
  String get _quoteText => _quote.map((p) => p.text).join(' ');

  void _shareQuoteBar() {
    final text = _quoteText.trim();
    if (text.isEmpty) return;
    _shareQuote(text);
  }

  Future<void> _copyQuote() async {
    final text = _quoteText.trim();
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: '"$text"\n— ${_citation()}'));
    if (!mounted) return;
    HapticFeedback.selectionClick();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Quote copied'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  /// Un-highlights everything in the live quote and closes the bar.
  void _clearQuote({bool unhighlight = false}) {
    if (unhighlight) {
      for (final p in _quote) {
        EgwHighlights.remove(widget.bookId, _current.id, p.text);
      }
    }
    setState(() {
      _quote.clear();
      _chromeVisible = true;
    });
  }

  /// The paragraph painted somewhere beneath [node].
  ///
  /// The tap handler's own context does NOT resolve to the paragraph:
  /// `GestureDetector` has a render object of its own, so
  /// `findRenderObject()` stops there. Descending is also what keeps this
  /// working for a blockquote, where the text sits inside a decorated
  /// `Container` rather than directly under the detector.
  RenderParagraph? _paragraphUnder(RenderObject? node) {
    if (node == null) return null;
    if (node is RenderParagraph) return node;
    RenderParagraph? found;
    node.visitChildren((child) {
      found ??= _paragraphUnder(child);
    });
    return found;
  }

  /// Maps an offset in the PAINTED paragraph back to one in [block]`.text`.
  ///
  /// The two are not the same string. A page anchor contributes no
  /// characters to `block.text` (its span's text is empty) but is painted as
  /// a `WidgetSpan`, and a WidgetSpan occupies one character position in the
  /// paragraph. So every page number a paragraph carries shifts painted
  /// offsets one further along than the source — and a sentence picked with
  /// the raw offset would start a word or two late, on exactly the
  /// paragraphs that carry a page break.
  int _blockOffsetOf(EgwBlock block, int painted) {
    var inPainted = 0;
    var inBlock = 0;
    for (final span in block.spans) {
      if (span.isPageMarker) {
        if (painted <= inPainted) return inBlock;
        inPainted += 1;
        continue;
      }
      if (painted < inPainted + span.text.length) {
        return inBlock + (painted - inPainted);
      }
      inPainted += span.text.length;
      inBlock += span.text.length;
    }
    return inBlock;
  }

  /// Inline runs, including the two things the EPUB marks up for us, plus
  /// any highlight wash over them.
  List<InlineSpan> _inline(
    EgwBlock block,
    EgwReadingPalette palette,
    double scale,
  ) {
    // Highlights are matched by TEXT, so they are resolved against the
    // block's own string and then mapped back onto the spans. See
    // EgwHighlights for why offsets would not survive repagination.
    final passages = EgwHighlights.forChapter(widget.bookId, _current.id);
    final ranges = passages.isEmpty
        ? const <({int start, int end})>[]
        : EgwHighlights.rangesIn(block.text, passages);

    final out = <InlineSpan>[];
    var cursor = 0;

    /// Emits [text] split at highlight boundaries, so a highlight can start
    /// or end mid-span without the wash covering the whole run.
    void emit(String text, TextStyle? style) {
      if (text.isEmpty) return;
      if (ranges.isEmpty) {
        out.add(TextSpan(text: text, style: style));
        cursor += text.length;
        return;
      }
      final start = cursor;
      final end = cursor + text.length;
      var at = start;
      while (at < end) {
        final hit = ranges.firstWhere(
          (r) => r.end > at && r.start < end,
          orElse: () => (start: -1, end: -1),
        );
        if (hit.start < 0) {
          out.add(TextSpan(text: text.substring(at - start), style: style));
          break;
        }
        if (hit.start > at) {
          out.add(TextSpan(
            text: text.substring(at - start, hit.start - start),
            style: style,
          ));
          at = hit.start;
        }
        final stop = hit.end < end ? hit.end : end;
        out.add(TextSpan(
          text: text.substring(at - start, stop - start),
          style: (style ?? const TextStyle())
              .copyWith(backgroundColor: palette.highlight),
        ));
        at = stop;
      }
      cursor = end;
    }

    for (final span in block.spans) {
      // Page anchors become a quiet marginal number, NOT "[18]" inline.
      // Keeping the bracketed artefact in the sentence is half of what
      // made the old reader feel like a scan.
      if (span.isPageMarker) {
        out.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: Text(
                '${span.page}',
                style: AppTextStyles.labelSmall.copyWith(
                  color: palette.muted.withValues(alpha: 0.55),
                  fontSize: 10.5 * scale,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        );
        continue;
      }

      if (span.scriptureRef != null) {
        emit(
          span.text,
          TextStyle(
            color: palette.accent,
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.underline,
            decorationColor: palette.accent.withValues(alpha: 0.35),
          ),
        );
        continue;
      }

      emit(
        span.text,
        span.italic ? const TextStyle(fontStyle: FontStyle.italic) : null,
      );
    }
    return out;
  }

  /// Adds "Share quote" to the selection menu — the reason selection is
  /// enabled at all.
  Widget _quoteMenu(BuildContext context, SelectableRegionState state) {
    final selected = _selection;
    final already =
        EgwHighlights.has(widget.bookId, _current.id, selected);

    final items = <ContextMenuButtonItem>[
      ...state.contextMenuButtonItems,
      ContextMenuButtonItem(
        // Toggles, so removing a highlight is the same gesture that made
        // it — selecting it again and tapping the same button.
        label: already ? 'Remove highlight' : 'Highlight',
        onPressed: () {
          ContextMenuController.removeAny();
          state.clearSelection();
          if (selected.trim().isEmpty) return;
          if (already) {
            EgwHighlights.remove(widget.bookId, _current.id, selected);
          } else {
            EgwHighlights.add(widget.bookId, _current.id, selected);
          }
          setState(() {});
        },
      ),
      ContextMenuButtonItem(
        label: 'Share quote',
        onPressed: () {
          ContextMenuController.removeAny();
          state.clearSelection();
          if (selected.trim().isEmpty) return;
          _shareQuote(selected);
        },
      ),
    ];
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: state.contextMenuAnchors,
      buttonItems: items,
    );
  }

  /// Where a quote taken right now comes from, in citable form.
  ///
  /// The canonical printed page is the whole reason the EPUB was chosen over
  /// the PDF, and it is read off the page ON SCREEN rather than the chapter
  /// — a chapter runs twenty printed pages, so citing its first one is wrong
  /// for all but the opening screen. Falls back to the chapter when a book
  /// carries no page anchors at all; the twelve daily devotionals are
  /// organised by date and have none.
  String _citation() {
    final index = _pageIndex.value;
    final page = (index >= 0 && index < _pages.length)
        ? _pages[index].printedPage ?? _current.startPage
        : _current.startPage;
    return page != null
        ? '${widget.book.title}, p. $page'
        : '${widget.book.title} — ${_current.title}';
  }

  void _shareQuote(String text) {
    VerseShareSheet.open(
      context,
      reference: _citation(),
      text: text.trim(),
      attribution: widget.book.author ?? 'Ellen G. White',
    );
  }

  Widget _endOfChapter(EgwReadingPalette palette) {
    final hasNext = _chapter < widget.book.chapters.length - 1;
    return Padding(
      padding: const EdgeInsets.only(top: 26, bottom: 40),
      child: Column(
        children: [
          Container(width: 60, height: 1, color: palette.rule),
          const SizedBox(height: 22),
          if (hasNext)
            TextButton(
              onPressed: () => _goTo(_chapter + 1),
              child: Text(
                'Next — ${widget.book.chapters[_chapter + 1].title}',
                textAlign: TextAlign.center,
                style: AppTextStyles.labelMedium.copyWith(
                  color: palette.accent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          else
            Text(
              'End of ${widget.book.title}',
              style: AppTextStyles.labelMedium.copyWith(color: palette.muted),
            ),
        ],
      ),
    );
  }

  // ---- Chrome ---------------------------------------------------------------

  Widget _topBar(EgwReadingPalette palette) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        color: palette.page.withValues(alpha: 0.96),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          children: [
            IconButton(
              icon: Icon(Icons.arrow_back, color: palette.text),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: Text(
                widget.book.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.labelMedium.copyWith(
                  color: palette.text,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Contents',
              icon: Icon(Icons.list_rounded, color: palette.text),
              onPressed: _openContents,
            ),
            IconButton(
              tooltip: 'Reading settings',
              icon: Icon(Icons.text_fields_rounded, color: palette.text),
              onPressed: _openSettings,
            ),
          ],
        ),
      ),
    );
  }

  Widget _bottomBar(EgwReadingPalette palette) {
    final total = widget.book.chapters.length;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        color: palette.page.withValues(alpha: 0.96),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
        child: Row(
          children: [
            IconButton(
              icon: Icon(Icons.chevron_left_rounded, color: palette.text),
              onPressed: _chapter > 0 ? () => _goTo(_chapter - 1) : null,
            ),
            // Page position FIRST, then the chapter title.
            //
            // The title is long in these books ("Chapter 2—The Sinner's
            // Need of Christ") and ellipsis ate the counter entirely when
            // it came second. Position is the half worth keeping: it is the
            // sense of place a scrollbar never gives, and the reason
            // pagination is worth the work at all.
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // The one thing on screen that follows the page, and the
                  // only reason `onPageChanged` needs to notify anything.
                  ValueListenableBuilder<int>(
                    valueListenable: _pageIndex,
                    builder: (context, index, _) => Text(
                      _pages.isEmpty
                          ? 'Chapter ${_chapter + 1} of $total'
                          : 'Page ${_pageNumber(index)} of ${_pages.length}',
                      maxLines: 1,
                      style: AppTextStyles.labelSmall.copyWith(
                        color: palette.text,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    _current.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.labelSmall.copyWith(
                      color: palette.muted,
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(Icons.chevron_right_rounded, color: palette.text),
              onPressed:
                  _chapter < total - 1 ? () => _goTo(_chapter + 1) : null,
            ),
          ],
        ),
      ),
    );
  }

  /// The share bar — what a tap on a statement actually opens.
  ///
  /// Founder, 18 Aug 2026: *"the moment i click the text should highlight n
  /// there a big a share button to share image or text of the qoute"*. So
  /// Share is a full-width primary button, not a menu item: it is the whole
  /// reason to pick a statement, and it was previously two gestures and a
  /// long-press menu away.
  ///
  /// The bar stays up while more statements are tapped, and says how many
  /// are in — that is the "highlight more sentences" half, and the count is
  /// what tells the member the taps are accumulating rather than replacing.
  Widget _quoteBar(EgwReadingPalette palette) {
    final count = _quote.length;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        decoration: BoxDecoration(
          color: palette.page,
          border: Border(top: BorderSide(color: palette.rule)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 18,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.format_quote_rounded,
                    size: 17,
                    color: palette.accent,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      count == 1
                          ? '1 statement · tap another to add it'
                          : '$count statements picked',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.labelSmall.copyWith(
                        color: palette.muted,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => _clearQuote(unhighlight: true),
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      child: Text(
                        'Unhighlight',
                        style: AppTextStyles.labelSmall.copyWith(
                          color: palette.muted,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _quoteText,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodySmall.copyWith(
                  color: palette.text,
                  height: 1.4,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: FilledButton.icon(
                        onPressed: _shareQuoteBar,
                        style: FilledButton.styleFrom(
                          backgroundColor: palette.accent,
                          foregroundColor: palette.page,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: const Icon(Icons.ios_share_rounded, size: 19),
                        label: Text(
                          'Share quote',
                          style: AppTextStyles.labelLarge.copyWith(
                            color: palette.page,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _quoteAction(
                    palette,
                    icon: Icons.copy_rounded,
                    tooltip: 'Copy',
                    onTap: _copyQuote,
                  ),
                  const SizedBox(width: 8),
                  _quoteAction(
                    palette,
                    icon: Icons.close_rounded,
                    tooltip: 'Done',
                    // Keeps the highlights, closes the bar. Removing them is
                    // "Unhighlight" above — a member who has just marked
                    // four statements must not lose them to the X.
                    onTap: () => _clearQuote(),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _quoteAction(
    EgwReadingPalette palette, {
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 26,
        child: Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: palette.rule),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, size: 20, color: palette.text),
        ),
      ),
    );
  }

  void _openContents() {
    final palette = EgwReadingPalette.of(EgwReaderPrefs.resolve(context));
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: palette.page,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: widget.book.chapters.length,
          itemBuilder: (context, i) {
            final c = widget.book.chapters[i];
            final selected = i == _chapter;
            return ListTile(
              selected: selected,
              title: Text(
                c.title,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: selected ? palette.accent : palette.text,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              trailing: c.startPage == null
                  ? null
                  : Text(
                      'p. ${c.startPage}',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: palette.muted,
                      ),
                    ),
              onTap: () {
                Navigator.of(context).pop();
                _goTo(i);
              },
            );
          },
        ),
      ),
    );
  }

  void _openSettings() {
    showModalBottomSheet<void>(
      context: context,
      // Transparent, because the sheet paints its OWN ground from the
      // current setting. A colour passed here is evaluated once, when the
      // sheet opens, and never again — so tapping Sepia left the sheet
      // exactly as it was. The sheet covers the bottom of the screen and a
      // scrim dims the rest, so with the sheet frozen there was almost
      // nothing left on screen to show the tap had registered.
      backgroundColor: Colors.transparent,
      builder: (_) => const _ReaderSettingsSheet(),
    );
  }
}

/// One statement in the live quote, and where it sits in the chapter.
///
/// Ordered by position, not by the order it was tapped: somebody picking
/// three statements will not always work down the page, and a quote that
/// reads out of order is worse than no quote at all.
@immutable
class _Picked implements Comparable<_Picked> {
  const _Picked({
    required this.text,
    required this.blockStart,
    required this.offset,
  });

  final String text;

  /// Character position of the containing block within the chapter.
  final int blockStart;

  /// Character position of the statement within that block.
  final int offset;

  @override
  int compareTo(_Picked other) =>
      (blockStart + offset).compareTo(other.blockStart + other.offset);
}

/// Type size and reading ground. Applies live — the sheet AND the page
/// behind it both rebuild from `EgwReaderPrefs.revision`, so a change shows
/// on the next frame rather than after the sheet is dismissed.
///
/// Stateless on purpose. It used to `await` the write and then `setState`,
/// which meant a slow disk froze the controls themselves: the swatch border
/// and the slider thumb only moved once storage had caught up, so the sheet
/// looked as dead as the page did.
class _ReaderSettingsSheet extends StatelessWidget {
  const _ReaderSettingsSheet();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: EgwReaderPrefs.revision,
      builder: (context, _, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final theme = EgwReaderPrefs.resolve(context);
    final palette = EgwReadingPalette.of(theme);
    final scale = EgwReaderPrefs.scale();

    return Material(
      // The sheet's own ground follows the choice, so tapping a swatch
      // changes something the finger is still resting on.
      color: palette.page,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'TEXT SIZE',
                style: AppTextStyles.labelSmall.copyWith(
                  color: palette.muted,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                ),
              ),
              Row(
                children: [
                  Icon(Icons.text_fields, size: 16, color: palette.muted),
                  Expanded(
                    child: Slider(
                      value: scale,
                      min: EgwReaderPrefs.minScale,
                      max: EgwReaderPrefs.maxScale,
                      divisions: 8,
                      activeColor: palette.accent,
                      // Synchronous, so the thumb stays under the finger
                      // and the page reflows as it moves. The rebuild comes
                      // from `revision`, which the setter bumps before it
                      // goes anywhere near storage.
                      onChanged: EgwReaderPrefs.setScale,
                    ),
                  ),
                  Icon(Icons.text_fields, size: 26, color: palette.muted),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'PAGE',
                style: AppTextStyles.labelSmall.copyWith(
                  color: palette.muted,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  for (final t in EgwReadingTheme.values)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: _ThemeSwatch(
                          theme: t,
                          selected: t == theme,
                          onTap: () => EgwReaderPrefs.setTheme(t),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({
    required this.theme,
    required this.selected,
    required this.onTap,
  });

  final EgwReadingTheme theme;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = EgwReadingPalette.of(theme);
    final label = switch (theme) {
      EgwReadingTheme.day => 'Day',
      EgwReadingTheme.sepia => 'Sepia',
      EgwReadingTheme.night => 'Night',
    };
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: p.page,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? p.accent : p.rule,
            width: selected ? 2 : 1,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: AppTextStyles.labelMedium.copyWith(
              color: p.text,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
