import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/hymn_model.dart';
import 'cache_service.dart';
import 'connectivity_service.dart';

/// Reads the structured Hymnal (patch_129 `hymns`). The full list is cached
/// locally so browsing + searching work offline once loaded — modern hymnal
/// apps are expected to work without a connection.
class HymnService {
  HymnService._();
  static final SupabaseClient _client = Supabase.instance.client;

  static const _cacheKey = 'hymns_all_v1';
  static List<Hymn>? _mem;

  /// Drop the in-memory cache so the next [all]/[search] re-fetches. Called
  /// after an admin adds/edits/removes a hymn so the change shows immediately.
  static void invalidate() => _mem = null;

  /// All published hymns, ordered by number. Memory-cached after first load.
  static Future<List<Hymn>> all() async {
    final mem = _mem;
    if (mem != null) return mem;

    if (!ConnectivityService.isOnline) {
      return _mem = _readCache();
    }
    try {
      final rows = await _client
          .from('hymns')
          .select()
          .eq('is_published', true)
          .order('number', ascending: true)
          .order('title', ascending: true);
      final hymns = (rows as List)
          .map((r) => Hymn.fromJson(r as Map<String, dynamic>))
          .toList();
      CacheService.writeString(_cacheKey, jsonEncode(rows));
      return _mem = hymns;
    } catch (_) {
      return _mem = _readCache();
    }
  }

  static List<Hymn> _readCache() {
    try {
      final raw = CacheService.readStringStale(_cacheKey);
      if (raw == null) return const [];
      return (jsonDecode(raw) as List)
          .map((r) => Hymn.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Local search across number, title and lyrics. A bare number matches the
  /// hymn number exactly first (so "23" jumps to hymn 23), then falls back to
  /// substring matches on title/lyrics. All words must appear.
  static Future<List<Hymn>> search(String query) async {
    final q = query.trim().toLowerCase();
    final hymns = await all();
    if (q.isEmpty) return hymns;

    // Pure-number query → exact number match floated to the top.
    final asNumber = int.tryParse(q);
    final terms = q.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();

    final scored = <(int, Hymn)>[];
    for (final h in hymns) {
      final hay = '${h.number ?? ''} ${h.title} ${h.lyrics}'.toLowerCase();
      final titleLower = h.title.toLowerCase();
      if (!terms.every(hay.contains)) continue;
      var score = 0;
      if (asNumber != null && h.number == asNumber) score += 1000;
      if (titleLower.contains(q)) score += 100;
      if (titleLower.startsWith(q)) score += 50;
      scored.add((score, h));
    }
    scored.sort((a, b) {
      if (a.$1 != b.$1) return b.$1.compareTo(a.$1);
      final an = a.$2.number ?? 1 << 30;
      final bn = b.$2.number ?? 1 << 30;
      return an.compareTo(bn);
    });
    return scored.map((e) => e.$2).toList();
  }
}
