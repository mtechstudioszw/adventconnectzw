import 'bible_service.dart';

/// A scripture reference detected in free text (e.g. a sermon title or
/// description): "John 3:16", "Rom 8:28-30", "1 Cor 13:4".
class VerseRef {
  const VerseRef({
    required this.book,
    required this.chapter,
    required this.startVerse,
    required this.endVerse,
    required this.display,
  });

  final String book; // canonical book name as in the KJV asset
  final int chapter;
  final int startVerse;
  final int endVerse;
  final String display; // "John 3:16" / "Romans 8:28-30"
}

/// One read verse (number + cleaned text).
class VerseLine {
  const VerseLine(this.number, this.text);
  final int number;
  final String text;
}

/// Detects scripture references in text and reads the passage from the
/// offline KJV ([BibleService]). Conservative on purpose — it only emits a
/// chip when it can confidently match a real book + in-range chapter/verse,
/// so a sermon description never sprouts bogus links.
class VerseRefService {
  VerseRefService._();

  // Common non-prefix abbreviations → a token that prefix-matches the
  // canonical KJV name. (Prefix abbreviations like "gen", "rom", "matt",
  // "1cor", "ps", "heb" are resolved automatically below.)
  static const Map<String, String> _abbrev = {
    'mt': 'matthew', 'mk': 'mark', 'mr': 'mark', 'lk': 'luke',
    'jn': 'john', 'jhn': 'john', 'ac': 'acts', 'ro': 'romans',
    'jas': 'james', 'jms': 'james', 'php': 'philippians', 'pp': 'philippians',
    'phm': 'philemon', 'phlm': 'philemon', 'tit': 'titus',
    'rev': 'revelation', 're': 'revelation', 'heb': 'hebrews',
    'jud': 'jude', 'gal': 'galatians', 'eph': 'ephesians', 'col': 'colossians',
    'dt': 'deuteronomy', 'ex': 'exodus', 'lev': 'leviticus', 'nu': 'numbers',
    'ps': 'psalms', 'psa': 'psalms', 'pss': 'psalms', 'prov': 'proverbs',
    'pr': 'proverbs', 'ecc': 'ecclesiastes', 'isa': 'isaiah', 'is': 'isaiah',
    'jer': 'jeremiah', 'eze': 'ezekiel', 'ezk': 'ezekiel', 'dan': 'daniel',
    'da': 'daniel', 'hos': 'hosea', 'mic': 'micah', 'zec': 'zechariah',
    'zech': 'zechariah', 'mal': 'malachi', 'cor': 'corinthians',
    'th': 'thessalonians', 'thess': 'thessalonians', 'tim': 'timothy',
    'pet': 'peter', 'pt': 'peter',
  };

  static String _norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  /// Resolve a raw book token (e.g. "1 Cor", "Ps", "John") to a canonical
  /// KJV book name, or null when it can't be matched unambiguously.
  static String? _resolveBook(String raw, List<BibleBook> books) {
    var key = _norm(raw);
    if (key.length < 2) return null;
    // Direct abbreviation (with any numeric prefix preserved, e.g. "1cor").
    final numMatch = RegExp(r'^([1-3])(.*)$').firstMatch(key);
    final prefix = numMatch != null ? numMatch.group(1)! : '';
    final word = numMatch != null ? numMatch.group(2)! : key;
    final mapped = _abbrev[word];
    final target = mapped != null ? '$prefix$mapped' : key;

    // 1) Exact normalized full-name match.
    for (final b in books) {
      if (_norm(b.name) == target) return b.name;
    }
    // 2) Unique prefix match (>= 3 chars) against the normalized names.
    if (target.length >= 3) {
      final hits = books.where((b) => _norm(b.name).startsWith(target)).toList();
      if (hits.length == 1) return hits.first.name;
    }
    return null;
  }

  /// Find references in [text]. Returns at most [max] de-duplicated refs.
  static Future<List<VerseRef>> parse(String text, {int max = 8}) async {
    if (text.trim().isEmpty) return const [];
    final books = await BibleService.books();
    if (books.isEmpty) return const [];
    final byName = {for (final b in books) b.name: b};

    // BookToken Chapter:Verse(-Verse)?  — BookToken allows a 1–3 numeric
    // prefix ("1 John") and a multi-word name is captured by the last word
    // before the digits.
    final re = RegExp(
      r'((?:[1-3]\s*)?[A-Za-z]{2,})\.?\s+(\d{1,3}):(\d{1,3})(?:\s*[-–]\s*(\d{1,3}))?',
    );
    final out = <VerseRef>[];
    final seen = <String>{};
    for (final m in re.allMatches(text)) {
      final book = _resolveBook(m.group(1)!, books);
      if (book == null) continue;
      final chapter = int.tryParse(m.group(2)!) ?? 0;
      final start = int.tryParse(m.group(3)!) ?? 0;
      final end = m.group(4) != null ? (int.tryParse(m.group(4)!) ?? start) : start;
      final b = byName[book]!;
      if (chapter < 1 || chapter > b.chapterCount) continue;
      final verses = b.chapters[chapter - 1];
      if (start < 1 || start > verses.length) continue;
      final endClamped = end < start ? start : (end > verses.length ? verses.length : end);
      final display = endClamped > start
          ? '$book $chapter:$start-$endClamped'
          : '$book $chapter:$start';
      if (seen.add(display)) {
        out.add(VerseRef(
          book: book,
          chapter: chapter,
          startVerse: start,
          endVerse: endClamped,
          display: display,
        ));
      }
      if (out.length >= max) break;
    }
    return out;
  }

  /// Read the passage text for a ref from the offline KJV.
  static Future<List<VerseLine>> passage(VerseRef ref) async {
    final books = await BibleService.books();
    final book = books.where((b) => b.name == ref.book).cast<BibleBook?>().firstWhere(
          (b) => b != null,
          orElse: () => null,
        );
    if (book == null || ref.chapter > book.chapterCount) return const [];
    final verses = book.chapters[ref.chapter - 1];
    final out = <VerseLine>[];
    for (var v = ref.startVerse; v <= ref.endVerse && v <= verses.length; v++) {
      out.add(VerseLine(v, BibleService.cleanVerse(verses[v - 1])));
    }
    return out;
  }
}
