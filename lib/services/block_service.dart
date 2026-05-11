import 'package:supabase_flutter/supabase_flutter.dart';

/// Reads/writes for Table 26 (blocked_users). RLS keeps each user's
/// block list private.
class BlockService {
  BlockService._();

  static final SupabaseClient _client = Supabase.instance.client;
  static const _table = 'blocked_users';

  static Future<List<BlockedUser>> fetchMyBlocked() async {
    final user = _client.auth.currentUser;
    if (user == null) return const [];
    final response = await _client
        .from(_table)
        .select('*, profiles!blocked_users_blocked_id_fkey(full_name, profile_photo_url)')
        .eq('blocker_id', user.id)
        .order('created_at', ascending: false);
    return (response as List)
        .map((row) => BlockedUser.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  static Future<void> block(String userId) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to block someone.');
    }
    if (user.id == userId) {
      throw const AuthException('You can\'t block yourself.');
    }
    await _client.from(_table).insert({
      'blocker_id': user.id,
      'blocked_id': userId,
    });
  }

  static Future<void> unblock(String userId) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    await _client
        .from(_table)
        .delete()
        .eq('blocker_id', user.id)
        .eq('blocked_id', userId);
  }
}

class BlockedUser {
  const BlockedUser({
    required this.id,
    required this.blockedId,
    required this.createdAt,
    this.fullName,
    this.profilePhotoUrl,
  });

  final String id;
  final String blockedId;
  final DateTime createdAt;
  final String? fullName;
  final String? profilePhotoUrl;

  factory BlockedUser.fromJson(Map<String, dynamic> json) {
    final profile = json['profiles'];
    final profileMap = profile is Map<String, dynamic> ? profile : null;
    return BlockedUser(
      id: json['id'].toString(),
      blockedId: (json['blocked_id'] ?? '').toString(),
      fullName: profileMap?['full_name'] as String?,
      profilePhotoUrl: profileMap?['profile_photo_url'] as String?,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}
