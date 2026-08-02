import 'dart:async';
import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/ministry_tag_model.dart';
import 'cache_service.dart';

/// Ministry involvement and spiritual gifts (patch_168).
///
/// Both halves are cached to DISK, not just to memory.
///
/// `ministry_tags` is reference data — 30 rows that change about never —
/// yet it was only held in a process-lifetime field, so every cold start
/// paid a round-trip before the picker could open. The per-profile join
/// wasn't cached at all, so a member's own chips popped in late on every
/// profile visit and disappeared entirely offline, which is what made
/// the section look broken.
///
/// The user's OWN tags are the ones cached per-profile: they are the set
/// that is read most, and the only one we can keep correct locally
/// (saveMine rewrites it). Other people's tags still go to the server.
class MinistryService {
  MinistryService._();

  static final SupabaseClient _client = Supabase.instance.client;

  static const _tagsTable = 'ministry_tags';
  static const _joinTable = 'profile_ministry_tags';

  static const _vocabKey = 'ministry_vocabulary_v1';
  static const _mineKey = 'ministry_mine_v1';

  static List<MinistryTag>? _vocabularyCache;

  static List<MinistryTag> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => MinistryTag.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static String _encode(List<MinistryTag> tags) =>
      jsonEncode(tags.map((t) => t.toJson()).toList());

  /// Synchronously-readable vocabulary, so a picker can open on the
  /// first frame instead of after a network hop.
  static List<MinistryTag> cachedVocabulary() {
    final memory = _vocabularyCache;
    if (memory != null) return memory;
    final disk = _decode(CacheService.readStringStale(_vocabKey));
    if (disk.isNotEmpty) _vocabularyCache = disk;
    return disk;
  }

  /// The signed-in user's own tags from the local cache — for an
  /// instant, offline-safe paint of the profile chips.
  static List<MinistryTag> cachedMine() =>
      _decode(CacheService.readStringStale(_mineKey));

  /// The full controlled vocabulary, ordered for display.
  static Future<List<MinistryTag>> fetchVocabulary() async {
    final cached = _vocabularyCache;
    if (cached != null) return cached;
    try {
      final rows = await _client
          .from(_tagsTable)
          .select('id, code, label, kind, sort_order')
          .order('sort_order');
      final tags = (rows as List)
          .map((r) => MinistryTag.fromJson(r as Map<String, dynamic>))
          .toList();
      _vocabularyCache = tags;
      unawaited(CacheService.writeString(_vocabKey, _encode(tags)));
      return tags;
    } catch (_) {
      // Offline: the vocabulary is static, so a stale copy is as good as
      // a fresh one and far better than an empty picker.
      return cachedVocabulary();
    }
  }

  /// Tags claimed by [profileId]. RLS returns an empty list rather than
  /// an error when the profile is private and isn't the caller's, so a
  /// locked-down profile simply shows no chips.
  static Future<List<MinistryTag>> fetchForProfile(String profileId) async {
    if (profileId.isEmpty) return const [];
    final isMe = _client.auth.currentUser?.id == profileId;
    try {
      final rows = await _client
          .from(_joinTable)
          .select(
              'tag_id, ministry_tags:tag_id(id, code, label, kind, sort_order)')
          .eq('profile_id', profileId);
      final tags = <MinistryTag>[];
      for (final row in rows as List) {
        final nested = (row as Map<String, dynamic>)['ministry_tags'];
        if (nested is Map<String, dynamic>) {
          tags.add(MinistryTag.fromJson(nested));
        }
      }
      tags.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      if (isMe) unawaited(CacheService.writeString(_mineKey, _encode(tags)));
      return tags;
    } catch (_) {
      return isMe ? cachedMine() : const [];
    }
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
    if (tagIds.isNotEmpty) {
      await _client.from(_joinTable).insert([
        for (final id in tagIds) {'profile_id': user.id, 'tag_id': id},
      ]);
    }
    // Keep the local copy in step with what we just wrote, so returning
    // to the profile shows the new chips immediately instead of the
    // previous set until the next successful fetch.
    //
    // NOTE the early `return` this replaced: clearing every tag used to
    // skip the cache write entirely, so an emptied set kept rendering
    // the old chips from disk.
    final vocab = await fetchVocabulary();
    final mine = vocab.where((t) => tagIds.contains(t.id)).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    unawaited(CacheService.writeString(_mineKey, _encode(mine)));
  }
}
