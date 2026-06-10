import 'package:supabase_flutter/supabase_flutter.dart';

/// Group-chat management. Thin wrappers over the patch_053/054 SECURITY
/// DEFINER RPCs. A group is a conversations row (is_group=TRUE) whose
/// members live in conversation_members — so once created, everything
/// else (chat screen, media, receipts) reuses the normal chat stack.
class GroupService {
  GroupService._();
  static final SupabaseClient _client = Supabase.instance.client;

  /// Creates a group and returns its conversation id. [memberIds] are the
  /// other members; the caller is added as admin automatically.
  static Future<String> createGroup({
    required String name,
    String? photoUrl,
    String? description,
    required List<String> memberIds,
  }) async {
    final id = await _client.rpc('create_group', params: {
      'p_name': name,
      'p_photo_url': photoUrl,
      'p_description': description,
      'p_member_ids': memberIds,
    });
    return id.toString();
  }

  static Future<void> addMembers(String conversationId, List<String> userIds) {
    return _client.rpc('add_group_members', params: {
      'p_conversation': int.parse(conversationId),
      'p_user_ids': userIds,
    });
  }

  static Future<void> removeMember(String conversationId, String userId) {
    return _client.rpc('remove_group_member', params: {
      'p_conversation': int.parse(conversationId),
      'p_user_id': userId,
    });
  }

  static Future<void> setAdmin(
    String conversationId,
    String userId, {
    required bool makeAdmin,
  }) {
    return _client.rpc('set_group_admin', params: {
      'p_conversation': int.parse(conversationId),
      'p_user_id': userId,
      'p_make_admin': makeAdmin,
    });
  }

  static Future<void> updateGroup(
    String conversationId, {
    String? name,
    String? photoUrl,
    String? description,
  }) {
    return _client.rpc('update_group', params: {
      'p_conversation': int.parse(conversationId),
      'p_name': name,
      'p_photo_url': photoUrl,
      'p_description': description,
    });
  }

  static Future<void> leaveGroup(String conversationId) {
    return _client.rpc('leave_group', params: {
      'p_conversation': int.parse(conversationId),
    });
  }

  static Future<void> deleteGroup(String conversationId) {
    return _client.rpc('delete_group', params: {
      'p_conversation': int.parse(conversationId),
    });
  }

  /// Remove the group from MY list (after I've left) — deletes my
  /// membership row only (patch_079). The group stays for everyone else.
  static Future<void> deleteGroupConversation(String conversationId) {
    return _client.rpc('delete_group_conversation', params: {
      'p_conversation': int.parse(conversationId),
    });
  }

  /// Members of a group, each as {user_id, role, full_name,
  /// profile_photo_url}. Admins first, then alphabetical.
  static Future<List<GroupMember>> fetchMembers(String conversationId) async {
    final rows = await _client
        .from('conversation_members')
        .select(
          'user_id, role, '
          'profiles!conversation_members_user_id_fkey('
          'id, full_name, profile_photo_url)',
        )
        .eq('conversation_id', int.parse(conversationId))
        // Members who left (patch_079) keep their row but aren't shown.
        .isFilter('left_at', null);
    final list = (rows as List).map((r) {
      final map = r as Map<String, dynamic>;
      final p = map['profiles'] as Map<String, dynamic>?;
      return GroupMember(
        userId: map['user_id'].toString(),
        role: (map['role'] ?? 'member').toString(),
        fullName: (p?['full_name'] as String?)?.trim().isNotEmpty == true
            ? (p!['full_name'] as String).trim()
            : 'Member',
        photoUrl: p?['profile_photo_url'] as String?,
      );
    }).toList();
    list.sort((a, b) {
      if (a.isAdmin != b.isAdmin) return a.isAdmin ? -1 : 1;
      return a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase());
    });
    return list;
  }

  /// Members of a CHURCH group (implicit membership via profiles.church_id,
  /// patch_078). No admins/roles — everyone is a plain member.
  static Future<List<GroupMember>> fetchChurchMembers(
      String conversationId) async {
    final rows = await _client.rpc('church_conversation_members', params: {
      'p_conv': int.parse(conversationId),
    });
    if (rows is! List) return const [];
    return rows.map((r) {
      final map = r as Map<String, dynamic>;
      return GroupMember(
        userId: map['user_id'].toString(),
        role: 'member',
        fullName: (map['full_name'] as String?)?.trim().isNotEmpty == true
            ? (map['full_name'] as String).trim()
            : 'Member',
        photoUrl: map['photo_url'] as String?,
      );
    }).toList();
  }

  /// Get (or lazily create) the shareable invite token for a group.
  static Future<String> inviteToken(String conversationId) async {
    final token = await _client.rpc('get_or_create_group_invite', params: {
      'p_conversation': int.parse(conversationId),
    });
    return token.toString();
  }

  /// Join a group from an invite token; returns the conversation id.
  static Future<String> joinViaInvite(String token) async {
    final id = await _client.rpc('join_group_via_invite', params: {
      'p_token': token,
    });
    return id.toString();
  }
}

class GroupMember {
  const GroupMember({
    required this.userId,
    required this.role,
    required this.fullName,
    this.photoUrl,
  });

  final String userId;
  final String role;
  final String fullName;
  final String? photoUrl;

  bool get isAdmin => role == 'admin';
}
