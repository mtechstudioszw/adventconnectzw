import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'cache_service.dart';

/// Wraps Table 23 (notifications). DB triggers fill the table — the
/// app only reads, marks as read, and clears. See
/// `database/patch_002_v4_completion.sql` Section 8 for the triggers.
class NotificationService {
  NotificationService._();

  static final SupabaseClient _client = Supabase.instance.client;
  static const _table = 'notifications';
  static const _cacheKey = 'notifications';

  /// Ask the server to drop a "finish your profile" nudge in this user's
  /// notifications, if their profile really is incomplete.
  ///
  /// Server-side by necessity: `notifications` has no client INSERT
  /// policy (rows come from triggers), so this goes through the
  /// patch_181 SECURITY DEFINER RPC. That function re-checks
  /// completeness itself and rate-limits to one nudge per 14 days, so
  /// calling this on every launch is safe and cheap.
  static Future<void> maybeNudgeProfileIncomplete() async {
    if (_client.auth.currentUser == null) return;
    try {
      await _client.rpc('nudge_profile_incomplete');
    } catch (_) {
      // Offline, or the migration hasn't been applied to this
      // deployment. A missing nudge is never worth surfacing.
    }
  }

  static Future<List<AppNotification>> fetchAll({int limit = 100}) async {
    final user = _client.auth.currentUser;
    if (user == null) return const [];
    final response = await _client
        .from(_table)
        .select()
        .eq('user_id', user.id)
        .order('created_at', ascending: false)
        .limit(limit);
    // Cache the raw rows so the inbox paints instantly next launch
    // (and stays readable offline). Best-effort — never blocks the fetch.
    CacheService.writeString(_cacheKey, jsonEncode(response)).ignore();
    return (response as List)
        .map((row) =>
            AppNotification.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  /// Last-known notifications from the local cache, for an instant paint
  /// before the network fetch returns. Empty when nothing is cached.
  static List<AppNotification> cached() {
    final raw = CacheService.readStringStale(_cacheKey);
    if (raw == null) return const [];
    try {
      return (jsonDecode(raw) as List)
          .map((row) => AppNotification.fromJson(row as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Lightweight count used by the bell-icon badge on home.
  static Future<int> unreadCount() async {
    final user = _client.auth.currentUser;
    if (user == null) return 0;
    final response = await _client
        .from(_table)
        .select('id')
        .eq('user_id', user.id)
        .eq('is_read', false);
    return (response as List).length;
  }

  static Future<void> markRead(String id) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    await _client
        .from(_table)
        .update({
          'is_read': true,
          'read_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', id)
        .eq('user_id', user.id);
  }

  static Future<void> markAllRead() async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    await _client
        .from(_table)
        .update({
          'is_read': true,
          'read_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('user_id', user.id)
        .eq('is_read', false);
  }

  static Future<void> delete(String id) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    await _client
        .from(_table)
        .delete()
        .eq('id', id)
        .eq('user_id', user.id);
  }

  /// Save the device FCM token onto the user's profile, and CLAIM it
  /// exclusively — clearing it from any other account that still carries
  /// the same token (patch_077). Stops a device from receiving another
  /// account's pushes (the "I get a notification for my own message" bug
  /// when several accounts share one device).
  static Future<void> updateFcmToken(String token) async {
    final user = _client.auth.currentUser;
    if (user == null || token.trim().isEmpty) return;
    try {
      await _client.rpc('claim_fcm_token', params: {'p_token': token});
    } catch (_) {
      // Fall back to a plain self-update if the RPC is unavailable.
      await _client
          .from('profiles')
          .update({'fcm_token': token})
          .eq('id', user.id);
    }
  }
}

class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.isRead,
    required this.createdAt,
    this.referenceId,
    this.referenceType,
  });

  final String id;
  final String title;
  final String body;
  final String type;
  final String? referenceId;
  final String? referenceType;
  final bool isRead;
  final DateTime createdAt;

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'].toString(),
      title: (json['title'] ?? '') as String,
      body: (json['body'] ?? '') as String,
      type: (json['type'] ?? 'general') as String,
      referenceId: json['reference_id']?.toString(),
      referenceType: json['reference_type'] as String?,
      isRead: json['is_read'] == true,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}
