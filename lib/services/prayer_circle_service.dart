import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/prayer_circle_model.dart';

/// Prayer circles (patch_170) — named, invite-only groups a prayer can be
/// scoped to.
///
/// Every read here is already constrained by RLS: `prayer_circles` is
/// visible only to its owner and members, and a circle prayer is readable
/// only by members. The client-side filtering below is for ordering and
/// shape, never for access control.
class PrayerCircleService {
  PrayerCircleService._();

  static final SupabaseClient _client = Supabase.instance.client;

  static const _circles = 'prayer_circles';
  static const _members = 'prayer_circle_members';

  /// Circles the signed-in user owns or belongs to, with member counts.
  static Future<List<PrayerCircle>> fetchMine() async {
    final user = _client.auth.currentUser;
    if (user == null) return const [];
    final rows = await _client
        .from(_circles)
        .select('id, name, owner_id, created_at, '
            'prayer_circle_members(count)')
        .order('created_at', ascending: false);
    return (rows as List)
        .map((r) => PrayerCircle.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// Create a circle and add the owner as its first member.
  ///
  /// The owner is inserted into the membership table explicitly rather
  /// than being implied by `owner_id`: the prayers SELECT policy tests
  /// membership, so an owner who wasn't a member couldn't read the
  /// prayers posted to their own circle.
  static Future<PrayerCircle> create(String name) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to create a prayer circle.');
    }
    final trimmed = name.trim();
    final row = await _client
        .from(_circles)
        .insert({'name': trimmed, 'owner_id': user.id})
        .select('id, name, owner_id, created_at')
        .single();
    final circle = PrayerCircle.fromJson(row);
    await _client
        .from(_members)
        .insert({'circle_id': circle.id, 'user_id': user.id});
    return circle.copyWith(memberCount: 1);
  }

  static Future<void> rename(String circleId, String name) async {
    await _client
        .from(_circles)
        .update({'name': name.trim()}).eq('id', circleId);
  }

  /// Delete a circle. Prayers posted to it are NOT deleted — the FK is
  /// ON DELETE SET NULL, so they revert to normal visibility rather than
  /// vanishing. Worth knowing before offering this in the UI: it widens
  /// the audience of anything already posted there.
  static Future<void> delete(String circleId) async {
    await _client.from(_circles).delete().eq('id', circleId);
  }

  static Future<List<PrayerCircleMember>> fetchMembers(String circleId) async {
    final rows = await _client
        .from(_members)
        .select('user_id, profiles:user_id(full_name, profile_photo_url)')
        .eq('circle_id', circleId);
    return (rows as List).map((r) {
      final map = r as Map<String, dynamic>;
      final profile = map['profiles'] as Map<String, dynamic>?;
      final name = (profile?['full_name'] as String?)?.trim();
      final photo = (profile?['profile_photo_url'] as String?)?.trim();
      return PrayerCircleMember(
        userId: map['user_id']?.toString() ?? '',
        fullName: name?.isNotEmpty == true ? name! : 'A friend',
        photoUrl: photo?.isNotEmpty == true ? photo : null,
      );
    }).toList();
  }

  /// Add someone to a circle. Owner-only, enforced by RLS — a non-owner
  /// insert is rejected server-side, not merely hidden in the UI.
  static Future<void> addMember(String circleId, String userId) async {
    try {
      await _client
          .from(_members)
          .insert({'circle_id': circleId, 'user_id': userId});
    } on PostgrestException catch (e) {
      // Already a member — the composite PK rejected the duplicate.
      // That is the desired end state, so treat it as success.
      if (e.code != '23505') rethrow;
    }
  }

  static Future<void> removeMember(String circleId, String userId) async {
    await _client
        .from(_members)
        .delete()
        .eq('circle_id', circleId)
        .eq('user_id', userId);
  }
}
