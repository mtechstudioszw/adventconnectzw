import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../models/bible_translation.dart';
import 'cache_service.dart';

/// Hundreds of Bibles in hundreds of languages (owner, 3 Nov 2026: "add
/// many Bible translations, as many languages as possible").
///
/// The catalogue is bible.helloao.org's list (1,500+ translations). We keep
/// only what this app may lawfully show:
///   * the licence ALLOWS COMMERCIAL USE — the Android app carries ads and
///     sells Premium, so "non-commercial" Bibles (about half the list) are
///     left out rather than risk a takedown;
///   * at least a whole New Testament (27 books), so a pick is always
///     worth reading.
/// Licences that require attribution get it under every chapter.
///
/// Cached on the phone (`bible:` keys are library content: kept a year and
/// across sign-out is not needed — the list refetches in one request).
class BibleCatalog {
  BibleCatalog._();

  static const _url =
      'https://bible.helloao.org/api/available_translations.json';
  static const _kCatalog = 'bible:catalog_v1';
  static String _kBooks(String id) => 'bible:books_v1:$id';

  /// Already curated / bundled — never listed twice.
  static const _skip = {
    'BSB',
    'sna_bib',
    'eng_kjv',
    'eng_kja',
    'eng_cpb',
    'heb_wlc',
    'grc_byz',
    'grc_sbl',
    'grc_gtr',
    'grc_bre',
  };

  static Future<List<BibleTranslation>>? _loading;

  /// Registers the cached catalogue straight away (so a saved choice of,
  /// say, Ndebele resolves on launch), then refreshes in the background.
  static void restoreCached() {
    final raw = CacheService.readStringStale(_kCatalog);
    if (raw == null) return;
    try {
      BibleTranslations.registerCatalog(
        parse(jsonDecode(raw) as Map<String, dynamic>),
      );
    } catch (_) {}
  }

  /// The catalogue: cached copy if fetched in the last week, else network
  /// (falling back to whatever is cached).
  static Future<List<BibleTranslation>> load() =>
      _loading ??= _load().whenComplete(() => _loading = null);

  static Future<List<BibleTranslation>> _load() async {
    final cached = CacheService.readStringStale(_kCatalog);
    final fresh = CacheService.readString(_kCatalog);
    if (fresh == null) {
      try {
        final body = await _get(_url);
        final list = parse(jsonDecode(body) as Map<String, dynamic>);
        if (list.isNotEmpty) {
          unawaited(CacheService.writeString(_kCatalog, body));
          BibleTranslations.registerCatalog(list);
          return list;
        }
      } catch (e) {
        debugPrint('BibleCatalog: fetch failed: $e');
      }
    }
    if (cached == null) return const [];
    final list = parse(jsonDecode(cached) as Map<String, dynamic>);
    BibleTranslations.registerCatalog(list);
    return list;
  }

  /// Fetches (once, then cached) which books [t] really contains, so the
  /// reader says "not in this translation" instead of failing a download.
  static Future<void> ensureBooks(BibleTranslation t) async {
    if (t.languageEnglish == null) return; // curated: coverage is exact
    final cached = CacheService.readStringStale(_kBooks(t.id));
    if (cached != null) {
      BibleTranslations.registerBooks(
        t.id,
        (jsonDecode(cached) as List).cast<String>().toSet(),
      );
      return;
    }
    try {
      final body = await _get(
        'https://bible.helloao.org/api/${t.id}/books.json',
      );
      final books = ((jsonDecode(body) as Map)['books'] as List)
          .map((b) => (b as Map)['id'].toString())
          .toList();
      if (books.isEmpty) return;
      BibleTranslations.registerBooks(t.id, books.toSet());
      unawaited(CacheService.writeString(_kBooks(t.id), jsonEncode(books)));
    } catch (e) {
      debugPrint('BibleCatalog: books for ${t.id} failed: $e');
    }
  }

  /// Turns the API's list into translations this app may show.
  @visibleForTesting
  static List<BibleTranslation> parse(Map<String, dynamic> json) {
    final out = <BibleTranslation>[];
    for (final e in (json['translations'] as List? ?? const [])) {
      if (e is! Map) continue;
      final id = '${e['id'] ?? ''}';
      final license = e['license'];
      final books = (e['numberOfBooks'] as num?)?.toInt() ?? 0;
      if (id.isEmpty || _skip.contains(id)) continue;
      if (license is! Map || license['commercialUse'] != 'allowed') continue;
      if (books < 27) continue;
      final english = '${e['englishName'] ?? e['name'] ?? id}'.trim();
      final native = '${e['name'] ?? english}'.trim();
      final langEnglish = '${e['languageEnglishName'] ?? e['language'] ?? ''}'
          .trim();
      final langNative = '${e['languageName'] ?? langEnglish}'.trim();
      final coverage = books >= 60
          ? TranslationCoverage.whole
          : books == 39
          ? TranslationCoverage.oldTestament
          : TranslationCoverage.newTestament;
      out.add(
        BibleTranslation(
          id: id,
          name: english,
          nativeName: native,
          languageLabel: langNative.isEmpty ? langEnglish : langNative,
          languageEnglish: langEnglish.isEmpty ? 'Other' : langEnglish,
          glyph: _glyph(native),
          accent: _accent(id),
          rtl: e['textDirection'] == 'rtl',
          coverage: coverage,
          note: switch (coverage) {
            TranslationCoverage.whole => 'Whole Bible',
            TranslationCoverage.newTestament => 'New Testament',
            TranslationCoverage.oldTestament => 'Old Testament',
          },
          attribution: license['attribution'] == 'required'
              ? '$native. Used under its open licence'
                    '${e['licenseUrl'] != null ? ': ${e['licenseUrl']}' : '.'}'
              : null,
        ),
      );
    }
    out.sort((a, b) {
      final l = a.languageEnglish!.compareTo(b.languageEnglish!);
      return l != 0 ? l : a.name.compareTo(b.name);
    });
    return out;
  }

  static String _glyph(String name) {
    final s = name.trim();
    if (s.isEmpty) return '•';
    final rune = s.runes.first;
    return String.fromCharCode(rune).toUpperCase();
  }

  /// A stable brand-palette accent per translation.
  static Color _accent(String id) {
    const palette = [
      AppAccent.blue,
      AppAccent.navy,
      AppAccent.gold,
      AppAccent.blue2,
    ];
    return palette[id.codeUnits.fold<int>(0, (a, c) => a + c) % palette.length];
  }

  static Future<String> _get(String url) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.getUrl(Uri.parse(url));
      final resp = await req.close().timeout(const Duration(seconds: 20));
      if (resp.statusCode != 200) {
        throw HttpException('HTTP ${resp.statusCode} for $url');
      }
      return await resp.transform(utf8.decoder).join();
    } finally {
      client.close(force: true);
    }
  }
}

/// Accent colours for catalogue cards — the app palette only.
class AppAccent {
  static const blue = Color(0xFF1565C0);
  static const navy = Color(0xFF0D1B3E);
  static const gold = Color(0xFFC8A951);
  static const blue2 = Color(0xFF1976D2);
}
