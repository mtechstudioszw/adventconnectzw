import 'dart:convert';

import 'package:flutter/foundation.dart' show ValueNotifier;

import 'cache_service.dart';
import 'search_typeahead_service.dart';

/// The people, Pages, products and churches a member opened from Search,
/// newest first — shown as faces and logos on the Search landing, the way
/// Facebook does ("Recent").
///
/// On the device only, and user-scoped: the key has no `pref:` prefix, so
/// sign-out clears it (CLAUDE.md) and the next person on a shared phone
/// doesn't see who the last one looked up.
class SearchHistoryService {
  SearchHistoryService._();

  static const _key = 'search_recent_items_v1';
  static const max = 12;

  static final ValueNotifier<List<SearchHit>> items = ValueNotifier(const []);

  /// Kinds worth remembering — a verse or hymn is a jump, not a "who".
  static const _kept = {
    SearchHitKind.person,
    SearchHitKind.page,
    SearchHitKind.church,
    SearchHitKind.product,
    SearchHitKind.job,
  };

  static bool _loaded = false;

  /// Reads the saved list once per session (it's kept in memory after).
  static void load() {
    if (_loaded) return;
    _loaded = true;
    try {
      final raw = CacheService.readStringStale(_key);
      if (raw == null) {
        items.value = const [];
        return;
      }
      items.value = [
        for (final e in jsonDecode(raw) as List)
          if (e is Map) _fromJson(e.cast<String, dynamic>()),
      ].whereType<SearchHit>().toList();
    } catch (_) {
      items.value = const [];
    }
  }

  static Future<void> add(SearchHit hit) async {
    if (!_kept.contains(hit.kind)) return;
    load();
    final next = [
      hit,
      ...items.value.where((h) => !(h.kind == hit.kind && h.id == hit.id)),
    ].take(max).toList();
    items.value = next;
    await _persist();
  }

  static Future<void> remove(SearchHit hit) async {
    items.value = [
      for (final h in items.value)
        if (!(h.kind == hit.kind && h.id == hit.id)) h,
    ];
    await _persist();
  }

  /// Sign-out wipes the stored key; forget the in-memory copy too.
  static void reset() {
    _loaded = false;
    items.value = const [];
  }

  static Future<void> clear() async {
    items.value = const [];
    await _persist();
  }

  static Future<void> _persist() async {
    try {
      await CacheService.writeString(
        _key,
        jsonEncode([for (final h in items.value) _toJson(h)]),
      );
    } catch (_) {}
  }

  static Map<String, dynamic> _toJson(SearchHit h) => {
    'kind': h.kind.name,
    'id': h.id,
    'title': h.title,
    'subtitle': h.subtitle,
    'image': h.imageUrl,
    'verified': h.verified,
  };

  static SearchHit? _fromJson(Map<String, dynamic> j) {
    final kind = SearchHitKind.values
        .where((k) => k.name == j['kind'])
        .firstOrNull;
    if (kind == null || j['id'] == null) return null;
    return SearchHit(
      kind: kind,
      id: j['id'].toString(),
      title: (j['title'] ?? '').toString(),
      subtitle: j['subtitle'] as String?,
      imageUrl: j['image'] as String?,
      verified: j['verified'] == true,
    );
  }
}
