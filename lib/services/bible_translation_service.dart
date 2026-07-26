import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/bible_translation.dart';
import 'cache_service.dart';

/// One chapter in a non-bundled translation.
class TranslatedChapter {
  const TranslatedChapter({
    required this.verses,
    this.headings = const {},
    this.audioLinks = const {},
  });

  /// Verse text, index 0 = verse 1.
  final List<String> verses;

  /// verseIndex → section heading that precedes it (e.g. "Jesus Teaches
  /// Nicodemus"). The bundled KJV has none; the modern translations do, and
  /// they make a chapter far easier to scan.
  final Map<int, String> headings;

  /// Narrator name → chapter MP3 URL. Only the BSB currently ships these.
  final Map<String, String> audioLinks;

  bool get hasAudio => audioLinks.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'verses': verses,
        'headings': headings.map((k, v) => MapEntry(k.toString(), v)),
        'audio': audioLinks,
      };

  factory TranslatedChapter.fromJson(Map<String, dynamic> json) {
    return TranslatedChapter(
      verses: (json['verses'] as List).map((e) => e.toString()).toList(),
      headings: ((json['headings'] as Map?) ?? const {}).map(
        (k, v) => MapEntry(int.tryParse(k.toString()) ?? 0, v.toString()),
      ),
      audioLinks: ((json['audio'] as Map?) ?? const {}).map(
        (k, v) => MapEntry(k.toString(), v.toString()),
      ),
    );
  }
}

/// Fetches non-bundled Bible translations from the Free Use Bible API
/// (bible.helloao.org) and caches every chapter locally.
///
/// The bundled KJV never comes through here — [BibleService] serves it from
/// the asset. This is only for Shona, Hebrew, Greek and the BSB.
///
/// Offline story: a chapter is written to Hive the first time it loads, so
/// re-reading it never needs a connection. Nothing throws at the UI; a failed
/// fetch with no cache returns null and the reader shows a clear message.
class BibleTranslationService {
  BibleTranslationService._();

  static const _base = 'https://bible.helloao.org/api';
  static const _timeout = Duration(seconds: 15);
  static const _kActive = 'bible_translation_v1';

  /// Bumped when the active translation changes so open readers rebuild.
  static final ValueNotifier<String> active =
      ValueNotifier<String>(BibleTranslations.kjv.id);

  /// Restores the saved translation. Call once when the Bible tab mounts.
  static void restore() {
    active.value =
        CacheService.readPref(_kActive) ?? BibleTranslations.kjv.id;
  }

  static BibleTranslation get current =>
      BibleTranslations.byId(active.value);

  static Future<void> setActive(BibleTranslation translation) async {
    active.value = translation.id;
    await CacheService.writePref(_kActive, translation.id);
  }

  static String _cacheKey(String translationId, int book, int chapter) =>
      'bible:$translationId:$book:$chapter';

  /// Loads one chapter of [translation]. Cache-first, then network.
  ///
  /// Returns null when the chapter is unavailable offline and the fetch fails,
  /// or when the translation genuinely lacks that book.
  static Future<TranslatedChapter?> chapter({
    required BibleTranslation translation,
    required int bookIndex,
    required int chapter,
  }) async {
    if (translation.isBundled) return null;
    if (!translation.hasBook(bookIndex)) return null;

    final key = _cacheKey(translation.id, bookIndex, chapter);
    final cached = CacheService.readStringStale(key);
    if (cached != null) {
      try {
        return TranslatedChapter.fromJson(
            jsonDecode(cached) as Map<String, dynamic>);
      } catch (_) {
        // Corrupt entry — fall through and refetch.
      }
    }

    final code = BibleTranslations.codeFor(bookIndex);
    if (code == null) return null;

    try {
      final parsed = await _fetch(translation.id, code, chapter + 1);
      unawaited(CacheService.writeString(key, jsonEncode(parsed.toJson())));
      return parsed;
    } catch (e) {
      debugPrint('BibleTranslationService.chapter failed: $e');
      return null;
    }
  }

  static Future<TranslatedChapter> _fetch(
    String translationId,
    String bookCode,
    int chapterNumber,
  ) async {
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final uri = Uri.parse(
          '$_base/$translationId/$bookCode/$chapterNumber.json');
      final req = await client.getUrl(uri);
      final resp = await req.close().timeout(_timeout);
      if (resp.statusCode != 200) {
        throw HttpException('HTTP ${resp.statusCode} for $uri');
      }
      final body = await resp.transform(utf8.decoder).join().timeout(_timeout);
      final doc = jsonDecode(body) as Map<String, dynamic>;

      final content =
          ((doc['chapter'] as Map?)?['content'] as List?) ?? const [];

      final verses = <String>[];
      final headings = <int, String>{};
      String? pendingHeading;

      for (final node in content) {
        if (node is! Map) continue;
        final type = node['type']?.toString();
        if (type == 'heading') {
          pendingHeading = _flatten(node['content']);
        } else if (type == 'verse') {
          if (pendingHeading != null && pendingHeading.isNotEmpty) {
            headings[verses.length] = pendingHeading;
            pendingHeading = null;
          }
          verses.add(_flatten(node['content']));
        }
      }

      final audio = <String, String>{};
      final rawAudio = doc['thisChapterAudioLinks'];
      if (rawAudio is Map) {
        rawAudio.forEach((k, v) => audio[k.toString()] = v.toString());
      }

      return TranslatedChapter(
        verses: verses,
        headings: headings,
        audioLinks: audio,
      );
    } finally {
      client.close(force: true);
    }
  }

  /// Verse content is a list that mixes plain strings with objects (footnote
  /// refs, poetry markers, `{noteId: …}`). Keep the readable text, drop the
  /// rest, so a verse never renders as `{noteId: 12}`.
  static String _flatten(dynamic content) {
    if (content == null) return '';
    if (content is String) return content;
    if (content is! List) return '';
    final buffer = StringBuffer();
    for (final part in content) {
      if (part is String) {
        if (buffer.isNotEmpty) buffer.write(' ');
        buffer.write(part);
      } else if (part is Map) {
        // Poetry / word-of-Jesus wrappers carry their own nested text.
        final nested = part['content'] ?? part['text'];
        final text = _flatten(nested is String ? [nested] : nested);
        if (text.isNotEmpty) {
          if (buffer.isNotEmpty) buffer.write(' ');
          buffer.write(text);
        }
      }
    }
    return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// True when this chapter is already readable offline.
  static bool isChapterCached(
    BibleTranslation translation,
    int bookIndex,
    int chapter,
  ) {
    if (translation.isBundled) return true;
    return CacheService.readStringStale(
          _cacheKey(translation.id, bookIndex, chapter),
        ) !=
        null;
  }
}
