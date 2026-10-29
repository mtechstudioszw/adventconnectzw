import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/hymn_model.dart';
import 'cache_service.dart';

/// Christ in Song number → SDA Hymnal number (patch_285 `hymn_links`).
///
/// One row per Christ in Song number links EVERY vernacular edition at once,
/// because they share the numbering. Rows are entered by super admins from
/// the printed hymnal; a number with no row simply shows no link — nothing
/// is guessed.
///
/// Cached in Hive so links work offline after one successful fetch.
class HymnLinkService {
  HymnLinkService._();

  static const _cacheKey = 'hymn_links_v1';

  static final ValueNotifier<Map<int, int>> links =
      ValueNotifier<Map<int, int>>(const {});

  static bool _primed = false;

  /// Loads the cached links (synchronously) once.
  static void prime() {
    if (_primed) return;
    _primed = true;
    try {
      final raw = CacheService.readStringStale(_cacheKey);
      if (raw != null) links.value = decode(raw);
    } catch (_) {}
  }

  /// Public for the tests.
  static Map<int, int> decode(String raw) {
    try {
      final map = jsonDecode(raw) as Map;
      return {
        for (final e in map.entries)
          if (int.tryParse('${e.key}') != null && e.value is num)
            int.parse('${e.key}'): (e.value as num).toInt(),
      };
    } catch (_) {
      return const {};
    }
  }

  /// Best-effort refresh. Never throws (the table may not exist yet on an
  /// older database, or the phone may be offline).
  static Future<void> refresh() async {
    prime();
    try {
      final rows = await Supabase.instance.client
          .from('hymn_links')
          .select('cis_number,sda_number')
          .timeout(const Duration(seconds: 10));
      final map = <int, int>{
        for (final r in rows as List)
          ((r as Map)['cis_number'] as num).toInt(): (r['sda_number'] as num)
              .toInt(),
      };
      links.value = map;
      await CacheService.writeString(
        _cacheKey,
        jsonEncode(map.map((k, v) => MapEntry('$k', v))),
      );
    } catch (e) {
      debugPrint('HymnLinkService.refresh skipped: $e');
    }
  }

  static int? sdaFor(int cisNumber) => links.value[cisNumber];

  /// Christ in Song numbers that point at [sdaNumber] (usually one).
  static List<int> cisFor(int sdaNumber) => [
    for (final e in links.value.entries)
      if (e.value == sdaNumber) e.key,
  ]..sort();

  /// Super admins only (RLS). Null [sdaNumber] removes the link.
  static Future<void> save(int cisNumber, int? sdaNumber) async {
    final table = Supabase.instance.client.from('hymn_links');
    if (sdaNumber == null) {
      await table.delete().eq('cis_number', cisNumber);
    } else {
      await table.upsert({'cis_number': cisNumber, 'sda_number': sdaNumber});
    }
    final map = {...links.value};
    sdaNumber == null ? map.remove(cisNumber) : map[cisNumber] = sdaNumber;
    links.value = map;
    await CacheService.writeString(
      _cacheKey,
      jsonEncode(map.map((k, v) => MapEntry('$k', v))),
    );
  }

  /// The same song in the other hymnals the app has, in switcher order:
  /// for a Christ in Song hymn, the same number in every other language
  /// plus its SDA Hymnal number when linked; for an SDA Hymnal hymn, the
  /// Christ in Song editions that link to it.
  static List<Hymn> counterparts(
    Hymn hymn,
    Iterable<Hymn> all, {
    Map<int, int>? linkMap,
  }) {
    final number = hymn.number;
    if (number == null) return const [];
    final map = linkMap ?? links.value;
    final family = HymnCollection.fromKey(hymn.collection).family;

    final wanted = <(String, int)>{}; // (collection, number)
    if (family != null) {
      for (final c in HymnCollection.known) {
        if (c.family == family && c.key != hymn.collection) {
          wanted.add((c.key, number));
        }
      }
      final sda = map[number];
      if (sda != null) wanted.add((HymnCollection.sdaHymnal.key, sda));
    } else if (hymn.collection == HymnCollection.sdaHymnal.key) {
      for (final e in map.entries) {
        if (e.value != number) continue;
        for (final c in HymnCollection.known) {
          if (c.family == HymnCollection.christInSong) {
            wanted.add((c.key, e.key));
          }
        }
      }
    }
    if (wanted.isEmpty) return const [];

    final found = [
      for (final h in all)
        if (h.number != null && wanted.contains((h.collection, h.number!))) h,
    ];
    final order = [for (final c in HymnCollection.known) c.key];
    found.sort((a, b) {
      final c = order
          .indexOf(a.collection)
          .compareTo(order.indexOf(b.collection));
      return c != 0 ? c : a.number!.compareTo(b.number!);
    });
    return found;
  }

  @visibleForTesting
  static void debugSet(Map<int, int> map) {
    _primed = true;
    links.value = map;
  }
}
