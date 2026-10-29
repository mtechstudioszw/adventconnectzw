import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Who may follow a member (patch_282). Personal accounts only — Pages can
/// always be followed.
///
/// Since patch_287 (29 Oct 2026, owner) every account starts PERSONAL —
/// followers off ([nobody]) — and the member turns "Allow followers" on
/// ([everyone]) if they post publicly: pastors, leaders, musicians,
/// ministries. [friends] is kept for anyone who already chose it; the app
/// no longer offers it, because two kinds of "on" was one too many.
enum WhoCanFollow { everyone, friends, nobody }

extension WhoCanFollowX on WhoCanFollow {
  String get wire => name;

  /// Followers on — anyone (or, for older settings, friends) can follow.
  bool get allowsFollowers => this != WhoCanFollow.nobody;

  String get label => switch (this) {
    WhoCanFollow.everyone => 'On',
    WhoCanFollow.friends => 'Friends only',
    WhoCanFollow.nobody => 'Off',
  };

  String get description => switch (this) {
    WhoCanFollow.everyone =>
      'Anyone can follow your public posts. Friends still see your '
          'friends-only posts.',
    WhoCanFollow.friends => 'Only your friends can follow you.',
    WhoCanFollow.nobody =>
      'Personal account: people connect with you by adding you as a '
          'friend. Nobody can follow you.',
  };

  /// Missing or unknown = off: that is the default since patch_287, and
  /// guessing "on" would show a Follow button the server then refuses.
  static WhoCanFollow fromWire(String? v) => switch (v) {
    'everyone' => WhoCanFollow.everyone,
    'friends' => WhoCanFollow.friends,
    _ => WhoCanFollow.nobody,
  };
}

/// The member's "who can follow me" setting refused this follow.
class FollowNotAllowed implements Exception {
  const FollowNotAllowed();
}

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
      // patch_282's gate. Checked first: it's a refusal, not a missing
      // table.
      if (e.toString().contains('FOLLOW_NOT_ALLOWED')) {
        throw const FollowNotAllowed();
      }
      if (_missing(e)) available = false;
      rethrow;
    }
  }

  /// Sources whose post alerts the viewer muted (patch_283), as
  /// `user:ID` / `page:ID`. Null until loaded or before the patch — the
  /// mute item is then left out rather than offered and failing.
  static final ValueNotifier<Set<String>?> mutedAlerts = ValueNotifier(null);

  static String alertKey(String type, String id) => '$type:$id';

  static Future<void> loadAlertMutes() async {
    final me = _client.auth.currentUser?.id;
    if (me == null) return;
    try {
      final rows = await _client
          .from('follow_alert_mutes')
          .select('target_type, target_id')
          .eq('user_id', me);
      mutedAlerts.value = {
        for (final r in rows as List)
          alertKey((r as Map)['target_type'].toString(), '${r['target_id']}'),
      };
    } catch (_) {
      // Before patch_283: no mute table. Leave null.
    }
  }

  /// Mute or unmute "new post" alerts from a person ([type] 'user') or a
  /// Page ('page') you follow. Following itself is unchanged.
  static Future<void> setAlertsMuted({
    required String type,
    required String id,
    required bool muted,
  }) async {
    final me = _client.auth.currentUser?.id;
    if (me == null) throw const AuthException('Sign in first.');
    if (muted) {
      await _client.from('follow_alert_mutes').upsert({
        'user_id': me,
        'target_type': type,
        'target_id': id,
      }, ignoreDuplicates: true);
    } else {
      await _client
          .from('follow_alert_mutes')
          .delete()
          .eq('user_id', me)
          .eq('target_type', type)
          .eq('target_id', id);
    }
    final key = alertKey(type, id);
    final current = mutedAlerts.value ?? <String>{};
    mutedAlerts.value = muted
        ? {...current, key}
        : ({...current}..remove(key));
  }

  /// The viewer's own setting, or null before patch_282 — the setting is
  /// then left out of Edit profile rather than offered and failing.
  static Future<WhoCanFollow?> myWhoCanFollow() async {
    final me = _client.auth.currentUser?.id;
    if (me == null) return null;
    try {
      final row = await _client
          .from('profiles')
          .select('who_can_follow')
          .eq('id', me)
          .maybeSingle();
      if (row == null) return null;
      return WhoCanFollowX.fromWire(row['who_can_follow'] as String?);
    } catch (_) {
      return null;
    }
  }

  /// How many current followers switching to [value] would remove — for
  /// the warning before [setWhoCanFollow].
  static Future<int> followersRemovedBy(WhoCanFollow value) async {
    final res = await _client.rpc(
      'followers_removed_by',
      params: {'p_value': value.wire},
    );
    return (res as num?)?.toInt() ?? 0;
  }

  /// Saves the setting. The server removes followers it no longer allows
  /// and returns how many.
  static Future<int> setWhoCanFollow(WhoCanFollow value) async {
    final res = await _client.rpc(
      'set_who_can_follow',
      params: {'p_value': value.wire},
    );
    revision.value++;
    return (res as num?)?.toInt() ?? 0;
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
