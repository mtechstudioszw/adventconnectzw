import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/library_item_model.dart';
import 'cache_service.dart';
import 'connectivity_service.dart';

/// Reads the in-app Library catalog (patch_128 `library_items`): hymnals,
/// music tracks and EGW books. Content is upload-driven — the user adds
/// files + rows in Supabase and they appear here with no app change.
class LibraryService {
  LibraryService._();
  static final SupabaseClient _client = Supabase.instance.client;

  static String _cacheKey(String kind) => 'library:$kind';

  /// Published items of [kind] ('hymnal' | 'music' | 'egw_book'), ordered by
  /// sort_order then newest. Serves from cache when offline so the lists
  /// (and any already-downloaded files) still browse without a connection.
  static Future<List<LibraryItem>> fetchItems(String kind) async {
    if (!ConnectivityService.isOnline) {
      return _readCache(kind);
    }
    try {
      final rows = await _client
          .from('library_items')
          .select()
          .eq('kind', kind)
          .eq('is_published', true)
          .order('sort_order', ascending: true)
          .order('created_at', ascending: false);
      final items = (rows as List)
          .map((r) => LibraryItem.fromJson(r as Map<String, dynamic>))
          .toList();
      // Cache the raw rows so an offline reopen restores the same list.
      CacheService.writeString(
        _cacheKey(kind),
        jsonEncode(rows),
      );
      return items;
    } catch (_) {
      return _readCache(kind);
    }
  }

  static List<LibraryItem> _readCache(String kind) {
    try {
      final raw = CacheService.readStringStale(_cacheKey(kind));
      if (raw == null) return const [];
      final decoded = jsonDecode(raw) as List;
      return decoded
          .map((r) => LibraryItem.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }
}
