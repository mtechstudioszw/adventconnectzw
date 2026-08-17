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

  static Future<void> add(
    String bookId,
    String chapterId,
    String text,
  ) async {
    final passage = _clean(text);
    // A highlight of two words is noise; of nothing at all is a bug.
    if (passage.length < 3) return;

    final all = Map<String, List<String>>.from(forBook(bookId));
    final list = List<String>.from(all[chapterId] ?? const []);
    if (list.contains(passage)) return;
    list.add(passage);
    all[chapterId] = list;
    await _save(bookId, all);
  }

  static Future<void> remove(
    String bookId,
    String chapterId,
    String text,
  ) async {
    final passage = _clean(text);
    final all = Map<String, List<String>>.from(forBook(bookId));
    final list = List<String>.from(all[chapterId] ?? const []);
    if (!list.remove(passage)) return;
    if (list.isEmpty) {
      all.remove(chapterId);
    } else {
      all[chapterId] = list;
    }
    await _save(bookId, all);
  }

  static Future<void> _save(
    String bookId,
    Map<String, List<String>> all,
  ) async {
    await CacheService.writePref(_key(bookId), jsonEncode(all));
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
      while (true) {
        final at = text.indexOf(passage, from);
        if (at < 0) break;
        found.add((start: at, end: at + passage.length));
        from = at + passage.length;
      }
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

  /// Collapses whitespace so a passage selected across a line break matches
  /// the text the reader renders. Selection returns what was on screen,
  /// wrapping included.
  static String _clean(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();
}
