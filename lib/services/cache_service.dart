import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Tiny key/value cache backed by Hive. Stores the last successful
/// payload for hot screens so the user sees real content (24h old or
/// less) when the device boots up offline.
///
/// Strategy mirrors Part 27 of the master reference:
///   * Home feed — last 50 items (`feed`)
///   * Followed church profiles — keyed by id (`church:<id>`)
///   * Upcoming events — single rolling list (`events`)
///
/// Values are stored as raw JSON strings (`jsonEncode(model.toJson())`)
/// so Hive doesn't need a generated TypeAdapter per model.
class CacheService {
  CacheService._();

  static const _boxName = 'advent_connect_cache_v1';
  static Box<String>? _box;
  static const Duration _maxAge = Duration(hours: 24);

  /// Open the cache box. Called once from `main()` after
  /// `Hive.initFlutter()`. Subsequent calls no-op.
  static Future<void> initialize() async {
    if (_box != null) return;
    try {
      await Hive.initFlutter();
      _box = await Hive.openBox<String>(_boxName);
      // Hive boxes are an append-only log: every feed/inbox/chat refresh
      // appends a fresh copy and tombstones the previous one, so the file
      // grows unbounded and the NEXT cold-start openBox gets slower and
      // slower (the "app got slower over time" symptom). Prune stale
      // entries + compact in the background so it never blocks launch but
      // keeps the box small for subsequent starts.
      unawaited(_pruneAndCompact());
    } catch (e, st) {
      debugPrint('CacheService: init failed: $e\n$st');
    }
  }

  /// How long LIBRARY content survives without being re-opened.
  ///
  /// Bible chapters and Sabbath School lessons are offline-first by promise —
  /// the app has an explicit "download this week" button — but they were being
  /// swept by the 24h TTL along with feed payloads. A member who downloaded a
  /// quarter on Sabbath found it gone by Monday, the Bible re-fetched books it
  /// had already stored, and the ~90-language Sabbath School picker collapsed
  /// to its two hardcoded fallbacks whenever it was opened offline a day after
  /// the last successful sync.
  ///
  /// A year is effectively permanent from the member's point of view while
  /// still letting the box reclaim content that genuinely was never revisited.
  static const Duration _libraryMaxAge = Duration(days: 365);

  /// Chat/inbox caches are read "stale" for offline, so they outlive the
  /// default TTL too, just by less.
  static const Duration _chatMaxAge = Duration(days: 7);

  /// True for offline-first Library payloads: downloaded Bible chapters,
  /// Sabbath School quarterlies / lessons / days, and the language list that
  /// makes the Sabbath School picker usable without a connection.
  static bool _isLibraryContent(String key) =>
      key.startsWith('bible:') ||
      key.startsWith('ss:') ||
      key.startsWith('ss_');

  /// Drop expired cached payloads, then rewrite the box to drop all the
  /// dead/overwritten log entries. Best-effort, off the critical path.
  static Future<void> _pruneAndCompact() async {
    final box = _box;
    if (box == null) return;
    try {
      final now = DateTime.now().toUtc();
      final toDelete = <String>[];
      for (final key in box.keys) {
        if (key is! String || key.endsWith('__ts') || key.startsWith('pref:')) {
          continue;
        }
        // The bundled Hymnal is static text that rarely changes and is never
        // pruned at all (an admin edit busts it via HymnService.invalidate +
        // refetch when back online).
        if (key.startsWith('hymns_')) continue;
        final tsRaw = box.get('${key}__ts');
        final ts = tsRaw == null ? null : DateTime.tryParse(tsRaw);
        if (ts == null) continue;
        final Duration limit;
        if (_isLibraryContent(key)) {
          limit = _libraryMaxAge;
        } else if (key == 'inbox' || key.startsWith('chat:')) {
          limit = _chatMaxAge;
        } else {
          limit = _maxAge;
        }
        if (now.difference(ts) > limit) {
          toDelete..add(key)..add('${key}__ts');
        }
      }
      if (toDelete.isNotEmpty) await box.deleteAll(toDelete);
      await box.compact();
    } catch (_) {
      // Pruning is best-effort — never let it break startup.
    }
  }

