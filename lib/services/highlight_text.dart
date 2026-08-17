/// The text half of highlighting, shared by both readers.
///
/// Extracted from `EgwHighlights` when Sabbath School gained highlighting
/// (19 Aug 2026). The two stores are deliberately different — EGW's is
/// device-local, Sabbath School's follows the account — but *where a
/// statement begins and ends*, and *where a stored passage sits in the text
/// on screen*, are the same questions with the same answers. A second copy
/// of these rules would drift, and the sentence rule in particular is the
/// part most likely to be quietly wrong.
///
/// Pure functions, no storage, no Flutter.
library;

class HighlightText {
  HighlightText._();

  /// The sentence surrounding [offset] in [text], as `[start, end)`.
  ///
  /// Founder, 18 Aug 2026: *"when click text in egw it should highlight a
  /// statement from were it starts to where it end"*.
  ///
  /// Splitting on `.` alone is wrong for this material. Both shelves are
  /// dense with initials (E. G. White), abbreviations (Mrs., vol., p.) and
  /// verse references (Col. 2:3) — and a rule that breaks on every period
  /// highlights two words and looks broken. So a terminator only ends a
  /// sentence when what FOLLOWS it looks like a new one: whitespace, then a
  /// capital or an opening quote. That single test handles all three cases
  /// without a dictionary of abbreviations to maintain.
  ///
  /// Returns the whole of [text] when it holds no sentence break at all,
  /// which is the right answer for a one-line quotation rather than a
  /// reason to do nothing.
  static ({int start, int end}) sentenceAt(String text, int offset) {
    if (text.isEmpty) return (start: 0, end: 0);
    final at = offset.clamp(0, text.length - 1);

    /// One past the terminator at [i], including anything that closes it.
    int after(int i) {
      var e = i + 1;
      while (e < text.length && _isCloser(text[e])) {
        e++;
      }
      return e;
    }

    var start = 0;
    for (var i = at - 1; i >= 0; i--) {
      if (_endsSentenceAt(text, i)) {
        start = after(i);
        break;
      }
    }

    var end = text.length;
    for (var i = at; i < text.length; i++) {
      if (_endsSentenceAt(text, i)) {
        end = after(i);
        break;
      }
    }

    // Leading whitespace belongs to the gap between statements, not to the
    // statement itself.
    while (start < end && _isSpace(text.codeUnitAt(start))) {
      start++;
    }
    return (start: start, end: end);
  }

  /// Is the character at [i] the last one of a sentence?
  static bool _endsSentenceAt(String text, int i) {
    final c = text[i];
    if (c != '.' && c != '!' && c != '?') return false;

    // An initial — "E. G. White". A single letter standing alone before the
    // stop is never the end of a statement, and this material is full of
    // them. It is also the one case the "followed by a capital" test below
    // cannot catch, since an initial IS followed by a capital.
    if (c == '.' && i >= 1) {
      final prev = text[i - 1];
      final isLetter = prev.toUpperCase() != prev.toLowerCase();
      final standsAlone = i == 1 || _isSpace(text.codeUnitAt(i - 2));
      if (isLetter && standsAlone) return false;
    }

    // Run past a closing quote or bracket: `he said "go."` ends after the
    // quote mark, not before it.
    var j = i + 1;
    while (j < text.length && _isCloser(text[j])) {
      j++;
    }
    if (j >= text.length) return true;
    if (!_isSpace(text.codeUnitAt(j))) return false;

    while (j < text.length && _isSpace(text.codeUnitAt(j))) {
      j++;
    }
    if (j >= text.length) return true;
    final next = text[j];
    // A capital or an opening quote starts the next statement. A lowercase
    // letter or a digit means the period was an abbreviation or a
    // reference, and the statement runs on.
    return next == next.toUpperCase() && next != next.toLowerCase() ||
        _isOpener(next);
  }

  /// Character ranges of [text] that fall inside a highlighted passage.
  ///
  /// Returned sorted and merged, so overlapping highlights paint as one
  /// wash rather than stacking their alpha into a darker band.
  static List<({int start, int end})> rangesIn(
    String text,
    Iterable<String> passages,
  ) {
    final found = <({int start, int end})>[];
    for (final passage in passages) {
      if (passage.isEmpty) continue;
      var from = 0;
      var hit = false;
      while (true) {
        final at = text.indexOf(passage, from);
        if (at < 0) break;
        hit = true;
        found.add((start: at, end: at + passage.length));
        from = at + passage.length;
      }
      // Passages are stored with their whitespace COLLAPSED, because a
      // dragged selection arrives wrapped exactly as it was on screen. The
      // source text keeps its own line breaks and double spaces, so a plain
      // indexOf can miss a passage that is genuinely there — the highlight
      // then stores fine and simply never paints, which is
      // indistinguishable from the feature not working.
      if (!hit) found.addAll(_loosely(text, passage));
    }
    if (found.isEmpty) return const [];

    found.sort((a, b) => a.start.compareTo(b.start));
    final merged = <({int start, int end})>[found.first];
    for (final r in found.skip(1)) {
      final last = merged.last;
      if (r.start <= last.end) {
        merged[merged.length - 1] = (
          start: last.start,
          end: r.end > last.end ? r.end : last.end,
        );
      } else {
        merged.add(r);
      }
    }
    return merged;
  }

  /// Finds [passage] in [text] allowing any run of whitespace to stand in
  /// for the single spaces the stored passage was collapsed to. Ranges are
  /// into the ORIGINAL [text].
  static Iterable<({int start, int end})> _loosely(
    String text,
    String passage,
  ) {
    final words = passage.split(' ').where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return const [];
    final pattern = words.map(RegExp.escape).join(r'\s+');
    try {
      return RegExp(pattern)
          .allMatches(text)
          .map((m) => (start: m.start, end: m.end));
    } catch (_) {
      // A passage long enough to blow the regex engine is not worth failing
      // a page render over.
      return const [];
    }
  }

  /// Collapses whitespace so a passage selected across a line break matches
  /// the text the reader renders. Selection returns what was on screen,
  /// wrapping included.
  static String clean(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

  static bool _isSpace(int c) =>
      c == 0x20 || c == 0x0A || c == 0x09 || c == 0x0D || c == 0xA0;

  static bool _isCloser(String c) =>
      c == '"' || c == "'" || c == '”' || c == '’' || c == ')' || c == ']';

  static bool _isOpener(String c) =>
      c == '"' || c == "'" || c == '“' || c == '‘';
}
