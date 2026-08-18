import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'cache_service.dart';
import 'highlight_text.dart';

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

  /// The decoded book, kept so a page turn does not re-parse JSON once per
  /// paragraph.
  ///
  /// [forChapter] is called from the reader's `_inline`, which runs for
  /// EVERY block on EVERY page it builds — and a `PageView` builds three
  /// pages at a time and rebuilds them mid-fling. Decoding the whole book's
  /// highlights thirty times per frame is exactly the kind of work that
  /// shows up as *"the page animation when swipping is abit lagging"*
  /// (founder, 18 Aug 2026), because it lands on the UI isolate in the
  /// middle of the turn.
  ///
  /// Keyed by the raw string it was decoded from, so it cannot go stale:
  /// every write goes through [_save], which puts the new JSON into Hive's
  /// in-memory keystore before its first `await`, so the next read sees a
  /// different raw string and re-decodes.
  static String? _cachedRaw;
  static String? _cachedBookId;
  static Map<String, List<String>> _cachedBook = const {};

  /// Highlighted passages for a book, grouped by chapter id.
  static Map<String, List<String>> forBook(String bookId) {
    final raw = CacheService.readPref(_key(bookId));
    if (raw == null || raw.isEmpty) return const {};
    if (bookId == _cachedBookId && raw == _cachedRaw) return _cachedBook;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final book = decoded.map(
        (chapter, list) => MapEntry(
          chapter,
          (list as List).map((e) => e.toString()).toList(),
        ),
      );
      _cachedBookId = bookId;
      _cachedRaw = raw;
      _cachedBook = book;
      return book;
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


  // ---- Text rules ---------------------------------------------------------
  //
  // Delegated to [HighlightText] since 19 Aug 2026, when Sabbath School
  // gained highlighting. The two STORES are deliberately different — these
  // highlights are device-local and sign-out clears them, Sabbath School's
  // follow the account — but where a statement begins and ends, and where a
  // stored passage sits in the text on screen, are the same questions. A
  // second copy would drift, and the sentence rule is the part most likely
  // to be quietly wrong.
  //
  // Kept as named delegates rather than deleted: they are the vocabulary the
  // reader and its tests already speak.

  /// Character ranges of [text] that fall inside a highlighted passage.
  static List<({int start, int end})> rangesIn(
    String text,
    List<String> passages,
  ) =>
      HighlightText.rangesIn(text, passages);

  /// The sentence surrounding [offset] in [text], as `[start, end)`.
  static ({int start, int end}) sentenceAt(String text, int offset) =>
      HighlightText.sentenceAt(text, offset);

  static String _clean(String s) => HighlightText.clean(s);
}
