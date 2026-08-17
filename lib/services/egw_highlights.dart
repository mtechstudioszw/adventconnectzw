import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'cache_service.dart';

/// Passages the member has highlighted, per book.
///
/// ## Why the TEXT is stored, not an offset
///
/// The obvious design is a character range, and it is the wrong one here.
/// The reader repaginates whenever the type size, the viewport or the
/// orientation changes, and a paragraph gets sliced at a different point
/// every time — so an offset into "the page" is meaningless by the next
/// session. Even an offset into the chapter breaks the moment the parser
/// changes how it collapses whitespace.
///
/// Storing the passage itself is stable against all of that: a highlight is
/// re-found by matching text, so it survives re-pagination, a type-size
/// change, and a re-parse of the book.
///
/// The known cost is duplicates — a passage appearing twice in one chapter
/// highlights both. That is rare in practice, and vastly preferable to
/// highlights that silently drift onto the wrong sentence.
///
/// ## Storage
///
/// Deliberately NOT `pref:`-prefixed. `CacheService.clearUserData()` wipes
/// anything without that prefix on sign-out, which is exactly right here:
/// highlights are personal content, and the next member to sign in on a
/// shared phone must not inherit them. Reading settings ARE `pref:`, since
/// type size belongs to the handset and the person's eyes.
class EgwHighlights {
  EgwHighlights._();

  static String _key(String bookId) => 'egw_hl:$bookId';

  /// Bumped on every change so open readers repaint.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// Highlighted passages for a book, grouped by chapter id.
  static Map<String, List<String>> forBook(String bookId) {
    final raw = CacheService.readPref(_key(bookId));
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map(
        (chapter, list) => MapEntry(
          chapter,
          (list as List).map((e) => e.toString()).toList(),
        ),
      );
    } catch (_) {
      return const {};
    }
  }

  static List<String> forChapter(String bookId, String chapterId) =>
      forBook(bookId)[chapterId] ?? const [];

  static bool has(String bookId, String chapterId, String text) =>
      forChapter(bookId, chapterId).contains(_clean(text));

  static void add(String bookId, String chapterId, String text) {
    final passage = _clean(text);
    // A highlight of two words is noise; of nothing at all is a bug.
    if (passage.length < 3) return;

    final all = Map<String, List<String>>.from(forBook(bookId));
    final list = List<String>.from(all[chapterId] ?? const []);
    if (list.contains(passage)) return;
    list.add(passage);
    all[chapterId] = list;
    _save(bookId, all);
  }

  static void remove(String bookId, String chapterId, String text) {
    final passage = _clean(text);
    final all = Map<String, List<String>>.from(forBook(bookId));
    final list = List<String>.from(all[chapterId] ?? const []);
    if (!list.remove(passage)) return;
    if (list.isEmpty) {
      all.remove(chapterId);
    } else {
      all[chapterId] = list;
    }
    _save(bookId, all);
  }

  /// The wash appears on the frame the member asked for it.
  ///
  /// The write is started but not awaited, and the order matters:
  /// `writePref` reaches `box.put` before its first `await`, and Hive
  /// updates its in-memory keystore there — so [forBook] already reads the
  /// new passage back while only the disk flush is outstanding. Awaiting it
  /// first is what made the reading settings feel dead (see
  /// [EgwReaderPrefs]), and a highlight is even less forgiving: the member
  /// is watching the exact words they just picked.
  static void _save(String bookId, Map<String, List<String>> all) {
    unawaited(
      CacheService.writePref(_key(bookId), jsonEncode(all)).catchError(
        (Object e) => debugPrint('EgwHighlights: could not persist: $e'),
      ),
    );
    revision.value++;
  }

  /// Character ranges of [text] that fall inside a highlighted passage.
  ///
  /// Returned sorted and merged, so overlapping highlights paint as one
  /// wash rather than stacking their alpha into a darker band.
  static List<({int start, int end})> rangesIn(
    String text,
    List<String> passages,
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
      // then stores fine and simply never paints, which is indistinguishable
      // from the feature not working.
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
  /// for the single spaces the stored passage was collapsed to.
  ///
  /// Returns ranges into the ORIGINAL [text], so the caller can keep
  /// painting against the string it actually renders.
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
      // A passage long enough to blow the regex engine is not worth
      // failing a page render over.
      return const [];
    }
  }

  /// Collapses whitespace so a passage selected across a line break matches
  /// the text the reader renders. Selection returns what was on screen,
  /// wrapping included.
  static String _clean(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

  /// The sentence surrounding [offset] in [text], as `[start, end)`.
  ///
  /// Founder, 18 Aug 2026: *"when click text in egw it should highlight a
  /// statement from were it starts to where it end n u can hight many
  /// statements"*. This is the half that decides where a statement begins
  /// and ends; the storage was already on our side, since a highlight is
  /// matched by TEXT rather than by offsets.
  ///
  /// Splitting on `.` alone is wrong in these books specifically. They are
  /// dense with initials (E. G. White), abbreviations (Mrs., vol., p.) and
  /// verse references (Col. 2:3) — and a rule that breaks on every period
  /// would highlight two words and look broken. So a terminator only ends a
  /// sentence when what FOLLOWS it looks like a new one: whitespace, then a
  /// capital or a quote. That single test handles all three cases above
  /// without a dictionary of abbreviations to maintain.
  ///
  /// Returns the whole of [text] when it holds no sentence break at all,
  /// which is the right answer for a one-line quotation.
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
    // stop is never the end of a statement, and this shelf is full of them.
    // It is also the one case the "followed by a capital" test below cannot
    // catch, since an initial IS followed by a capital.
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

  static bool _isSpace(int c) => c == 0x20 || c == 0x0A || c == 0x09 ||
      c == 0x0D || c == 0xA0;

  static bool _isCloser(String c) =>
      c == '"' || c == "'" || c == '”' || c == '’' || c == ')' ||
      c == ']';

  static bool _isOpener(String c) =>
      c == '"' || c == "'" || c == '“' || c == '‘';
}
