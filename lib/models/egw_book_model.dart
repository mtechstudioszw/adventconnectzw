import 'package:flutter/foundation.dart';

/// A parsed EGW book: chapters of styled paragraphs, ready to lay out with
/// the app's own text widgets.
///
/// Deliberately NOT html. The reader renders these with `Text`/`TextSpan`
/// so it gets Poppins, real Day/Sepia/Night themes, selection handles for
/// highlighting and full control of line height — which is what "stop
/// feeling like a PDF" actually means. A generic HTML widget would fight
/// all four.
@immutable
class EgwBook {
  const EgwBook({
    required this.title,
    required this.author,
    required this.chapters,
  });

  final String title;
  final String? author;
  final List<EgwChapter> chapters;

  bool get isEmpty => chapters.isEmpty;
}

@immutable
class EgwChapter {
  const EgwChapter({
    required this.id,
    required this.title,
    required this.blocks,
  });

  /// The spine id / source filename, used as a stable anchor for bookmarks
  /// and highlights. Survives a re-parse; a list index would not.
  final String id;

  final String title;
  final List<EgwBlock> blocks;

  /// First printed page number appearing in this chapter, if any.
  int? get startPage {
    for (final b in blocks) {
      for (final s in b.spans) {
        if (s.page != null) return s.page;
      }
    }
    return null;
  }
}

/// What a block of text IS, which decides how it is set.
enum EgwBlockKind {
  /// Chapter title.
  heading,

  /// Ordinary body paragraph.
  paragraph,

  /// Indented/offset quotation.
  blockquote,

  /// Centred poem or hymn line — the EGW books use these often.
  verse,
}

@immutable
class EgwBlock {
  const EgwBlock({required this.kind, required this.spans});

  final EgwBlockKind kind;
  final List<EgwSpan> spans;

  /// The block's text with no markup, for search, sharing and quote cards.
  String get text => spans.map((s) => s.text).join();

  bool get isBlank => text.trim().isEmpty;

  /// The character range `[start, end)` of this block, as a block.
  ///
  /// Needed because a paginated reader must be able to break a paragraph
  /// across a page boundary — a real book does, and refusing to would leave
  /// half-empty pages whenever a long paragraph did not fit.
  ///
  /// Page markers are kept when their position falls inside the range, so a
  /// quote taken from the second half of a split paragraph still cites the
  /// right printed page.
  EgwBlock slice(int start, int end) {
    final out = <EgwSpan>[];
    var cursor = 0;
    for (final span in spans) {
      // Zero-width markers belong to the slice that contains their position.
      if (span.text.isEmpty) {
        if (cursor >= start && cursor <= end) out.add(span);
        continue;
      }
      final spanStart = cursor;
      final spanEnd = cursor + span.text.length;
      cursor = spanEnd;
      if (spanEnd <= start || spanStart >= end) continue;

      final from = (start - spanStart).clamp(0, span.text.length);
      final to = (end - spanStart).clamp(0, span.text.length);
      if (to <= from) continue;
      out.add(EgwSpan(
        text: span.text.substring(from, to),
        scriptureRef: span.scriptureRef,
        page: span.page,
        italic: span.italic,
      ));
    }
    return EgwBlock(kind: kind, spans: out);
  }
}

/// One run of text inside a block.
@immutable
class EgwSpan {
  const EgwSpan({
    required this.text,
    this.scriptureRef,
    this.page,
    this.italic = false,
  });

  final String text;

  /// Set when this run is a scripture citation the source already tagged,
  /// e.g. `Colossians 2:3`. The reader makes these tappable into the app's
  /// own Bible tab — the markup is in the EPUB, so this costs nothing.
  final String? scriptureRef;

  /// Set when this run marks the start of a printed page.
  ///
  /// This is the single most valuable thing the EPUB carries. A quote is
  /// worthless without a citation, and these are the CANONICAL page
  /// numbers — the ones every other Ellen White edition uses — so a shared
  /// card can say "Steps to Christ, p. 18" and be right.
  final int? page;

  final bool italic;

  /// Page markers carry no readable text of their own.
  bool get isPageMarker => page != null && text.isEmpty;
}
