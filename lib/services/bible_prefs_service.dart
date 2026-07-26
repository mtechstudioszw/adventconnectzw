import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'cache_service.dart';

/// Local (offline, no-TTL) persistence for the Bible reader's modern
/// features: bookmarks, highlights, notes, reading settings and the
/// last-read position. Backed by [CacheService] prefs (Hive). All state is
/// per-device — no server round-trip, so it works fully offline.
///
/// Verse identity is the stable key `bookIndex:chapter:verse` (all 0-based).
class BiblePrefsService {
  BiblePrefsService._();

  static const _kBookmarks = 'bible_bookmarks_v1'; // List<String> verseKeys
  static const _kHighlights = 'bible_highlights_v1'; // Map<verseKey,int color>
  static const _kNotes = 'bible_notes_v1'; // Map<verseKey,String>
  static const _kFontScale = 'bible_font_scale_v1'; // double 0.8–1.6
  static const _kLastPos = 'bible_last_pos_v1'; // "book:chapter"

  /// Palette for verse highlights (index → ARGB). Warm, readable on both
  /// light + dark surfaces.
  static const List<int> highlightColors = [
    0xFFFFF1A8, // yellow
    0xFFBFE3C0, // green
    0xFFBcdcff, // blue
    0xFFFFC9C9, // red/pink
    0xFFE6D3FF, // purple
  ];

  static String verseKey(int book, int chapter, int verse) =>
      '$book:$chapter:$verse';

  // ---- Listenable so open screens refresh when prefs change ----
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);
  static void _bump() => revision.value++;

  // ---- Bookmarks ----------------------------------------------------------
  static Set<String> bookmarks() {
    final raw = CacheService.readPref(_kBookmarks);
    if (raw == null) return <String>{};
    try {
      return (jsonDecode(raw) as List).map((e) => e.toString()).toSet();
    } catch (_) {
      return <String>{};
    }
  }

  static bool isBookmarked(String key) => bookmarks().contains(key);

  static Future<void> toggleBookmark(String key) async {
    final set = bookmarks();
    set.contains(key) ? set.remove(key) : set.add(key);
    await CacheService.writePref(_kBookmarks, jsonEncode(set.toList()));
    _bump();
  }

  // ---- Highlights ---------------------------------------------------------
  static Map<String, int> highlights() {
    final raw = CacheService.readPref(_kHighlights);
    if (raw == null) return <String, int>{};
    try {
      return (jsonDecode(raw) as Map)
          .map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
    } catch (_) {
      return <String, int>{};
    }
  }

  static int? highlightColor(String key) => highlights()[key];

  /// Sets [colorIndex] (into [highlightColors]) for a verse, or clears it
  /// when [colorIndex] is null.
  static Future<void> setHighlight(String key, int? colorIndex) async {
    final map = highlights();
    if (colorIndex == null) {
      map.remove(key);
    } else {
      map[key] = colorIndex;
    }
    await CacheService.writePref(_kHighlights, jsonEncode(map));
    _bump();
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

  static String? note(String key) => notes()[key];

  static Future<void> setNote(String key, String text) async {
    final map = notes();
    final t = text.trim();
    if (t.isEmpty) {
      map.remove(key);
    } else {
      map[key] = t;
    }
    await CacheService.writePref(_kNotes, jsonEncode(map));
    _bump();
  }

  // ---- Reading settings ---------------------------------------------------
  static double fontScale() {
    final raw = CacheService.readPref(_kFontScale);
    return double.tryParse(raw ?? '') ?? 1.0;
  }

  static Future<void> setFontScale(double scale) async {
    await CacheService.writePref(
        _kFontScale, scale.clamp(0.8, 1.8).toStringAsFixed(2));
    _bump();
  }

  // ---- Last-read position -------------------------------------------------
  /// Returns (bookIndex, chapter) of the last opened chapter, or null.
  static (int, int)? lastPosition() {
    final raw = CacheService.readPref(_kLastPos);
    if (raw == null) return null;
    final parts = raw.split(':');
    if (parts.length != 2) return null;
    final b = int.tryParse(parts[0]);
    final c = int.tryParse(parts[1]);
    if (b == null || c == null) return null;
    return (b, c);
  }

  static Future<void> setLastPosition(int book, int chapter) =>
      CacheService.writePref(_kLastPos, '$book:$chapter');

  // ---- Reading theme ------------------------------------------------------

  static const _kTheme = 'bible_theme_v1';

  /// Paper for the reader, independent of the app's light/dark setting — a
  /// reader wants sepia at night even when the rest of the app is light.
  static BibleReadingTheme readingTheme() {
    return switch (CacheService.readPref(_kTheme)) {
      'sepia' => BibleReadingTheme.sepia,
      'dark' => BibleReadingTheme.dark,
      'light' => BibleReadingTheme.light,
      _ => BibleReadingTheme.system,
    };
  }

  static Future<void> setReadingTheme(BibleReadingTheme theme) async {
    await CacheService.writePref(_kTheme, theme.name);
    _bump();
  }

  // ---- Reading streak -----------------------------------------------------

  static const _kStreak = 'bible_streak_v1'; // "count:yyyy-mm-dd"

  static String _today() {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${now.year}-${two(now.month)}-${two(now.day)}';
  }

  /// Consecutive days with at least one chapter opened. Resets when a day is
  /// skipped — read today to keep it alive.
  static int streak() {
    final raw = CacheService.readPref(_kStreak);
    if (raw == null) return 0;
    final parts = raw.split(':');
    if (parts.length != 2) return 0;
    final count = int.tryParse(parts[0]) ?? 0;
    final last = DateTime.tryParse(parts[1]);
    if (last == null) return 0;
    final today = DateTime.tryParse(_today());
    if (today == null) return count;
    final gap = today.difference(last).inDays;
    // 0 = already counted today, 1 = still unbroken until midnight.
    return gap <= 1 ? count : 0;
  }

  /// Called when a chapter is opened. Increments once per calendar day.
  static Future<void> noteReadToday() async {
    final raw = CacheService.readPref(_kStreak);
    final today = _today();
    if (raw != null) {
      final parts = raw.split(':');
      if (parts.length == 2) {
        if (parts[1] == today) return; // already counted
        final count = int.tryParse(parts[0]) ?? 0;
        final last = DateTime.tryParse(parts[1]);
        final todayDate = DateTime.tryParse(today);
        if (last != null && todayDate != null) {
          final gap = todayDate.difference(last).inDays;
          final next = gap == 1 ? count + 1 : 1;
          await CacheService.writePref(_kStreak, '$next:$today');
          _bump();
          return;
        }
      }
    }
    await CacheService.writePref(_kStreak, '1:$today');
    _bump();
  }
}

/// Paper options for the Bible reader.
enum BibleReadingTheme { system, light, sepia, dark }
