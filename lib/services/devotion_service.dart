import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/devotion_model.dart';
import 'cache_service.dart';

/// Fetches the day's devotion (todays_devotion RPC, patch_108) with a local
/// cache. The devotion card is pinned to the top of Home, so it must not
/// vanish on a slow/offline open — we paint the cached copy instantly and
/// refresh in the background.
class DevotionService {
  DevotionService._();
  static final SupabaseClient _client = Supabase.instance.client;

  static const _cacheKey = 'devotion_today_v1';

  static String _today() =>
      DateTime.now().toUtc().toIso8601String().substring(0, 10);

  /// Today's devotion from the local cache, read synchronously (no await)
  /// so Home can paint it on the first frame. Returns null when nothing is
  /// cached for today's date — so we never show yesterday's devotion.
  static Devotion? cachedToday() {
    final raw = CacheService.readStringStale(_cacheKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      if (map['date'] != _today()) return null;
      return Devotion.fromJson(map['devotion'] as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Future<Devotion?> fetchToday() async {
    try {
      final res = await _client.rpc('todays_devotion');
      // The RPC returns the row (table type) — Supabase may give a Map or
      // a single-element List depending on the driver.
      final map = res is List
          ? (res.isEmpty ? null : res.first as Map<String, dynamic>)
          : res as Map<String, dynamic>?;
      if (map == null || map['bible_ref'] == null) return null;
      final devotion = Devotion.fromJson(map);
      await CacheService.writeString(
        _cacheKey,
        jsonEncode({'date': _today(), 'devotion': devotion.toJson()}),
      );
      return devotion;
    } catch (_) {
      return null;
    }
  }
}
