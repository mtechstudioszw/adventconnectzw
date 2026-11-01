import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/message_model.dart';
import 'cache_service.dart';
import 'connectivity_service.dart';
import 'messaging_service.dart';

/// Offline-first chat actions (owner, 1 Nov 2026: "if I pin a chat, every
/// time I reload the app, that pinned chat is down … when you react to a
/// message, it reacts and waits for internet to proceed. Like WhatsApp").
///
/// Every small action — pin / mute / archive a chat, react to a message,
/// star it, pin it inside the chat — now happens in three steps:
///
///   1. it is written to the phone at once (a cache that survives a
///      restart), so the screen shows it immediately and keeps showing it;
///   2. it is queued as an "op" in a Hive box, keyed so the LATEST choice
///      wins (react ❤️ then 👍 offline sends only 👍);
///   3. the queue drains whenever there is a connection — now, on reconnect
///      and on app start — and an op leaves the queue only once the server
///      accepted it.
///
/// Server reads (states, reactions, stars) are cached on success and served
/// from the cache on failure, with the pending ops laid on top. That is what
/// stops the old "it remembers, then forgets, then pins again" flicker: the
/// screen never falls back to an empty server answer.
///
/// Text messages already have their own outbox in [MessagingService]; this
/// is everything else.
class ChatSync {
  ChatSync._();

  static const _boxName = 'chat_ops_v1';
  static Box<String>? _ops;
  static StreamSubscription<bool>? _sub;
  static bool _flushing = false;

  /// Bumped whenever the local view of states/reactions/stars/pins changes,
  /// so open screens can rebuild without polling.
  static final ValueNotifier<int> revision = ValueNotifier(0);

  static SupabaseClient get _client => Supabase.instance.client;
  static String? get _me => _client.auth.currentUser?.id;

  static Future<void> start() async {
    if (_sub != null) return;
    try {
      _ops = await Hive.openBox<String>(_boxName);
    } catch (e) {
      debugPrint('ChatSync: box open failed: $e');
      return;
    }
    _sub = ConnectivityService.onChanged.listen((online) {
      if (online) unawaited(flush());
    });
    unawaited(flush());
  }

  /// Ops waiting for a connection, for "waiting to sync" hints.
  static int get pendingCount => _ops?.length ?? 0;

  /// Sign-out: another member must never replay this one's actions.
  static Future<void> clear() async {
    try {
      await _ops?.clear();
    } catch (_) {}
  }

  // ------------------------------------------------------------------
  //  Chat flags: pinned / muted / archived
  // ------------------------------------------------------------------

  /// User-scoped (no `pref:`), so sign-out clears it — see CLAUDE.md.
  static const _statesKey = 'conv_states_v1';

