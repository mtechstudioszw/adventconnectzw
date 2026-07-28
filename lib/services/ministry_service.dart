import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/ministry_tag_model.dart';

/// Ministry involvement and spiritual gifts (patch_168).
///
/// `ministry_tags` is reference data — small, static, and read on every
/// profile open — so the vocabulary is cached for the process lifetime
/// after the first fetch. The per-profile join is never cached: it
/// changes as soon as the user edits it.
class MinistryService {
  MinistryService._();

  static final SupabaseClient _client = Supabase.instance.client;

  static const _tagsTable = 'ministry_tags';
  static const _joinTable = 'profile_ministry_tags';

  static List<MinistryTag>? _vocabularyCache;

  /// The full controlled vocabulary, ordered for display. Cached after
  /// the first successful read.
  static Future<List<MinistryTag>> fetchVocabulary() async {
    final cached = _vocabularyCache;
    if (cached != null) return cached;
    final rows = await _client
        .from(_tagsTable)
        .select('id, code, label, kind, sort_order')
        .order('sort_order');
    final tags = (rows as List)
        .map((r) => MinistryTag.fromJson(r as Map<String, dynamic>))
        .toList();
    _vocabularyCache = tags;
    return tags;
  }

  /// Tags claimed by [profileId]. RLS returns an empty list rather than
  /// an error when the profile is private and isn't the caller's, so a
  /// locked-down profile simply shows no chips.
  static Future<List<MinistryTag>> fetchForProfile(String profileId) async {
    if (profileId.isEmpty) return const [];
    final rows = await _client
        .from(_joinTable)
        .select('tag_id, ministry_tags:tag_id(id, code, label, kind, sort_order)')
        .eq('profile_id', profileId);
    final tags = <MinistryTag>[];
    for (final row in rows as List) {
      final nested = (row as Map<String, dynamic>)['ministry_tags'];
      if (nested is Map<String, dynamic>) {
        tags.add(MinistryTag.fromJson(nested));
      }
    }
    tags.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return tags;
  }

  /// Replace the signed-in user's tag set with [tagIds].
  ///
  /// Delete-then-insert rather than a diff: the set is at most a few
  /// dozen rows, and a diff would need to be transactional to avoid a
  /// half-applied state. RLS restricts both halves to `auth.uid()`, and
  /// the predicate is repeated so a role issue can never clear someone
  /// else's tags.
  static Future<void> saveMine(Set<int> tagIds) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to update your profile.');
    }
    await _client.from(_joinTable).delete().eq('profile_id', user.id);
    if (tagIds.isEmpty) return;
    await _client.from(_joinTable).insert([
      for (final id in tagIds) {'profile_id': user.id, 'tag_id': id},
    ]);
  }
}
