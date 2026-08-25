import 'package:supabase_flutter/supabase_flutter.dart';

import 'presence_service.dart';

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

  /// Is there a block between me and [userId], in EITHER direction?
  ///
  /// The symmetric question (patch_200). This is the right one for
  /// CONTENT — you block someone to stop seeing them, so their posts and
  /// stories should leave your feed too.
  ///
  /// It is the WRONG one for deciding whether a profile reads as
  /// unavailable: it hid the blocked person from the blocker, along with
  /// the Unblock button. Use [hasBlockedMe] there.
  static Future<bool> isBlockedEitherWay(String userId) async {
    try {
      final res =
          await _client.rpc('is_blocked_by', params: {'p_author': userId});
      return res == true;
    } catch (_) {
      return false;
    }
  }

  /// Has [userId] blocked ME?
  ///
  /// One-directional (patch_266). True only when THEY blocked me, so the
  /// person who did the blocking still sees the account they blocked —
  /// which is how they unblock it, and what WhatsApp does.
  ///
  /// Must go through the SECURITY DEFINER RPC: `blocked_users` RLS hides
  /// the other person's rows, so a direct query returns nothing whether
  /// they blocked you or not.
  static Future<bool> hasBlockedMe(String userId) async {
    try {
      final res =
          await _client.rpc('has_blocked_me', params: {'p_user': userId});
      return res == true;
    } catch (_) {
      // Fail OPEN. A network blip must not make a normal profile read as
      // "unavailable" — the server still refuses anything that matters
      // (messages, calls, content) on its own.
      return false;
    }
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
    // Presence is a realtime channel with no RLS behind it, so blocking
    // does not take the green dot away on its own — the client has to be
    // told (patch_210). Without this the person you just blocked keeps
    // showing as "Online" until the next launch.
    await PresenceService.refreshHidden();
  }

  static Future<void> unblock(String userId) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    await _client
        .from(_table)
        .delete()
        .eq('blocker_id', user.id)
        .eq('blocked_id', userId);
    await PresenceService.refreshHidden();
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