  static Map<String, ConversationState> cachedStates() {
    final raw = CacheService.readStringStale(_statesKey);
    final base = <String, ConversationState>{};
    if (raw != null && raw.isNotEmpty) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        map.forEach((k, v) {
          base[k] = ConversationState.fromJson(Map<String, dynamic>.from(v as Map));
        });
      } catch (_) {}
    }
    return withPendingFlags(base);
  }

  static Future<void> cacheStates(Map<String, ConversationState> states) async {
    try {
      await CacheService.writeString(
        _statesKey,
        jsonEncode({for (final e in states.entries) e.key: _stateJson(e.value)}),
      );
    } catch (_) {}
  }

  static Map<String, dynamic> _stateJson(ConversationState s) => {
    'pinned': s.pinned,
    'muted': s.muted,
    'archived': s.archived,
    'cleared_at': ?s.clearedAt?.toIso8601String(),
  };

  /// [base] with every queued flag change applied on top.
  static Map<String, ConversationState> withPendingFlags(
    Map<String, ConversationState> base,
  ) {
    final out = {...base};
    for (final op in _opsOfKind('flags')) {
      final cid = op['conversation_id'] as String;
      final cur = out[cid] ?? const ConversationState();
      out[cid] = ConversationState(
        pinned: (op['pinned'] as bool?) ?? cur.pinned,
        muted: (op['muted'] as bool?) ?? cur.muted,
        archived: (op['archived'] as bool?) ?? cur.archived,
        clearedAt: cur.clearedAt,
      );
    }
    return out;
  }

  /// Server states, cached, with pending changes on top. Falls back to the
  /// cache when the server can't be reached — never to "nothing pinned".
  static Future<Map<String, ConversationState>> loadStates() async {
    final me = _me;
    if (me == null) return const {};
    try {
      final rows = await _client
          .from('conversation_state')
          .select()
          .eq('user_id', me)
          .timeout(const Duration(seconds: 12));
      final fresh = {
        for (final r in (rows as List))
          (r as Map)['conversation_id'].toString():
              ConversationState.fromJson(Map<String, dynamic>.from(r)),
      };
      await cacheStates(fresh);
      return withPendingFlags(fresh);
    } catch (_) {
      return cachedStates();
    }
  }

  static Future<void> setFlags(
    String conversationId, {
    bool? pinned,
    bool? muted,
    bool? archived,
  }) async {
    final me = _me;
    if (me == null) return;
    final key = 'flags:$conversationId';
    final prev = _read(key);
    final op = <String, dynamic>{
      'kind': 'flags',
      'user_id': me,
      'conversation_id': conversationId,
      'pinned': pinned ?? prev?['pinned'],
      'muted': muted ?? prev?['muted'],
      'archived': archived ?? prev?['archived'],
    };
    await _put(key, op);
    // Fold into the cache too, so a restart before the flush still shows it.
    final cached = cachedStates();
    await cacheStates(cached);
    revision.value++;
    unawaited(flush());
  }

  // ------------------------------------------------------------------
  //  Reactions
  // ------------------------------------------------------------------

  static String _reactionsKey(String cid) => 'reactions:$cid';

  /// Reactions as last seen from the server, with queued reactions on top.
  /// Shape matches [MessagingService.fetchReactions]: message id →
  /// {emoji: count, '_mine_EMOJI': 1}.
  static Map<String, Map<String, int>> cachedReactions(String cid) {
    final raw = CacheService.readStringStale(_reactionsKey(cid));
    final base = <String, Map<String, int>>{};
    if (raw != null && raw.isNotEmpty) {
      try {
        (jsonDecode(raw) as Map<String, dynamic>).forEach((mid, v) {
          base[mid] = Map<String, int>.from(
            (v as Map).map((k, c) => MapEntry(k.toString(), (c as num).toInt())),
          );
        });
      } catch (_) {}
    }
    return withPendingReactions(cid, base);
  }

  static Future<Map<String, Map<String, int>>> loadReactions(String cid) async {
    try {
      final fresh = await MessagingService.fetchReactionsStrict(cid);
      await CacheService.writeString(_reactionsKey(cid), jsonEncode(fresh));
      return withPendingReactions(cid, fresh);
    } catch (_) {
      return cachedReactions(cid);
    }
  }

  /// [base] with each queued reaction applied: the viewer's own reaction on
  /// that message becomes exactly the queued emoji (or none).
  static Map<String, Map<String, int>> withPendingReactions(
    String cid,
    Map<String, Map<String, int>> base,
  ) {
    final out = {
      for (final e in base.entries) e.key: Map<String, int>.from(e.value),
    };
    for (final op in _opsOfKind('reaction')) {
      if (op['conversation_id'] != cid) continue;
      final mid = op['message_id'] as String;
      final want = op['emoji'] as String?;
      final m = out.putIfAbsent(mid, () => <String, int>{});
      // Take off whatever the viewer had…
      for (final k in m.keys.where((k) => k.startsWith('_mine_')).toList()) {
        final emoji = k.substring(6);
        m.remove(k);
        final c = (m[emoji] ?? 1) - 1;
        if (c <= 0) {
          m.remove(emoji);
        } else {
          m[emoji] = c;
        }
      }
      // …and put on what they chose.
      if (want != null) {
        m['_mine_$want'] = 1;
        m[want] = (m[want] ?? 0) + 1;
      }
      if (m.isEmpty) out.remove(mid);
    }
    return out;
  }

  /// The viewer's reaction on [messageId] becomes [emoji] (null = none).
  static Future<void> setReaction(
    String cid,
    String messageId,
    String? emoji,
  ) async {
    final me = _me;
    if (me == null) return;
    await _put('reaction:$messageId', {
      'kind': 'reaction',
      'user_id': me,
      'conversation_id': cid,
      'message_id': messageId,
      'emoji': emoji,
    });
    revision.value++;
    unawaited(flush());
  }

  // ------------------------------------------------------------------
  //  Stars
  // ------------------------------------------------------------------

  static String _starsKey(String cid) => 'stars:$cid';

  static Set<String> cachedStars(String cid) {
    final raw = CacheService.readStringStale(_starsKey(cid));
    final base = <String>{};
    if (raw != null && raw.isNotEmpty) {
      try {
        base.addAll((jsonDecode(raw) as List).map((e) => e.toString()));
      } catch (_) {}
    }
    return withPendingStars(cid, base);
  }

  static Future<Set<String>> loadStars(String cid) async {
    try {
      final fresh = await MessagingService.fetchStarredIdsStrict(cid);
      await CacheService.writeString(_starsKey(cid), jsonEncode(fresh.toList()));
      return withPendingStars(cid, fresh);
    } catch (_) {
      return cachedStars(cid);
    }
  }

  static Set<String> withPendingStars(String cid, Set<String> base) {
    final out = {...base};
    for (final op in _opsOfKind('star')) {
      if (op['conversation_id'] != cid) continue;
      final mid = op['message_id'] as String;
      if (op['starred'] == true) {
        out.add(mid);
      } else {
        out.remove(mid);
      }
    }
    return out;
  }

  static Future<void> setStar(String cid, String messageId, bool starred) async {
    final me = _me;
    if (me == null) return;
    await _put('star:$messageId', {
      'kind': 'star',
      'user_id': me,
      'conversation_id': cid,
      'message_id': messageId,
      'starred': starred,
    });
    revision.value++;
    unawaited(flush());
  }

  // ------------------------------------------------------------------
  //  Pinned message inside a chat
  // ------------------------------------------------------------------

  /// The queued pinned message for [cid]: null = nothing queued,
  /// '' = queued "unpin", otherwise the message id.
  static String? pendingPinned(String cid) {
    final op = _read('pin:$cid');
    if (op == null) return null;
    return (op['message_id'] as String?) ?? '';
  }

  static Future<void> setPinnedMessage(String cid, String? messageId) async {
    final me = _me;
    if (me == null) return;
    await _put('pin:$cid', {
      'kind': 'pin',
      'user_id': me,
      'conversation_id': cid,
      'message_id': messageId,
    });
    revision.value++;
    unawaited(flush());
  }

  // ------------------------------------------------------------------
  //  The queue
  // ------------------------------------------------------------------

  static Map<String, dynamic>? _read(String key) {
    final raw = _ops?.get(key);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Iterable<Map<String, dynamic>> _opsOfKind(String kind) sync* {
    final box = _ops;
    final me = _me;
    if (box == null || me == null) return;
    for (final key in box.keys) {
      final op = _read(key.toString());
      if (op != null && op['kind'] == kind && op['user_id'] == me) yield op;
    }
  }

  static Future<void> _put(String key, Map<String, dynamic> op) async {
    op['queued_at'] = DateTime.now().toUtc().toIso8601String();
    try {
      await _ops?.put(key, jsonEncode(op));
    } catch (e) {
      debugPrint('ChatSync: queue write failed: $e');
    }
  }

  /// Send what's queued. Stops at the first network failure (the rest wait
  /// for the next connection); drops an op the server refuses outright —
  /// e.g. a reaction on a message that was deleted — so one bad op can
  /// never jam the queue.
  static Future<int> flush() async {
    final box = _ops;
    final me = _me;
    if (box == null || me == null || _flushing || box.isEmpty) return 0;
    if (!ConnectivityService.isOnline) return 0;
    _flushing = true;
    var sent = 0;
    try {
      for (final key in box.keys.toList()) {
        final op = _read(key.toString());
        if (op == null || op['user_id'] != me) {
          await box.delete(key);
          continue;
        }
        try {
          await _apply(op);
          // Only remove it if nothing newer replaced it meanwhile.
          if (box.get(key) != null &&
              _read(key.toString())?['queued_at'] == op['queued_at']) {
            await box.delete(key);
          }
          sent++;
        } on PostgrestException catch (e) {
          if (!isPermanentRefusal(e)) {
            // Overloaded, timed out, gateway error, expired token: the
            // server didn't say NO, it just couldn't answer. Keep it.
            debugPrint('ChatSync: will retry ${op['kind']}: ${e.message}');
            break;
          }
          debugPrint('ChatSync: server refused ${op['kind']}: ${e.message}');
          await box.delete(key);
        } catch (e) {
          debugPrint('ChatSync: will retry ${op['kind']}: $e');
          break;
        }
      }
    } finally {
      _flushing = false;
    }
    if (sent > 0) revision.value++;
    return sent;
  }

  /// True only for a definite "no" from Postgres (a deleted message, RLS,
  /// a constraint) — never for the 5xx, timeout and overload answers the
  /// Nano database gave during the 30 Oct 2026 outage. Dropping an op on
  /// one of those would lose exactly the action the queue exists to keep.
  static bool isPermanentRefusal(PostgrestException e) {
    final code = e.code ?? '';
    // A real SQLSTATE is 5 characters.
    if (!RegExp(r'^[0-9A-Z]{5}$').hasMatch(code)) return false;
    // 08 connection, 53 insufficient resources, 57 timeout/shutdown,
    // 58 system, 40 serialization/deadlock — all worth retrying.
    for (final retry in const ['08', '53', '57', '58', '40']) {
      if (code.startsWith(retry)) return false;
    }
    return true;
  }

  static Future<void> _apply(Map<String, dynamic> op) {
    final cid = op['conversation_id'] as String;
    switch (op['kind']) {
      case 'flags':
        return MessagingService.setConversationFlags(
          cid,
          pinned: op['pinned'] as bool?,
          muted: op['muted'] as bool?,
          archived: op['archived'] as bool?,
        );
      case 'reaction':
        return MessagingService.setReaction(
          op['message_id'] as String,
          op['emoji'] as String?,
        );
      case 'star':
        // toggleStar's flag is the CURRENT state: true deletes the star.
        return MessagingService.toggleStar(
          op['message_id'] as String,
          starred: op['starred'] != true,
        );
      case 'pin':
        return MessagingService.setPinnedMessage(
          cid,
          op['message_id'] as String?,
        );
    }
    return Future.value();
  }

  @visibleForTesting
  static Future<void> debugUseBox(Box<String> box) async {
    _ops = box;
  }
}
