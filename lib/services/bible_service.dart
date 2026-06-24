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
