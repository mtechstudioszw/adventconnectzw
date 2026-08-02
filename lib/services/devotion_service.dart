import 'dart:convert';

import 'package:flutter/foundation.dart';
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

  /// The ONE devotion the whole app shows, so Home's card and the
  /// Library's verse-of-the-day can never disagree.
  ///
  /// They did disagree, daily. Home called [fetchToday] and re-rendered
  /// with the fresh devotion; the Library's verse card only ever read
  /// [cachedToday] at build time — and [cachedToday] deliberately returns
  /// YESTERDAY's devotion until a refresh lands. So every morning, and on
  /// any open where the Library was built before Home's fetch returned,
  /// the two screens quoted different verses. Worse, with an empty cache
  /// the Library fell through to its own hard-coded day-of-year list,
  /// which shares nothing with the server's devotion at all.
  ///
  /// Both screens now watch this notifier, so whichever one refreshes
  /// first updates both.
  static final ValueNotifier<Devotion?> current =
      ValueNotifier<Devotion?>(null);

  /// Seed [current] from the cache. Safe to call repeatedly; call it once
  /// during app start so the very first screen painted already agrees
  /// with every other one.
  static void primeFromCache() {
    current.value ??= _readCache();
  }

  static String _today() =>
      DateTime.now().toUtc().toIso8601String().substring(0, 10);

  /// The devotion from the local cache, read synchronously (no await)
  /// so Home can paint it on the first frame.
  ///
  /// Deliberately returns the LAST cached devotion even when it's from a
  /// previous day: the old date check made the card vanish every morning
  /// on slow networks (nothing cached "for today" until the fetch
  /// succeeded). A one-day-stale devotion is better than a hole at the
  /// top of Home — fetchToday() replaces it the moment the network lands.
  static Devotion? cachedToday() => current.value ?? _readCache();

  static Devotion? _readCache() {
    final raw = CacheService.readStringStale(_cacheKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
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
      // Publish to every listening screen at once — this is what keeps
      // Home and the Library quoting the same verse.
      current.value = devotion;
      return devotion;
    } catch (_) {
      return null;
    }
  }
}
