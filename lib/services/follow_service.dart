import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Where the viewer stands with a profile.
enum FollowState { none, requested, following }

/// Follower and following counts plus the viewer's relationship.
class FollowStats {
  const FollowStats({
    required this.followers,
    required this.following,
    required this.state,
    required this.followsMe,
  });

  final int followers;
  final int following;
  final FollowState state;

  /// They follow the viewer ("Follows you").
  final bool followsMe;

  static const empty = FollowStats(
    followers: 0,
    following: 0,
    state: FollowState.none,
    followsMe: false,
  );
}

/// One person in a followers / following / requests list.
class FollowPerson {
  const FollowPerson({
    required this.userId,
    required this.fullName,
    this.username,
    this.photoUrl,
    this.isVerified = false,
  });

  final String userId;
  final String fullName;
  final String? username;
  final String? photoUrl;
  final bool isVerified;

  factory FollowPerson.fromRow(Map<String, dynamic> r) => FollowPerson(
    userId: r['user_id'].toString(),
    fullName: (r['full_name'] as String?)?.trim().isNotEmpty == true
        ? (r['full_name'] as String).trim()
        : 'Member',
    username: r['username'] as String?,
    photoUrl: r['profile_photo_url'] as String?,
    isVerified: r['is_verified'] == true,
  );
}

/// One-way following, alongside friends (patch_274).
///
/// Friends are mutual and live in `friendships`, untouched. Following is a
/// subscription to someone's public updates. The SERVER decides whether a
/// follow is active or pending (private profiles approve), applies blocks,
/// and serves counts and lists through privacy-checking functions — this
/// class never decides any of that.
class FollowService {
  FollowService._();

  static final SupabaseClient _client = Supabase.instance.client;

  /// False until patch_274's table answers — screens say so instead of
  /// pretending a follow happened.
  static bool available = true;

  /// Bumped after any follow change so headers and lists refresh.
  static final ValueNotifier<int> revision = ValueNotifier(0);

  /// Members the viewer follows (active or requested), for the post menu's
  /// Follow / Unfollow. Null until loaded — the menu leaves the item out
  /// rather than guess.
  static final ValueNotifier<Set<String>?> followingIds = ValueNotifier(null);

  static void _mark(String userId, bool following) {
    final current = followingIds.value;
    if (current == null) return;
    followingIds.value = following
        ? {...current, userId}
        : ({...current}..remove(userId));
  }

  /// Fills [followingIds]. Reads the viewer's own rows directly (RLS lets
  /// either party see a row), so pending requests count as followed too.
  static Future<void> loadMyFollowing() async {
    final me = _client.auth.currentUser?.id;
    if (me == null) return;
    try {
      final rows = await _client
          .from('follows')
          .select('followee_id')
          .eq('follower_id', me);
      available = true;
      followingIds.value = {
        for (final r in rows as List) (r as Map)['followee_id'].toString(),
      };
    } catch (e) {
      if (_missing(e)) available = false;
    }
  }

  static bool _missing(Object e) {
    final s = e.toString();
    return s.contains('follows') ||
        s.contains('profile_follow_stats') ||
        s.contains('list_follows') ||
        s.contains('my_follow_requests') ||
        s.contains('PGRST202') ||
        s.contains('PGRST205') ||
        s.contains('42P01');
  }

  static Future<FollowStats> stats(String userId) async {
    try {
      final res = await _client.rpc(
        'profile_follow_stats',
        params: {'target': userId},
      );
      available = true;
      final row = res is List
          ? (res.isEmpty ? null : res.first as Map<String, dynamic>)
          : res as Map<String, dynamic>?;
      if (row == null) return FollowStats.empty;
      final status = row['i_follow'] as String?;
      return FollowStats(
        followers: (row['followers'] as num?)?.toInt() ?? 0,
        following: (row['following'] as num?)?.toInt() ?? 0,
        state: status == 'active'
            ? FollowState.following
            : status == 'pending'
            ? FollowState.requested
            : FollowState.none,
        followsMe: row['follows_me'] == true,
      );
    } catch (e) {
      if (_missing(e)) available = false;
      rethrow;
    }
  }

  /// Follow [userId]. Returns the state the server chose: following for a
  /// public profile, requested for a private one.
  static Future<FollowState> follow(String userId) async {
    final me = _client.auth.currentUser?.id;
    if (me == null) throw const AuthException('Sign in to follow people.');
    try {
      final row = await _client
          .from('follows')
          .insert({'follower_id': me, 'followee_id': userId})
          .select('status')
          .single();
      revision.value++;
      _mark(userId, true);
      return row['status'] == 'pending'
          ? FollowState.requested
          : FollowState.following;
    } catch (e) {
      if (_missing(e)) available = false;
      rethrow;
    }
  }

  /// Unfollow, or withdraw a pending request.
  static Future<void> unfollow(String userId) async {
    final me = _client.auth.currentUser?.id;
    if (me == null) return;
    await _client
        .from('follows')
        .delete()
        .eq('follower_id', me)
        .eq('followee_id', userId);
    revision.value++;
    _mark(userId, false);
  }

  /// Remove someone who follows you, or decline their request.
  static Future<void> removeFollower(String userId) async {
    final me = _client.auth.currentUser?.id;
    if (me == null) return;
    await _client
        .from('follows')
        .delete()
        .eq('follower_id', userId)
        .eq('followee_id', me);
    revision.value++;
  }

  static Future<void> approve(String userId) async {
    final me = _client.auth.currentUser?.id;
    if (me == null) return;
    final rows = await _client
        .from('follows')
        .update({'status': 'active'})
        .eq('follower_id', userId)
        .eq('followee_id', me)
        .select('follower_id');
    if ((rows as List).isEmpty) {
      throw StateError('follow request from $userId was not approved');
    }
    revision.value++;
  }

  /// [direction] is 'followers' or 'following'. Empty when the profile is
  /// private and the viewer may not see it (the server decides).
  static Future<List<FollowPerson>> list(
    String userId,
    String direction,
  ) async {
    try {
      final rows = await _client.rpc(
        'list_follows',
        params: {'target': userId, 'direction': direction},
      );
      return [
        for (final r in rows as List)
          FollowPerson.fromRow(r as Map<String, dynamic>),
      ];
    } catch (e) {
      if (_missing(e)) available = false;
      rethrow;
    }
  }

  static Future<List<FollowPerson>> myRequests() async {
    try {
      final rows = await _client.rpc('my_follow_requests');
      return [
        for (final r in rows as List)
          FollowPerson.fromRow(r as Map<String, dynamic>),
      ];
    } catch (e) {
      if (_missing(e)) available = false;
      rethrow;
    }
  }
}
