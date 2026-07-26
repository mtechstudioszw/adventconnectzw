import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'cache_service.dart';

/// Local, offline progress + notes for Sabbath School.
///
/// Everything is per-device (Hive), matching [BiblePrefsService] and
/// [HymnPrefs] — no server round trip, so ticking a day works with no
/// connection and never blocks the reader.
class SabbathSchoolPrefs {
  SabbathSchoolPrefs._();

  static const _kRead = 'ss_read_days_v1'; // Set<dayIndex>
  static const _kNotes = 'ss_notes_v1'; // Map<dayIndex, String>
  static const _kFontScale = 'ss_font_scale_v1';
  static const _kLastRead = 'ss_last_read_v1'; // JSON pointer for "Continue"

  static final ValueNotifier<int> revision = ValueNotifier<int>(0);
  static void _bump() => revision.value++;

  // ---- Completed days -----------------------------------------------------

  /// Day identity is the API's stable `read_path`, so progress survives a
  /// language switch being switched back and never collides across quarters.
  static Set<String> readDays() {
    final raw = CacheService.readPref(_kRead);
    if (raw == null) return <String>{};
    try {
      return (jsonDecode(raw) as List).map((e) => e.toString()).toSet();
    } catch (_) {
      return <String>{};
    }
  }

  static bool isRead(String dayPath) => readDays().contains(dayPath);

  static Future<void> setRead(String dayPath, bool read) async {
    final set = readDays();
    read ? set.add(dayPath) : set.remove(dayPath);
    await CacheService.writePref(_kRead, jsonEncode(set.toList()));
    _bump();
  }

  static Future<void> toggleRead(String dayPath) =>
      setRead(dayPath, !isRead(dayPath));

  /// How many of [dayPaths] are complete — drives the per-week progress ring.
  static int readCount(Iterable<String> dayPaths) {
    final set = readDays();
    return dayPaths.where(set.contains).length;
  }

  // ---- Notes --------------------------------------------------------------

  static Map<String, String> notes() {
    final raw = CacheService.readPref(_kNotes);
    if (raw == null) return <String, String>{};
    try {
      return (jsonDecode(raw) as Map)
          .map((k, v) => MapEntry(k.toString(), v.toString()));
    } catch (_) {
      return <String, String>{};
    }
  }

  static String? note(String dayPath) => notes()[dayPath];

  static Future<void> setNote(String dayPath, String text) async {
    final map = notes();
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      map.remove(dayPath);
    } else {
      map[dayPath] = trimmed;
    }
    await CacheService.writePref(_kNotes, jsonEncode(map));
    _bump();
  }

  // ---- Reading settings ---------------------------------------------------

  static double fontScale() =>
      double.tryParse(CacheService.readPref(_kFontScale) ?? '') ?? 1.0;

  static Future<void> setFontScale(double v) async {
    await CacheService.writePref(
      _kFontScale,
      v.clamp(0.8, 2.0).toStringAsFixed(2),
    );
    _bump();
  }

  // ---- Continue reading ---------------------------------------------------

  /// Remembers where the reader left off so the tab can offer a one-tap
  /// "Continue" instead of making the user re-navigate the hierarchy.
  static Future<void> setLastRead({
    required String lang,
    required String quarterlyId,
    required String quarterlyTitle,
    required String lessonId,
    required String lessonTitle,
    required String dayPath,
    required String dayTitle,
  }) async {
    await CacheService.writePref(
      _kLastRead,
      jsonEncode({
        'lang': lang,
        'quarterly_id': quarterlyId,
        'quarterly_title': quarterlyTitle,
        'lesson_id': lessonId,
        'lesson_title': lessonTitle,
        'day_path': dayPath,
        'day_title': dayTitle,
        'at': DateTime.now().toIso8601String(),
      }),
    );
    _bump();
  }

  static Map<String, dynamic>? lastRead() {
    final raw = CacheService.readPref(_kLastRead);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearLastRead() => CacheService.deletePref(_kLastRead);
}
