import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/sabbath_school_model.dart';
import '../widgets/cached_image.dart' show precacheImageUrls;
import 'cache_service.dart';

/// Reads Sabbath School lessons from Adventech's public API — the same feed
/// the official Sabbath School app uses.
///
/// ## Offline behaviour
///
/// Every fetch writes through to Hive, and every read falls back to that cache
/// when the network is unavailable or slow. Once a lesson week has been
/// opened it stays readable forever, and [downloadLesson] pre-fetches a whole
/// week (all days + verses) in one go for deliberate offline use.
///
/// Nothing here throws at the UI: failures return cached content, or an empty
/// list the tab renders as a friendly state.
class SabbathSchoolService {
  SabbathSchoolService._();

  static const _base = 'https://sabbath-school.adventech.io/api/v1';

  /// Default language. Shona first — this is a Zimbabwean app, so the mother
  /// tongue is the default and English is a switch away, not the reverse.
  static const defaultLanguage = 'sn';

  /// Pinned to the top of the picker; the remaining ~85 follow alphabetically.
  static const priorityLanguages = ['sn', 'en', 'nd', 'af', 'pt', 'sw'];

  static const _kLang = 'ss_lang_v1';
  static const _kLangList = 'ss_languages_v1';

  /// Network calls are short-fused: the cache is almost always good enough,
  /// so waiting 30s on a stalled socket is strictly worse than showing it.
  static const _timeout = Duration(seconds: 15);

  // ---- Language -----------------------------------------------------------

  static String language() =>
      CacheService.readPref(_kLang) ?? defaultLanguage;

  static Future<void> setLanguage(String code) =>
      CacheService.writePref(_kLang, code);

  /// Every language Adventech publishes (~90), fetched live and cached so the
  /// picker still opens offline. Priority languages float to the top; the rest
  /// are alphabetical.
  ///
  /// Returns a hardcoded minimum on a cold first run with no connection, so
  /// the picker is never empty.
  static Future<List<SsLanguage>> languages() async {
    List<SsLanguage> order(List<SsLanguage> list) {
      final byCode = {for (final l in list) l.code: l};
      final pinned = [
        for (final code in priorityLanguages)
          if (byCode.containsKey(code)) byCode.remove(code)!,
      ];
      final rest = byCode.values.toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      return [...pinned, ...rest];
    }

    try {
      final data = await _get('languages/index.json');
      final list = (data as List)
          .map((e) => SsLanguage.fromJson(e as Map<String, dynamic>))
          .toList();
      if (list.isNotEmpty) {
        unawaited(CacheService.writeString(
          _kLangList,
          jsonEncode([for (final l in list) l.toJson()]),
        ));
        return order(list);
      }
    } catch (e) {
      debugPrint('SS languages falling back to cache: $e');
    }

    final cached = _readCache(_kLangList);
    if (cached is List && cached.isNotEmpty) {
      return order(cached
          .map((e) => SsLanguage.fromJson(e as Map<String, dynamic>))
          .toList());
    }
    // Cold first run with no connection. Covers every priority language
    // rather than just Shona + English: the picker collapsing to two entries
    // was the reported "it loses all the languages when I'm offline", and the
    // real cause (the 24h cache prune eating ss_languages_v1) is fixed in
    // CacheService — this is the floor underneath that.
    return const [
      SsLanguage(code: 'sn', name: 'Shona'),
      SsLanguage(code: 'en', name: 'English'),
      SsLanguage(code: 'nd', name: 'Ndebele'),
      SsLanguage(code: 'af', name: 'Afrikaans'),
      SsLanguage(code: 'pt', name: 'Português'),
      SsLanguage(code: 'sw', name: 'Kiswahili'),
    ];
  }

  // ---- Fetch primitives ---------------------------------------------------

