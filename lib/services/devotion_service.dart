import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/devotion_model.dart';

/// Fetches the day's devotion (todays_devotion RPC, patch_108).
class DevotionService {
  DevotionService._();
  static final SupabaseClient _client = Supabase.instance.client;

  static Future<Devotion?> fetchToday() async {
    try {
      final res = await _client.rpc('todays_devotion');
      // The RPC returns the row (table type) — Supabase may give a Map or
      // a single-element List depending on the driver.
      final map = res is List
          ? (res.isEmpty ? null : res.first as Map<String, dynamic>)
          : res as Map<String, dynamic>?;
      if (map == null || map['bible_ref'] == null) return null;
      return Devotion.fromJson(map);
    } catch (_) {
      return null;
    }
  }
}
