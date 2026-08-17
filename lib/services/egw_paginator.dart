import 'package:flutter/material.dart';

import '../models/egw_book_model.dart';

/// One screen of a book.
@immutable
class EgwPage {
  const EgwPage({required this.blocks, required this.chapterIndex});

  final List<EgwBlock> blocks;
  final int chapterIndex;

  /// Printed page number in force on this screen, for citing a quote.
  int? get printedPage {
    for (final b in blocks) {
      for (final s in b.spans) {
        if (s.page != null) return s.page;
      }
    }
    return null;
  }
}

/// Splits chapters into screen-sized pages so the reader can TURN pages
/// rather than scroll (founder, 17 Aug: "like an actual book").
///
/// Scrolling is the thing that makes a long-form reader feel like a web
/// page. Pagination is also what lets the reader say "4 of 12" — a real
/// sense of place, which a scrollbar never gives.
///
/// ## How it measures
///
/// Blocks are packed greedily until the next one would overflow the
/// viewport. A block that is taller than a whole page on its own is split
/// on a LINE boundary using [TextPainter]'s line metrics, so a paragraph
/// breaks the way it would in print rather than being pushed whole onto the
/// next page and leaving a half-empty one.
///
/// Measurement uses the same styles the reader renders with. If the two
/// ever drift, pages will overflow — so the reader passes its styles in
/// rather than either side hardcoding them.
class EgwPaginator {
  EgwPaginator._();

  /// Non-text vertical space each block occupies, mirroring EXACTLY what
  /// the reader renders around it.
  ///
  /// These must match `_block` in egw_reader_screen.dart. When they drifted
  /// by ten pixels — the heading's rule and its gaps were under-counted —
  /// every page carrying a chapter heading overflowed by exactly ten.
  ///
  ///   heading: top 8 + gap 14 + rule 2 + bottom 22 = 46
  ///   verse:   bottom 18
  ///   others:  bottom 16
  static double gapAfter(EgwBlockKind kind) => switch (kind) {
    EgwBlockKind.heading => 46,
    EgwBlockKind.verse => 18,
    _ => 16,
  };

  /// Slack held back from the measured viewport.
  ///
  /// Layout rounds and a rendered line box can land a fraction above the
  /// painter's measurement, so packing to the exact pixel produces
  /// occasional one-off overflows. Costing a few pixels of page is far
  /// cheaper than a yellow-and-black stripe across somebody's book.
  static const double safetyMargin = 8;

  static List<EgwPage> paginate({
    required EgwChapter chapter,
    required int chapterIndex,
    required Size viewport,
    required TextStyle bodyStyle,
    required TextStyle headingStyle,
    required double devicePixelRatio,
  }) {
    final usable = Size(
      viewport.width,
      (viewport.height - safetyMargin).clamp(1.0, viewport.height),
    );
    viewport = usable;

    final pages = <EgwPage>[];
    var current = <EgwBlock>[];
    var used = 0.0;

    void flush() {
      if (current.isEmpty) return;
      pages.add(EgwPage(blocks: current, chapterIndex: chapterIndex));
      current = <EgwBlock>[];
      used = 0.0;
    }

    for (final block in chapter.blocks) {
      final style =
          block.kind == EgwBlockKind.heading ? headingStyle : bodyStyle;
      // A blockquote is inset, so it measures against a narrower column.
      final width = block.kind == EgwBlockKind.blockquote
          ? viewport.width - 34
          : viewport.width;
      final gap = gapAfter(block.kind);

      final painter = _paint(block, style, width, devicePixelRatio);
      final height = painter.height;

      if (used + height + gap <= viewport.height) {
        current.add(block);
        used += height + gap;
        continue;
      }

      // Does the whole block fit on a page of its own? Then start a new one.
      if (height + gap <= viewport.height) {
        flush();
        current.add(block);
        used = height + gap;
        continue;
      }

      // Taller than a page: cut it on line boundaries.
      //
      // Written as a loop that provably terminates: each pass either
      // consumes at least one line of text, or flushes to a full-height
      // page exactly once and retries. The earlier version mutated the
      // line list while iterating it and could spin.
      var offset = 0;
      var available = viewport.height - used;

      while (offset < block.text.length) {
        final rest = block.slice(offset, block.text.length);
        final restPainter = _paint(rest, style, width, devicePixelRatio);

        if (restPainter.height + gap <= available) {
          current.add(rest);
          used = (viewport.height - available) + restPainter.height + gap;
          break;
        }

        // How many characters fit in what is left of this page?
        var top = 0.0;
        var cut = 0;
        for (final line in restPainter.computeLineMetrics()) {
          if (top + line.height > available) break;
          top += line.height;
          cut = restPainter
              .getPositionForOffset(Offset(width, top - line.height / 2))
              .offset;
        }

        if (cut <= 0) {
          // Not even one line fits in the remainder. Start a fresh page —
          // but only once; if a whole page cannot hold a single line the
          // viewport is degenerate and we stop rather than spin.
          if (available >= viewport.height) break;
          flush();
          available = viewport.height;
          continue;
        }

        current.add(rest.slice(0, cut));
        offset += cut;
        flush();
        available = viewport.height;
      }
    }

    flush();
    // A chapter always has at least one page, even an empty one, so the
    // pager never has a zero-length range to index into.
    if (pages.isEmpty) {
      pages.add(EgwPage(blocks: const [], chapterIndex: chapterIndex));
    }
    return pages;
  }

  /// Measures a block the way the reader actually paints it.
  ///
  /// Crucially this includes the printed-page markers. The reader renders
  /// each one as an inline number with padding either side, and measuring
  /// the block as plain text ignored them entirely — enough to push a line
  /// the measurer never accounted for, which overflowed the page.
  static TextPainter _paint(
    EgwBlock block,
    TextStyle style,
    double width,
    double dpr,
  ) {
    final markerStyle = style.copyWith(
      fontSize: (style.fontSize ?? 17.5) * 0.6,
      fontWeight: FontWeight.w600,
    );
    final painter = TextPainter(
      text: TextSpan(
        style: style,
        children: [
          for (final s in block.spans)
            if (s.isPageMarker)
              // Mirrors the WidgetSpan's 5px padding either side.
              TextSpan(text: '  ${s.page}  ', style: markerStyle)
            else
              TextSpan(text: s.text),
        ],
      ),
      textDirection: TextDirection.ltr,
      textAlign:
          block.kind == EgwBlockKind.verse ? TextAlign.center : TextAlign.left,
      textScaler: TextScaler.noScaling,
    )..layout(maxWidth: width);
    return painter;
  }
}