  /// GETs [path] (relative to the API root) and decodes JSON.
  static Future<dynamic> _get(String path) async {
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final req = await client.getUrl(Uri.parse('$_base/$path'));
      final resp = await req.close().timeout(_timeout);
      if (resp.statusCode != 200) {
        throw HttpException('HTTP ${resp.statusCode} for $path');
      }
      final body = await resp.transform(utf8.decoder).join().timeout(_timeout);
      return jsonDecode(body);
    } finally {
      client.close(force: true);
    }
  }

  /// Reads [key] from Hive, decoded, or null.
  static dynamic _readCache(String key) {
    try {
      final raw = CacheService.readStringStale(key);
      if (raw == null) return null;
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }

  // ---- Quarterlies --------------------------------------------------------

  /// All quarterlies for [lang], newest first.
  ///
  /// Serves cache immediately on failure. Only "Standard Adult" and any group
  /// the API marks are kept in order; we don't filter groups out, so Youth /
  /// Primary quarterlies remain reachable.
  static Future<List<Quarterly>> quarterlies({String? lang}) async {
    final code = lang ?? language();
    final key = 'ss:quarterlies:$code';
    try {
      final data = await _get('$code/quarterlies/index.json');
      final list = (data as List)
          .map((e) => Quarterly.fromJson(e as Map<String, dynamic>))
          .toList();
      unawaited(CacheService.writeString(
        key,
        jsonEncode([for (final q in list) q.toJson()]),
      ));
      // Warm the covers into the image cache alongside the JSON, so a quarter
      // that has been seen once still shows its artwork offline instead of a
      // grid of retry tiles.
      unawaited(precacheImageUrls([
        for (final q in list) ...[q.cover, q.splash],
      ]));
      return list;
    } catch (e) {
      debugPrint('SS quarterlies falling back to cache: $e');
      final cached = _readCache(key);
      if (cached is List) {
        return cached
            .map((e) => Quarterly.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      return const [];
    }
  }

  /// The quarterly covering today, or the newest one available.
  static Future<Quarterly?> currentQuarterly({String? lang}) async {
    final all = await quarterlies(lang: lang);
    if (all.isEmpty) return null;
    for (final q in all) {
      if (q.isCurrent && (q.groupName == null || q.groupName == 'Standard Adult')) {
        return q;
      }
    }
    for (final q in all) {
      if (q.isCurrent) return q;
    }
    return all.first;
  }

  // ---- Lessons ------------------------------------------------------------

  /// The 13 lesson weeks of [quarterlyId].
  static Future<List<SsLesson>> lessons(
    String quarterlyId, {
    String? lang,
  }) async {
    final code = lang ?? language();
    final key = 'ss:lessons:$code:$quarterlyId';
    try {
      final data = await _get('$code/quarterlies/$quarterlyId/index.json');
      final raw = (data as Map<String, dynamic>)['lessons'] as List? ?? const [];
      final list = raw
          .map((e) => SsLesson.fromJson(e as Map<String, dynamic>))
          .toList();
      unawaited(CacheService.writeString(
        key,
        jsonEncode([for (final l in list) l.toJson()]),
      ));
      unawaited(precacheImageUrls([for (final l in list) l.cover]));
      return list;
    } catch (e) {
      debugPrint('SS lessons falling back to cache: $e');
      final cached = _readCache(key);
      if (cached is List) {
        return cached
            .map((e) => SsLesson.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      return const [];
    }
  }

  // ---- Days ---------------------------------------------------------------

  /// The days (readings) inside one lesson week.
  static Future<List<SsDay>> days(
    String quarterlyId,
    String lessonId, {
    String? lang,
  }) async {
    final code = lang ?? language();
    final key = 'ss:days:$code:$quarterlyId:$lessonId';
    try {
      final data = await _get(
        '$code/quarterlies/$quarterlyId/lessons/$lessonId/index.json',
      );
      final raw = (data as Map<String, dynamic>)['days'] as List? ?? const [];
      final list =
          raw.map((e) => SsDay.fromJson(e as Map<String, dynamic>)).toList();
      unawaited(CacheService.writeString(
        key,
        jsonEncode([for (final d in list) d.toJson()]),
      ));
      return list;
    } catch (e) {
      debugPrint('SS days falling back to cache: $e');
      final cached = _readCache(key);
      if (cached is List) {
        return cached
            .map((e) => SsDay.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      return const [];
    }
  }

  // ---- Day content --------------------------------------------------------

  static String _contentKey(String readPath) => 'ss:read:$readPath';

  /// The readable body of one day. Cache-first when [preferCache] (used by
  /// the reader so an already-downloaded week opens instantly).
  static Future<SsDayContent?> dayContent(
    String readPath, {
    bool preferCache = true,
  }) async {
    final key = _contentKey(readPath);
    if (preferCache) {
      final cached = _readCache(key);
      if (cached is Map<String, dynamic>) {
        // Refresh in the background so a corrected lesson lands next open,
        // without making the user wait for it now.
        unawaited(_refreshContent(readPath));
        return SsDayContent.fromJson(cached);
      }
    }
    try {
      final data = await _get('$readPath/index.json');
      final content = SsDayContent.fromJson(data as Map<String, dynamic>);
      unawaited(CacheService.writeString(key, jsonEncode(content.toJson())));
      return content;
    } catch (e) {
      debugPrint('SS dayContent failed: $e');
      final cached = _readCache(key);
      if (cached is Map<String, dynamic>) return SsDayContent.fromJson(cached);
      return null;
    }
  }

  static Future<void> _refreshContent(String readPath) async {
    try {
      final data = await _get('$readPath/index.json');
      await CacheService.writeString(
        _contentKey(readPath),
        jsonEncode(SsDayContent.fromJson(data as Map<String, dynamic>).toJson()),
      );
    } catch (_) {
      // Silent — we already served the cached copy.
    }
  }

  /// True when [readPath] is already on disk.
  static bool isDayCached(String readPath) =>
      CacheService.readStringStale(_contentKey(readPath)) != null;

  // ---- Whole-week download ------------------------------------------------

  /// Pre-fetches every day of a lesson week so it reads with no connection.
  /// Reports 0.0–1.0 through [onProgress]. Returns true if all days landed.
  static Future<bool> downloadLesson(
    String quarterlyId,
    String lessonId, {
    String? lang,
    void Function(double progress)? onProgress,
  }) async {
    final list = await days(quarterlyId, lessonId, lang: lang);
    if (list.isEmpty) return false;
    var done = 0;
    var ok = true;
    for (final day in list) {
      final content = await dayContent(day.readPath, preferCache: false);
      if (content == null) ok = false;
      done++;
      onProgress?.call(done / list.length);
    }
    return ok;
  }

  /// True when every day of the week is cached.
  static Future<bool> isLessonDownloaded(
    String quarterlyId,
    String lessonId, {
    String? lang,
  }) async {
    final key = 'ss:days:${lang ?? language()}:$quarterlyId:$lessonId';
    final cached = _readCache(key);
    if (cached is! List || cached.isEmpty) return false;
    for (final e in cached) {
      final day = SsDay.fromJson(e as Map<String, dynamic>);
      if (!isDayCached(day.readPath)) return false;
    }
    return true;
  }
}
