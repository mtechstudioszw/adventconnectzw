import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// One book of the bundled offline KJV (assets/bible/kjv.json).
class BibleBook {
  const BibleBook({
    required this.index,
    required this.name,
    required this.abbrev,
    required this.chapters,
  });

  final int index;
  final String name;
  final String abbrev;

  /// chapters[c] is the list of raw verse strings for chapter c (0-based).
  final List<List<String>> chapters;

  int get chapterCount => chapters.length;

  /// Genesis–Malachi are the first 39 books; the rest are the New Testament.
  bool get isOldTestament => index < 39;
}

/// A single verse match from [BibleService.search].
class BibleSearchHit {
  const BibleSearchHit({
    required this.book,
    required this.chapter,
    required this.verse,
    required this.text,
  });
  final BibleBook book;
  final int chapter;
  final int verse;
  final String text;

  String get reference => '${book.name} ${chapter + 1}:${verse + 1}';
}

/// Loads + caches the bundled KJV so the Bible tab works fully offline.
class BibleService {
  BibleService._();

  static List<BibleBook>? _books;

  /// All 66 books. Parsed once on first use, then served from memory.
  static Future<List<BibleBook>> books() async {
    final cached = _books;
    if (cached != null) return cached;
    final raw = await rootBundle.loadString('assets/bible/kjv.json');
    // The asset is UTF-8 with a BOM — strip it so jsonDecode doesn't choke.
    final clean = raw.startsWith('﻿') ? raw.substring(1) : raw;
    final list = jsonDecode(clean) as List;
    final out = <BibleBook>[];
    for (var i = 0; i < list.length; i++) {
      final m = list[i] as Map<String, dynamic>;
      final chapters = <List<String>>[
        for (final ch in (m['chapters'] as List))
          [for (final v in (ch as List)) v.toString()],
      ];
      out.add(BibleBook(
        index: i,
        name: (m['name'] ?? m['abbrev'] ?? 'Book ${i + 1}').toString(),
        abbrev: (m['abbrev'] ?? '').toString(),
        chapters: chapters,
      ));
    }
    return _books = out;
  }

  /// Resolve a human reference like `John 3:16`, `1 Cor 13:4` or
  /// `Song of Solomon 2:1` into somewhere the reader can open.
  ///
  /// Returned chapter and verse are **1-based**, matching what a reader
  /// screen expects; `null` when the reference cannot be understood, so the
  /// caller can fall back to just opening the Bible rather than guessing.
  ///
  /// Matching is deliberately forgiving. The devotion feed writes book
  /// names by hand, so it produces "1 Corinthians", "1 Cor", "I Cor" and
  /// "1Cor" for the same book, and any of them landing on "no such book"
  /// would silently drop the member on Genesis 1.
  static Future<BibleReference?> resolveReference(String raw) async {
    final text = raw.trim();
    if (text.isEmpty) return null;

    final match = RegExp(
      // book name (may start with a numeral), then chapter[:verse]
      r'^\s*([1-3]?\s*[A-Za-z][A-Za-z\s.]*?)\s*(\d+)\s*(?::\s*(\d+))?',
      caseSensitive: false,
    ).firstMatch(text);
    if (match == null) return null;

    final wanted = _normaliseBookName(match.group(1) ?? '');
    if (wanted.isEmpty) return null;
    final chapter = int.tryParse(match.group(2) ?? '');
    if (chapter == null || chapter < 1) return null;
    final verse = int.tryParse(match.group(3) ?? '');

    final all = await books();
    BibleBook? found;
    for (final book in all) {
      final name = _normaliseBookName(book.name);
      final abbrev = _normaliseBookName(book.abbrev);
      // Exact first, then prefix — so "Judg" finds Judges without "Jude"
      // ever winning, and "John" is never swallowed by "1 John".
      if (name == wanted || abbrev == wanted) {
        found = book;
        break;
      }
      if (found == null && (name.startsWith(wanted) || wanted == abbrev)) {
        found = book;
      }
    }
    if (found == null) return null;
    if (chapter > found.chapterCount) return null;

    return BibleReference(book: found, chapter: chapter, verse: verse);
  }

  /// Lower-cased, unspaced, undotted, with leading Roman numerals folded to
  /// digits: `I Cor.` and `1 Corinthians` both reduce toward `1cor…`.
  static String _normaliseBookName(String raw) {
    var v = raw.toLowerCase().replaceAll('.', '').trim();
    v = v.replaceFirst(RegExp(r'^iii\s*'), '3 ');
    v = v.replaceFirst(RegExp(r'^ii\s*'), '2 ');
    v = v.replaceFirst(RegExp(r'^i\s+'), '1 ');
    return v.replaceAll(RegExp(r'\s+'), '');
  }

  /// One verse hit from [search].
  static final List<BibleSearchHit> _empty = const [];

  /// Full-text search across every verse (case-insensitive, all words must
  /// appear). Returns up to [limit] hits with cleaned text. Cheap enough to
  /// run on the bundled KJV without isolates for typical queries.
  static Future<List<BibleSearchHit>> search(String query,
      {int limit = 200}) async {
    final terms = query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    if (terms.isEmpty) return _empty;
    final all = await books();
    final hits = <BibleSearchHit>[];
    for (final book in all) {
      for (var c = 0; c < book.chapters.length; c++) {
        final verses = book.chapters[c];
        for (var v = 0; v < verses.length; v++) {
          final lower = verses[v].toLowerCase();
          if (terms.every(lower.contains)) {
            hits.add(BibleSearchHit(
              book: book,
              chapter: c,
              verse: v,
              text: cleanVerse(verses[v]),
            ));
            if (hits.length >= limit) return hits;
          }
        }
      }
    }
    return hits;
  }

  /// Strips KJV editorial markup for clean display:
  ///  - translator NOTES `{...: Heb. ...}` (brace groups with a colon) → removed
  ///  - italicised added words like `{was}` → keep the word, drop the braces
  static String cleanVerse(String verse) {
    var s = verse.replaceAll(RegExp(r'\{[^}]*:[^}]*\}'), '');
    s = s.replaceAll(RegExp(r'[{}]'), '');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }
}

/// A resolved place in the Bible. Chapter and verse are 1-based, which is
/// what a reader screen expects — `BibleBook.chapters` is 0-based, so the
/// two are deliberately not interchangeable.
class BibleReference {
  const BibleReference({
    required this.book,
    required this.chapter,
    this.verse,
  });

  final BibleBook book;
  final int chapter;
  final int? verse;
}
