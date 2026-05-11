import 'package:supabase_flutter/supabase_flutter.dart';

/// Wraps Table 22 (notification_preferences). Per-church preference
/// rows let users mute or downgrade churches without unfollowing them.
class NotificationPreferencesService {
  NotificationPreferencesService._();

  static final SupabaseClient _client = Supabase.instance.client;
  static const _table = 'notification_preferences';

  static Future<List<NotificationPreference>> fetchMyPreferences() async {
    final user = _client.auth.currentUser;
    if (user == null) return const [];
    final response = await _client
        .from(_table)
        .select('*, churches(name)')
        .eq('user_id', user.id);
    return (response as List)
        .map((row) =>
            NotificationPreference.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  /// Update the level for a specific church. `level` is one of
  /// 'all' / 'urgent' / 'none' — we translate to the three booleans
  /// the DB uses so older queries keep working.
  static Future<void> setChurchLevel({
    required String churchId,
    required String level,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to change notification settings.');
    }
    await _client.from(_table).upsert({
      'user_id': user.id,
      'church_id': churchId,
      'all_notifications': level == 'all',
      'urgent_only': level == 'urgent',
      'none': level == 'none',
    }, onConflict: 'user_id,church_id');
  }
}

class NotificationPreference {
  const NotificationPreference({
    required this.id,
    required this.churchId,
    required this.churchName,
    required this.level,
  });

  final String id;
  final String churchId;
  final String churchName;
  final String level; // 'all' / 'urgent' / 'none'

  factory NotificationPreference.fromJson(Map<String, dynamic> json) {
    final church = json['churches'];
    final churchMap = church is Map<String, dynamic> ? church : null;
    String level = 'all';
    if (json['none'] == true) {
      level = 'none';
    } else if (json['urgent_only'] == true) {
      level = 'urgent';
    }
    return NotificationPreference(
      id: json['id'].toString(),
      churchId: (json['church_id'] ?? '').toString(),
      churchName: (churchMap?['name'] as String?) ?? 'Church',
      level: level,
    );
  }
}
