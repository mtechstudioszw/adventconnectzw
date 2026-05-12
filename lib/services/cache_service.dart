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
    } catch (e, st) {
      debugPrint('CacheService: init failed: $e\n$st');
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

  static Future<void> clear() async {
    await _box?.clear();
  }
}