  static Future<void> writeString(String key, String value) async {
    final box = _box;
    if (box == null) return;
    await box.put(key, value);
    await box.put('${key}__ts', DateTime.now().toUtc().toIso8601String());
  }

  /// Returns the cached string if it exists and is under 24h old.
  /// Anything older is treated as stale and cleared.
  static String? readString(String key) {
    final box = _box;
    if (box == null) return null;
    final value = box.get(key);
    if (value == null) return null;
    final tsRaw = box.get('${key}__ts');
    if (tsRaw == null) return value;
    final ts = DateTime.tryParse(tsRaw);
    if (ts == null) return value;
    if (DateTime.now().toUtc().difference(ts) > _maxAge) {
      box.delete(key);
      box.delete('${key}__ts');
      return null;
    }
    return value;
  }

  /// Drop one cached payload, so the next read goes to the network.
  ///
  /// Use after a write that makes a cached list wrong — editing a church
  /// invalidates `churches_list`, otherwise the directory keeps painting
  /// the old logo from Hive for up to 24h (and indefinitely offline).
  static Future<void> invalidate(String key) async {
    final box = _box;
    if (box == null) return;
    await box.delete(key);
    await box.delete('${key}__ts');
  }

  /// When was the value at [key] last written? Returns null if there's
  /// nothing cached, or the timestamp is missing / malformed. Used by
  /// the "Updated X ago" strip on each tab so users know how fresh the
  /// list they're looking at is.
  static DateTime? cachedAt(String key) {
    final box = _box;
    if (box == null) return null;
    final tsRaw = box.get('${key}__ts');
    if (tsRaw == null) return null;
    return DateTime.tryParse(tsRaw);
  }

  static Future<void> clear() async {
    await _box?.clear();
  }

  /// Wipe every cached network payload (inbox, chats, feed, profiles, member
  /// directory, …) but KEEP device-level `pref:` settings (theme, Sabbath
  /// opt-in, etc.). Called on sign-out so the next account never briefly sees
  /// the previous user's cached data — a privacy fix for the "old chats flash
  /// then correct themselves" bug.
  static Future<void> clearUserData() async {
    final box = _box;
    if (box == null) return;
    final keys = box.keys
        .whereType<String>()
        .where((k) => !k.startsWith('pref:'))
        .toList();
    await box.deleteAll(keys);
  }

  // ---------- Long-term preferences (no TTL) -------------------------
  //
  // The TTL-tracking writeString/readString above are right for cached
  // network payloads — anything older than 24h should refetch. User
  // preferences (Sabbath countdown opt-in, etc.) need to survive
  // forever, so they get their own methods that skip the timestamp
  // dance.

  /// Write a long-term preference. Use a `pref:` prefixed key so it's
  /// easy to spot vs cached payload keys.
  static Future<void> writePref(String key, String value) async {
    final box = _box;
    if (box == null) return;
    await box.put(key, value);
  }

  /// Read a long-term preference. Returns null if absent.
  static String? readPref(String key) {
    final box = _box;
    if (box == null) return null;
    return box.get(key);
  }

  static Future<void> deletePref(String key) async {
    await _box?.delete(key);
  }

  /// Drop every `pref:` entry whose key starts with [prefix].
  ///
  /// [clearUserData] deliberately spares the whole `pref:` namespace so
  /// device settings (theme, Sabbath) survive sign-out — but a handful of
  /// `pref:` keys are USER-scoped, not device-scoped, and those leak into
  /// the next account on a shared phone. Sign-out deletes those by prefix.
  /// See [SessionReset.onSignOut] for the list and why each one is there.
  static Future<void> deletePrefsWithPrefix(String prefix) async {
    final box = _box;
    if (box == null) return;
    final keys =
        box.keys.whereType<String>().where((k) => k.startsWith(prefix)).toList();
    if (keys.isEmpty) return;
    await box.deleteAll(keys);
  }

  /// Read a cached value WITHOUT the 24h freshness gate. Used for
  /// chat caches (`inbox`, `chat:<id>`) where the user expects to
  /// see old conversations / messages offline even after a multi-day
  /// network outage. Sister of [readString] which auto-evicts stale.
  static String? readStringStale(String key) {
    return _box?.get(key);
  }
}
