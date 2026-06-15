import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/message_model.dart';
import 'analytics_service.dart';
import 'cache_service.dart';
import 'connectivity_service.dart';

/// One-shot handoff for opening a chat with a pre-filled draft and an
/// optional product preview (tester bug #17: "message a seller from a
/// product — show the product picture with a message ready to send").
/// Set it right before navigating to the chat; ChatScreen reads + clears
/// it in initState. Avoids threading extra args through go_router.
class ChatLaunchIntent {
  ChatLaunchIntent._();

  static String? draft;
  static String? productId;
  static String? productImageUrl;
  static String? productTitle;
  static String? productPrice;

  static bool get hasProduct =>
      (productTitle ?? '').isNotEmpty || (productImageUrl ?? '').isNotEmpty;

  static void set({
    String? draft,
    String? productId,
    String? productImageUrl,
    String? productTitle,
    String? productPrice,
  }) {
    ChatLaunchIntent.draft = draft;
    ChatLaunchIntent.productId = productId;
    ChatLaunchIntent.productImageUrl = productImageUrl;
    ChatLaunchIntent.productTitle = productTitle;
    ChatLaunchIntent.productPrice = productPrice;
  }

  static void clear() {
    draft = null;
    productId = null;
    productImageUrl = null;
    productTitle = null;
    productPrice = null;
  }
}

class MessagingService {
  MessagingService._();

  static final SupabaseClient _client = Supabase.instance.client;

  static const _conversationsTable = 'conversations';
  static const _messagesTable = 'messages';
  static const _voiceBucket = 'voice_notes';
  static const _outboxBoxName = 'message_outbox_v1';
  static Box<String>? _outbox;
  static StreamSubscription<bool>? _outboxFlushSub;
  static bool _flushInFlight = false;

  /// Open the outbox and subscribe to connectivity transitions so
  /// queued messages flush automatically when the device comes back
  /// online. Safe to call multiple times. Hive must already be inited.
  static Future<void> startOutboxFlusher() async {
    if (_outboxFlushSub != null) return;
    try {
      await Hive.initFlutter();
      _outbox = await Hive.openBox<String>(_outboxBoxName);
    } catch (e, st) {
      debugPrint('MessagingService: outbox open failed: $e\n$st');
      return;
    }
    _outboxFlushSub = ConnectivityService.onChanged.listen((online) {
      if (online) unawaited(flushOutbox());
    });
    // Try once on boot in case we never went offline but the previous
    // session shut down with queued items still present.
    if (ConnectivityService.isOnline) {
      unawaited(flushOutbox());
    }
  }

  /// True when at least one message is queued. Cheap synchronous check.
  static bool get hasPendingOutbox => (_outbox?.isNotEmpty ?? false);

  /// Drains the outbox. Each row is removed only if its insert succeeds —
  /// transient failures keep the row for a future retry. Returns the
  /// number of rows successfully sent.
  static Future<int> flushOutbox() async {
    final box = _outbox;
    if (box == null || box.isEmpty || _flushInFlight) return 0;
    _flushInFlight = true;
    var flushed = 0;
    try {
      for (final key in box.keys.toList()) {
        final raw = box.get(key);
        if (raw == null) continue;
        Map<String, dynamic> payload;
        try {
          payload = jsonDecode(raw) as Map<String, dynamic>;
        } catch (_) {
          await box.delete(key);
          continue;
        }
        try {
          final inserted = await _client
              .from(_messagesTable)
              .insert(payload)
              .select()
              .single();
          await _client.from(_conversationsTable).update({
            'last_message': payload['content'],
            'last_sender_id': payload['sender_id'],
            'last_message_at':
                (inserted['created_at'] ?? DateTime.now().toUtc().toIso8601String())
                    .toString(),
          }).eq('id', payload['conversation_id']);
          AnalyticsService.messageSent(source: 'text_outbox');
          await box.delete(key);
          flushed += 1;
        } catch (e, st) {
          debugPrint('MessagingService: outbox flush row failed: $e\n$st');
          // Leave the row in the box; we'll retry on the next online
          // transition. Bail to avoid a hot loop if the backend is sick.
          break;
        }
      }
    } finally {
      _flushInFlight = false;
    }
    return flushed;
  }

  static Future<void> _enqueueOutbox(Map<String, dynamic> payload) async {
    final box = _outbox;
    if (box == null) return;
    try {
      await box.add(jsonEncode(payload));
    } catch (e, st) {
      debugPrint('MessagingService: enqueue failed: $e\n$st');
    }
  }

  /// Realtime Broadcast channel name for the typing indicator. Keeping
  /// the format here so subscribers and senders stay in sync.
  static String _typingChannelName(String conversationId) =>
      'chat:$conversationId:typing';

  /// Fetches every conversation the current user is a participant in,
  /// including pending message requests. The UI splits the result into
  /// the Inbox / Requests buckets via [Conversation.isIncomingRequestFor].
  ///
  /// "Notes to self" is always pinned to the top of the inbox regardless
  /// of last_message_at — keeps the bookmark predictable even when the
  /// user hasn't written anything for a while.
  /// Selects the conversation columns plus a join to both participants'
  /// profile_photo_url so the inbox + chat header can render an actual
  /// avatar instead of just initials. Uses the explicit
  /// `target_table!fk_constraint_name(...)` form because conversations
  /// has four FKs to profiles (initiator, last_sender, participant_a,
  /// participant_b) and PostgREST needs the constraint name to pick
  /// the right one — the shorter `:fk_column(...)` form was returning
  /// empty embedded objects, leaving the chat header on initials only.
  static const _conversationSelect =
      '*, '
      'participant_a:profiles!conversations_participant_a_id_fkey(profile_photo_url), '
      'participant_b:profiles!conversations_participant_b_id_fkey(profile_photo_url)';

  /// Fetches a single conversation by id, joining both participants'
  /// profile photos. Used when the chat screen is entered from a deep
  /// link (push notification tap) and we don't yet have a
  /// Conversation object to pre-populate the header.
  static Future<Conversation?> fetchConversation(String conversationId) async {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    try {
      final row = await _client
          .from(_conversationsTable)
          .select(_conversationSelect)
          .eq('id', conversationId)
          .maybeSingle();
      if (row == null) return null;
      return Conversation.fromJson(row, currentUserId: user.id);
    } catch (_) {
      return null;
    }
  }

  static Future<List<Conversation>> fetchConversations() async {
    final user = _client.auth.currentUser;
    if (user == null) return const [];
    // Offline → return whatever we last cached so the inbox always
    // shows something (WhatsApp parity). The caller already drives
    // a refresh when ConnectivityService.onChanged fires online.
    if (!ConnectivityService.isOnline) {
      return readCachedInbox();
    }
    List<dynamic> response;
    try {
      // 1:1 chats (explicit participant filter) + group chats the viewer
      // belongs to (is_group rows; patch_052 RLS already limits these to
      // the caller's memberships, so no extra filter is needed). Fetched
      // in parallel and merged.
      final results = await Future.wait([
        _client
            .from(_conversationsTable)
            .select(_conversationSelect)
            .or(
              'participant_a_id.eq.${user.id},participant_b_id.eq.${user.id}',
            )
            .order('last_message_at', ascending: false)
            .limit(100),
        _client
            .from(_conversationsTable)
            .select(_conversationSelect)
            .eq('is_group', true)
            .order('last_message_at', ascending: false)
            .limit(100),
      ]);
      final merged = <String, dynamic>{};
      for (final row in [...(results[0] as List), ...(results[1] as List)]) {
        merged[(row as Map)['id'].toString()] = row;
      }
      response = merged.values.toList();
    } catch (_) {
      // Connectivity check raced — fall back to cache rather than
      // surfacing a generic failure on the inbox.
      return readCachedInbox();
    }
    // patch_032: drop rows the viewer has soft-deleted (until a fresh
    // inbound message arrives after the delete, in which case the
    // thread reappears — WhatsApp parity). Done client-side so it
    // stays correct even when the older `delete_by_*` columns aren't
    // present yet.
    final filteredResponse = response.where((r) {
      final raw = r as Map;
      final isA = raw['participant_a_id']?.toString() == user.id;
      final isB = raw['participant_b_id']?.toString() == user.id;
      final deletedAtRaw = isA
          ? raw['deleted_by_a_at']
          : isB
              ? raw['deleted_by_b_at']
              : null;
      if (deletedAtRaw == null) return true;
      final deletedAt = DateTime.tryParse(deletedAtRaw.toString());
      if (deletedAt == null) return true;
      final lastMsgRaw = raw['last_message_at'];
      final lastMsg = lastMsgRaw == null
          ? null
          : DateTime.tryParse(lastMsgRaw.toString());
      // Hide unless a newer message has arrived since the delete.
      return lastMsg != null && lastMsg.isAfter(deletedAt);
    }).toList();

    // Pull unread counts in parallel — single RPC roundtrip via
    // get_my_unread_counts() (patch_018, refined in patch_032 to
    // honour the new soft-delete). RLS is participant-scoped so the
    // count is naturally limited to the caller's threads.
    // These four are independent RPCs — run them in PARALLEL (one
    // round-trip instead of four) so the inbox loads fast on slow
    // networks. 1:1 + group (patch_060) + church (patch_090) unread, plus
    // the last-outgoing delivery state for the tick (patch_075).
    final counts = await Future.wait([
      fetchUnreadCounts(),
      fetchGroupUnreadCounts(),
      fetchChurchUnreadCounts(),
    ]);
    final unreadById = <String, int>{}
      ..addAll(counts[0])
      ..addAll(counts[1])
      ..addAll(counts[2]);
    final lastStatus = await fetchLastOutgoingStatus();
    // Splice the unread count into each raw row BEFORE caching so a
    // cache-restore preserves badges accurately — caching the raw
    // server response (without counts) was the source of the
    // "open chat, refresh, message reverts to unread" bug.
    final enriched = filteredResponse
        .map((r) {
          final raw = Map<String, dynamic>.from(r as Map);
          final id = raw['id'].toString();
          raw['unread_count'] = unreadById[id] ?? 0;
          return raw;
        })
        .toList();
    unawaited(_writeInboxCache(enriched));
    final list = enriched.map((raw) {
      var c = Conversation.fromJson(raw, currentUserId: user.id);
      final st = lastStatus[c.id];
      if (st != null) {
        c = c.copyWith(lastDelivered: st.delivered, lastRead: st.read);
      }
      return c;
    }).toList();
    list.sort((a, b) {
      if (a.isSelfChat && !b.isSelfChat) return -1;
      if (b.isSelfChat && !a.isSelfChat) return 1;
      return b.lastMessageAt.compareTo(a.lastMessageAt);
    });
    return list;
  }

  /// Returns a map from conversation_id → unread message count for
  /// the current user. Uses the `get_my_unread_counts` SQL function
  /// (patch_018) so the database does the GROUP BY instead of the
  /// client scanning every thread.
  static Future<Map<String, int>> fetchUnreadCounts() async {
    try {
      final rows = await _client.rpc('get_my_unread_counts');
      if (rows is! List) return const {};
      final result = <String, int>{};
      for (final raw in rows) {
        if (raw is Map) {
          final id = raw['conversation_id']?.toString();
          final count = raw['unread_count'];
          if (id == null) continue;
          if (count is int) {
            result[id] = count;
          } else if (count is num) {
            result[id] = count.toInt();
          }
        }
      }
      return result;
    } catch (_) {
      // RPC missing or RLS error — degrade gracefully to zero badges
      // rather than blanking the whole inbox.
      return const {};
    }
  }

  /// Delivery state of each conversation's last message WHEN the caller
  /// sent it (patch_075). Keyed by conversation id → (delivered, read).
  /// Used for the inbox tick. Conversations whose last message is from the
  /// other party are absent.
  static Future<Map<String, ({bool delivered, bool read})>>
      fetchLastOutgoingStatus() async {
    try {
      final rows = await _client.rpc('last_outgoing_message_status');
      if (rows is! List) return const {};
      final result = <String, ({bool delivered, bool read})>{};
      for (final raw in rows) {
        if (raw is Map) {
          final id = raw['conversation_id']?.toString();
          if (id == null) continue;
          result[id] = (
            delivered: raw['delivered'] == true,
            read: raw['is_read'] == true,
          );
        }
      }
      return result;
    } catch (_) {
      return const {};
    }
  }

  /// Per-group unread counts (patch_060). Keyed by conversation id.
  static Future<Map<String, int>> fetchGroupUnreadCounts() async {
    try {
      final rows = await _client.rpc('get_group_unread_counts');
      if (rows is! List) return const {};
      final result = <String, int>{};
      for (final raw in rows) {
        if (raw is Map) {
          final id = raw['conversation_id']?.toString();
          final count = raw['unread_count'];
          if (id == null) continue;
          if (count is num) result[id] = count.toInt();
        }
      }
      return result;
    } catch (_) {
      return const {};
    }
  }

  /// Per-church-group unread counts (patch_090). Keyed by conversation id.
  static Future<Map<String, int>> fetchChurchUnreadCounts() async {
    try {
      final rows = await _client.rpc('church_unread_counts');
      if (rows is! List) return const {};
      final result = <String, int>{};
      for (final raw in rows) {
        if (raw is Map) {
          final id = raw['conversation_id']?.toString();
          final count = raw['unread'];
          if (id == null) continue;
          if (count is num) result[id] = count.toInt();
        }
      }
      return result;
    } catch (_) {
      return const {};
    }
  }

  /// Realtime stream of INSERTs on the messages table, scoped to the
  /// current user's conversations by RLS. The conversations screen
  /// uses this to bump unread badges and refresh last-message
  /// previews without a full re-fetch on every keystroke from peers.
  static Stream<List<Map<String, dynamic>>> streamInboxActivity() {
    return _client
        .from(_messagesTable)
        .stream(primaryKey: ['id'])
        .order('created_at')
        .map((rows) => rows.cast<Map<String, dynamic>>());
  }

  /// Finds (or lazily creates) the signed-in user's "Notes to self"
  /// conversation. Self-chats are stored as ordinary conversation rows
  /// where both participant columns hold the same uuid; the
  /// `request_status` is forced to 'accepted' so the row never lands in
  /// the Requests inbox. The first time this runs the row is empty —
  /// the chat screen handles `lastMessage == ''` already.
  static Future<Conversation> openSelfChat() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to open Notes to self.');
    }
    final existing = await _client
        .from(_conversationsTable)
        .select()
        .eq('participant_a_id', user.id)
        .eq('participant_b_id', user.id)
        .limit(1);
    if ((existing as List).isNotEmpty) {
      return Conversation.fromJson(
        (existing.first as Map).cast<String, dynamic>(),
        currentUserId: user.id,
      );
    }
    final meta = user.userMetadata ?? const {};
    final myName = ((meta['full_name'] as String?)?.trim().isNotEmpty == true)
        ? (meta['full_name'] as String).trim()
        : 'Member';
    final inserted = await _client
        .from(_conversationsTable)
        .insert({
          'participant_a_id': user.id,
          'participant_b_id': user.id,
          'participant_a_name': myName,
          'participant_b_name': myName,
          'initiator_id': user.id,
          // 'direct' is the only generic value the conversation_source
          // CHECK constraint allows. Self-chats are identified by
          // participant_a_id = participant_b_id (see idx_conversations_self_chat
          // in patch_016), not by a special source value — passing 'self'
          // here would violate conversations_conversation_source_check.
          'conversation_source': 'direct',
          'request_status': 'accepted',
        })
        .select()
        .single();
    return Conversation.fromJson(
      (inserted as Map).cast<String, dynamic>(),
      currentUserId: user.id,
    );
  }

  /// Creates a conversation (or returns an existing one between the
  /// two users). If [firstMessage] is provided and non-empty, it's
  /// posted as the opening message; otherwise the conversation row is
  /// created empty (WhatsApp-style: tap a contact, land on an empty
  /// chat, type your own opener). New conversations are inserted with
  /// `request_status='pending'` so the recipient sees it in their
  /// Requests inbox until they accept. If a conversation already
  /// exists between the pair in either participant ordering, it's
  /// reused and the message (if any) is appended — no duplicate row.
  ///
  /// Returns the conversation (post-insert / post-update) so the caller
  /// can immediately navigate into the chat.
  static Future<Conversation> createConversation({
    required String otherUserId,
    required String otherUserName,
    String? firstMessage,
    String source = 'direct',
    bool isBusiness = false,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to send a message request.');
    }
    final body = (firstMessage ?? '').trim();
    final meta = user.userMetadata ?? const {};
    final myName = ((meta['full_name'] as String?)?.trim().isNotEmpty == true)
        ? (meta['full_name'] as String).trim()
        : 'Member';

    // Resolve the other participant's REAL display name from their
    // profile rather than trusting the caller-supplied name. Jobs /
    // marketplace pass placeholders like "Job seeker" / "Recruiter"
    // when they don't have the poster's identity loaded — but the
    // chat must show the actual person. Falls back to the passed
    // name (then "Member") if the lookup fails.
    var resolvedOtherName = otherUserName.trim();
    try {
      final prof = await _client
          .from('profiles')
          .select('full_name')
          .eq('id', otherUserId)
          .maybeSingle();
      final realName = (prof?['full_name'] as String?)?.trim() ?? '';
      if (realName.isNotEmpty) resolvedOtherName = realName;
    } catch (_) {
      // keep the caller-supplied name
    }
    if (resolvedOtherName.isEmpty) resolvedOtherName = 'Member';

    // Reuse an existing conversation between us if one already exists,
    // regardless of which side seeded it (a/b ordering). We pull the
    // joined participant photo URLs (_conversationSelect) so the
    // returned Conversation carries a usable avatar — without that
    // the chat screen header opened from search / profile fell back
    // to grey initials even when both users had profile photos.
    final existingRows = await _client
        .from(_conversationsTable)
        .select(_conversationSelect)
        .or(
          'and(participant_a_id.eq.${user.id},participant_b_id.eq.$otherUserId),'
          'and(participant_a_id.eq.$otherUserId,participant_b_id.eq.${user.id})',
        )
        .limit(1);

    Map<String, dynamic> convoRow;
    if ((existingRows as List).isNotEmpty) {
      convoRow = (existingRows.first as Map).cast<String, dynamic>();
      // Promote the existing thread to "business" once a marketplace
      // contact happens — sticky for the badge.
      if (isBusiness && convoRow['is_business'] != true) {
        await _client
            .from(_conversationsTable)
            .update({'is_business': true}).eq('id', convoRow['id']);
        convoRow['is_business'] = true;
      }
    } else {
      // patch_032: if these two users are already friends, the thread
      // should land in the recipient's main inbox, not Requests. The
      // DB trigger conversations_auto_accept_friends covers this
      // server-side too — this is a client-side belt-and-braces so
      // the right behaviour kicks in even before the migration runs.
      final areFriends = await _areAcceptedFriends(user.id, otherUserId);
      try {
        final inserted = await _client
            .from(_conversationsTable)
            .insert({
              'participant_a_id': user.id,
              'participant_b_id': otherUserId,
              'participant_a_name': myName,
              'participant_b_name': resolvedOtherName,
              'initiator_id': user.id,
              'conversation_source': source,
              'is_business': isBusiness,
              if (areFriends) 'request_status': 'accepted',
            })
            .select(_conversationSelect)
            .single();
        convoRow = (inserted as Map).cast<String, dynamic>();
      } on PostgrestException catch (e) {
        // patch_046 unique pair index: a concurrent tap (or entering
        // the chat from two surfaces at once) raced us to the insert.
        // Re-fetch the row the other call created instead of throwing
        // — guarantees one thread per pair, never a duplicate.
        if (e.code == '23505') {
          final raced = await _client
              .from(_conversationsTable)
              .select(_conversationSelect)
              .or(
                'and(participant_a_id.eq.${user.id},participant_b_id.eq.$otherUserId),'
                'and(participant_a_id.eq.$otherUserId,participant_b_id.eq.${user.id})',
              )
              .limit(1);
          if ((raced as List).isEmpty) rethrow;
          convoRow = (raced.first as Map).cast<String, dynamic>();
        } else {
          rethrow;
        }
      }
    }

    final conversationId = convoRow['id'].toString();

    // Empty-opener path: WhatsApp-style "tap contact → land in empty
    // chat → user types their own first message." Skip the message
    // insert + conversation last_message update entirely.
    if (body.isEmpty) {
      return Conversation.fromJson(convoRow, currentUserId: user.id);
    }

    final now = DateTime.now().toUtc().toIso8601String();
    // Note: messages table has NO sender_name column.
    await _client.from(_messagesTable).insert({
      'conversation_id': conversationId,
      'sender_id': user.id,
      'content': body,
    });
    await _client.from(_conversationsTable).update({
      'last_message': body,
      'last_sender_id': user.id,
      'last_message_at': now,
    }).eq('id', conversationId);

    return Conversation.fromJson(
      {
        ...convoRow,
        'last_message': body,
        'last_sender_id': user.id,
        'last_message_at': now,
      },
      currentUserId: user.id,
    );
  }

  /// True when an `accepted` friendship row exists between the two
  /// users (in either direction). Used by createConversation to skip
  /// the message-request wall for established friends.
  static Future<bool> _areAcceptedFriends(String a, String b) async {
    if (a.isEmpty || b.isEmpty || a == b) return false;
    try {
      final rows = await _client
          .from('friendships')
          .select('id')
          .eq('status', 'accepted')
          .or(
            'and(requester_id.eq.$a,addressee_id.eq.$b),'
            'and(requester_id.eq.$b,addressee_id.eq.$a)',
          )
          .limit(1);
      return (rows as List).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Promotes a pending request to a normal conversation. Idempotent.
  static Future<void> acceptRequest(String conversationId) async {
    await _client
        .from(_conversationsTable)
        .update({'request_status': 'accepted'})
        .eq('id', conversationId);
  }

  /// Declines a pending request OR removes an accepted conversation
  /// from the caller's inbox. patch_032: this no longer hard-deletes
  /// the row when the OTHER party still has their copy — it stamps a
  /// `deleted_by_{a|b}_at` timestamp instead, and the inbox query
  /// filters those rows out for the caller. The DB RPC also hard-
  /// deletes if both sides have soft-deleted, so we don't accumulate
  /// orphaned threads forever.
  static Future<void> declineRequest(String conversationId) async {
    try {
      await _client.rpc(
        'soft_delete_conversation',
        params: {
          'p_conversation_id':
              int.tryParse(conversationId) ?? conversationId,
        },
      );
    } catch (_) {
      // RPC missing or transient — fall back to the legacy hard delete
      // so the caller's request to dismiss the thread isn't dropped.
      await _client
          .from(_conversationsTable)
          .delete()
          .eq('id', conversationId);
    }
  }

  /// Per-user message visibility floor (patch_085): the latest of
  /// cleared_at, group joined_at, and church-join time. Messages at/before
  /// this are hidden for the caller (clear-chat + history-from-join).
  static Future<DateTime?> messageFloor(String conversationId) async {
    if (_client.auth.currentUser == null) return null;
    try {
      final res = await _client
          .rpc('message_floor', params: {'p_conv': int.parse(conversationId)});
      return res == null ? null : DateTime.tryParse(res.toString());
    } catch (_) {
      return null;
    }
  }

  /// "Delete for me" — hide the given messages for the current user only.
  static Future<void> hideMessages(List<String> messageIds) async {
    final ids = messageIds
        .map((e) => int.tryParse(e))
        .whereType<int>()
        .toList();
    if (ids.isEmpty) return;
    await _client.rpc('hide_messages', params: {'p_ids': ids});
  }

  /// Message ids the caller has hidden ("deleted for me") in a chat.
  static Future<Set<String>> fetchHiddenMessageIds(String conversationId) async {
    try {
      final res = await _client.rpc('hidden_message_ids',
          params: {'p_conv': int.parse(conversationId)});
      if (res is List) return res.map((e) => e.toString()).toSet();
      return const {};
    } catch (_) {
      return const {};
    }
  }

  // ---- Local "deleted for me" cache --------------------------------------
  // The server is the source of truth, but fetchHiddenMessageIds is a network
  // round-trip. The message cache stores RAW rows that don't know they were
  // hidden, so on reopen the cached paint flashed a just-deleted message back
  // for ~1s until the server hidden-ids arrived. We mirror the hidden ids into
  // a synchronous local cache so the paint can filter them INSTANTLY.
  static String _hiddenCacheKey(String conversationId) =>
      'chat_hidden:$conversationId';

  /// Hidden ids persisted locally, read synchronously (no await) so the
  /// cached-message paint filters them before any server round-trip.
  static Set<String> readHiddenIdsCached(String conversationId) {
    final raw = CacheService.readStringStale(_hiddenCacheKey(conversationId));
    if (raw == null || raw.isEmpty) return <String>{};
    try {
      return (jsonDecode(raw) as List).map((e) => e.toString()).toSet();
    } catch (_) {
      return <String>{};
    }
  }

  /// Merge [ids] into the locally-persisted hidden set for a conversation.
  static Future<void> addHiddenIdsCached(
      String conversationId, Iterable<String> ids) async {
    final merged = readHiddenIdsCached(conversationId)..addAll(ids);
    await CacheService.writeString(
        _hiddenCacheKey(conversationId), jsonEncode(merged.toList()));
  }

  // ---- Per-user inbox preview floor --------------------------------------
  // conversations.last_message is a SHARED, denormalised column, but
  // delete-for-me is per-user. When a user hides their conversation's last
  // message for themselves, the inbox kept showing it (tester: "delete a
  // message for me, it still appears outside the chat"). We persist the
  // timestamp of the hidden last message locally; the inbox suppresses the
  // stale preview for THIS user until a newer message arrives (last_message_at
  // moves past the floor). Persistent (no TTL) so it survives restarts.
  static String _previewFloorKey(String conversationId) =>
      'preview_floor:$conversationId';

  static Future<void> setInboxPreviewFloor(
      String conversationId, DateTime ts) async {
    await CacheService.writePref(
        _previewFloorKey(conversationId), ts.toIso8601String());
  }

  static DateTime? inboxPreviewFloor(String conversationId) {
    final raw = CacheService.readPref(_previewFloorKey(conversationId));
    return raw == null ? null : DateTime.tryParse(raw);
  }

  /// Clear the chat for the current user only (WhatsApp parity). Persists
  /// cleared_at (server) and empties the local message cache so the
  /// messages don't reappear from cache on the next (offline) open.
  static Future<void> clearConversation(String conversationId) async {
    await _client.rpc('clear_conversation', params: {
      'p_conversation': int.parse(conversationId),
    });
    unawaited(_writeMessagesCache(conversationId, const []));
  }

  static Future<List<Message>> fetchMessages(String conversationId) async {
    // Offline → serve from cache so the user can still read older
    // messages with no connection (WhatsApp parity).
    if (!ConnectivityService.isOnline) {
      return readCachedMessages(conversationId);
    }
    // Visibility floor (patch_085): clear-chat + history-from-join.
    final clearedAt = await messageFloor(conversationId);
    List<dynamic> response;
    try {
      // Fetch the NEWEST 500 (descending), then reverse to chronological
      // for display. Ordering ascending + limit returned the OLDEST 500,
      // which hid recent messages once a thread passed 500 messages.
      var query = _client
          .from(_messagesTable)
          .select()
          .eq('conversation_id', conversationId);
      if (clearedAt != null) {
        query = query.gt('created_at', clearedAt.toIso8601String());
      }
      final newestFirst = await query
          .order('created_at', ascending: false)
          .limit(500) as List;
      response = newestFirst.reversed.toList();
    } catch (_) {
      return readCachedMessages(conversationId);
    }
    // Persist for the next offline open. We write the raw rows so a
    // restore looks exactly like a fresh fetch.
    unawaited(_writeMessagesCache(
      conversationId,
      response.map((r) => Map<String, dynamic>.from(r as Map)).toList(),
    ));
    return response
        .map((row) => Message.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  static Future<Message> sendMessage({
    required String conversationId,
    required String content,
    String? replyToId,
    bool forwarded = false,
    String messageType = 'text',
    Map<String, dynamic>? meta,
    String? clientId,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to send messages.');
    }
    final body = content.trim();
    final payload = <String, dynamic>{
      'conversation_id': conversationId,
      'sender_id': user.id,
      'content': body,
      if (messageType != 'text') 'message_type': messageType,
      'meta': ?meta,
      'client_id': ?clientId,
      if (replyToId != null) 'reply_to_id': int.tryParse(replyToId),
      if (forwarded) 'forwarded': true,
    };

    // Offline path — queue and surface an OutboxQueuedException so the
    // UI can show a "we'll send this when you reconnect" hint instead
    // of the generic failure snackbar.
    if (!ConnectivityService.isOnline) {
      await _enqueueOutbox(payload);
      throw const OutboxQueuedException();
    }

    try {
      final response = await _client
          .from(_messagesTable)
          .insert(payload)
          .select()
          .single();
      final message = Message.fromJson(response);
      await _client.from(_conversationsTable).update({
        'last_message': message.content,
        'last_sender_id': user.id,
        'last_message_at': message.createdAt.toIso8601String(),
      }).eq('id', conversationId);
      AnalyticsService.messageSent(source: 'text');
      return message;
    } catch (e) {
      // If the network dropped between the connectivity check and the
      // insert, fall back to the outbox.
      if (!ConnectivityService.isOnline) {
        await _enqueueOutbox(payload);
        throw const OutboxQueuedException();
      }
      rethrow;
    }
  }

  static Stream<List<Message>> streamMessages(String conversationId) {
    return _client
        .from(_messagesTable)
        .stream(primaryKey: ['id'])
        .eq('conversation_id', conversationId)
        .order('created_at')
        .map((rows) => rows
            .map((row) => Message.fromJson(row))
            .toList());
  }

  // ---------- offline cache ----------

  static const _inboxCacheKey = 'inbox_v1';
  static String _chatCacheKey(String conversationId) => 'chat:$conversationId';

  /// Read the cached inbox even if it's older than 24h — when the
  /// device is offline we'd rather show stale conversations than a
  /// blank Inbox screen.
  static List<Conversation> readCachedInbox() {
    final raw = CacheService.readStringStale(_inboxCacheKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final user = _client.auth.currentUser;
      if (user == null) return const [];
      final list = jsonDecode(raw) as List;
      final convos = list
          .map((row) => Conversation.fromJson(
                Map<String, dynamic>.from(row as Map),
                currentUserId: user.id,
              ))
          .toList();
      // Sort identically to the live fetch (self-chat first, then newest
      // first) so the cache-first paint matches the fresh result and the
      // tiles don't visibly jump into place on refresh.
      convos.sort((a, b) {
        if (a.isSelfChat && !b.isSelfChat) return -1;
        if (b.isSelfChat && !a.isSelfChat) return 1;
        return b.lastMessageAt.compareTo(a.lastMessageAt);
      });
      return convos;
    } catch (_) {
      return const [];
    }
  }

  static Future<void> _writeInboxCache(List<Map<String, dynamic>> rows) async {
    await CacheService.writeString(_inboxCacheKey, jsonEncode(rows));
  }

  /// Read cached messages for a conversation. Returns the list as we
  /// last saw it from the server — newest at the end, same ordering
  /// as [fetchMessages] / [streamMessages] expose.
  static List<Message> readCachedMessages(String conversationId) {
    final raw = CacheService.readStringStale(_chatCacheKey(conversationId));
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((row) => Message.fromJson(Map<String, dynamic>.from(row as Map)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> _writeMessagesCache(
    String conversationId,
    List<Map<String, dynamic>> rows,
  ) async {
    await CacheService.writeString(
      _chatCacheKey(conversationId),
      jsonEncode(rows),
    );
  }

  // ---------- blocking ----------

  static const _blocksTable = 'blocked_users';

  /// Block [otherUserId]: insert a blocked_users row keyed by the
  /// current user. Idempotent — re-blocking is a no-op.
  static Future<void> blockUser(String otherUserId) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to block users.');
    }
    try {
      await _client.from(_blocksTable).insert({
        'blocker_id': user.id,
        'blocked_id': otherUserId,
      });
    } catch (e) {
      // Duplicate-key (already-blocked) is fine; bubble anything else.
      if (e is PostgrestException && e.code == '23505') return;
      rethrow;
    }
  }

  /// Unblock [otherUserId].
  static Future<void> unblockUser(String otherUserId) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    await _client
        .from(_blocksTable)
        .delete()
        .eq('blocker_id', user.id)
        .eq('blocked_id', otherUserId);
  }

  /// True when the current viewer has blocked [otherUserId].
  static Future<bool> isBlockedByMe(String otherUserId) async {
    final user = _client.auth.currentUser;
    if (user == null) return false;
    try {
      final row = await _client
          .from(_blocksTable)
          .select('id')
          .eq('blocker_id', user.id)
          .eq('blocked_id', otherUserId)
          .maybeSingle();
      return row != null;
    } catch (_) {
      return false;
    }
  }

  // ---------- read / delivered receipts ----------

  /// Mark EVERY undelivered incoming message (1:1 + group) as delivered
  /// for the current user. Called on app resume / reconnect so a sender's
  /// tick goes ✓✓ once the recipient comes back online, regardless of
  /// which screen they land on (patch_062). Best-effort.
  static Future<void> markAllIncomingDelivered() async {
    if (_client.auth.currentUser == null) return;
    try {
      await _client.rpc('mark_all_incoming_delivered');
    } catch (_) {
      // Best-effort — screen-level passes still cover the common case.
    }
  }

  /// Mark unread messages from [otherSenderIds] as delivered (but
  /// not read). WhatsApp fires this when the recipient's device has
  /// the message in hand — before they've actually opened the chat.
  /// Two grey ticks then appear on the sender's side via the stream.
  ///
  /// The list is built client-side from the realtime stream so we
  /// only issue an UPDATE for genuinely-new inbound rows, not every
  /// frame.
  /// Hard-delete a message the current user sent. RLS rejects deletes
  /// on anyone else's row, so callers don't need a client-side guard
  /// beyond hiding the menu for incoming messages — the database is
  /// authoritative. The realtime stream propagates the DELETE event
  /// to the other party so the bubble disappears on their side too.
  static Future<void> deleteMessage(String messageId) async {
    await _client.from(_messagesTable).delete().eq('id', messageId);
  }

  /// "Delete for everyone" — soft delete (sender only, via RLS). Clears
  /// content + media and flags the row so both sides render a
  /// "This message was deleted" tombstone (the row stays).
  /// Pin (or unpin, with null) a message in a conversation (patch_106).
  static Future<void> setPinnedMessage(
      String conversationId, String? messageId) async {
    await _client.rpc('set_pinned_message', params: {
      'p_conv': int.tryParse(conversationId) ?? conversationId,
      'p_message_id': messageId == null ? null : int.tryParse(messageId),
    });
  }

  static Future<void> softDeleteMessage(String messageId) async {
    await _client.from(_messagesTable).update({
      'is_deleted': true,
      'content': '',
      'media_url': null,
    }).eq('id', messageId);
  }

  /// Edit a sent message's text (sender only — enforced by RLS). Stamps
  /// edited_at so the UI can show an "edited" label.
  static Future<void> editMessage(String messageId, String newContent) async {
    await _client.from(_messagesTable).update({
      'content': newContent.trim(),
      'edited_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', messageId);
  }

  // ----- Reactions (patch_056) ---------------------------------------
  /// Set (or replace) the current user's reaction on a message. Passing
  /// the same emoji that's already set removes it (toggle).
  static Future<void> toggleReaction(String messageId, String emoji) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    final id = int.tryParse(messageId);
    if (id == null) return;
    final existing = await _client
        .from('message_reactions')
        .select('emoji')
        .eq('message_id', id)
        .eq('user_id', user.id)
        .maybeSingle();
    if (existing != null && existing['emoji'] == emoji) {
      await _client
          .from('message_reactions')
          .delete()
          .eq('message_id', id)
          .eq('user_id', user.id);
    } else {
      await _client.from('message_reactions').upsert({
        'message_id': id,
        'user_id': user.id,
        'emoji': emoji,
      });
    }
  }

  /// All reactions for a conversation, grouped by message id →
  /// {emoji: count} plus the viewer's own emoji under key '_mine'.
  static Future<Map<String, Map<String, int>>> fetchReactions(
    String conversationId,
  ) async {
    final user = _client.auth.currentUser;
    try {
      final rows = await _client
          .from('message_reactions')
          .select('message_id, user_id, emoji, messages!inner(conversation_id)')
          .eq('messages.conversation_id', int.parse(conversationId));
      final out = <String, Map<String, int>>{};
      for (final r in rows as List) {
        final map = r as Map<String, dynamic>;
        final mid = map['message_id'].toString();
        final emoji = map['emoji'].toString();
        final byMsg = out.putIfAbsent(mid, () => <String, int>{});
        byMsg[emoji] = (byMsg[emoji] ?? 0) + 1;
        if (user != null && map['user_id'].toString() == user.id) {
          byMsg['_mine_$emoji'] = 1;
        }
      }
      return out;
    } catch (_) {
      return const {};
    }
  }

  // ----- Starred messages (patch_056) --------------------------------
  static Future<void> toggleStar(String messageId, {required bool starred}) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    final id = int.tryParse(messageId);
    if (id == null) return;
    if (starred) {
      await _client
          .from('starred_messages')
          .delete()
          .eq('message_id', id)
          .eq('user_id', user.id);
    } else {
      await _client.from('starred_messages').upsert({
        'message_id': id,
        'user_id': user.id,
      });
    }
  }

  /// Lazily create the caller's church channel + members conversations
  /// (patch_066). Best-effort — called on chat-list load.
  static Future<void> ensureMyChurchConversations() async {
    if (_client.auth.currentUser == null) return;
    try {
      await _client.rpc('ensure_my_church_conversations');
    } catch (_) {
      // No church set / RPC issue — non-fatal.
    }
  }

  /// Whether the caller may post in a church ANNOUNCEMENT channel
  /// (verified church admin / super admin). Members chat is open.
  static Future<bool> canPostToChurchChannel(String conversationId) async {
    try {
      final res = await _client.rpc('can_post_church_channel',
          params: {'p_conv': int.tryParse(conversationId) ?? conversationId});
      return res == true;
    } catch (_) {
      return false;
    }
  }

  /// Per-user pin/mute/archive flags, keyed by conversation id. Empty
  /// map on error so the inbox still renders with default (unflagged)
  /// state.
  static Future<Map<String, ConversationState>>
      fetchConversationStates() async {
    final user = _client.auth.currentUser;
    if (user == null) return const {};
    try {
      final rows = await _client
          .from('conversation_state')
          .select()
          .eq('user_id', user.id);
      return {
        for (final r in (rows as List))
          (r as Map)['conversation_id'].toString():
              ConversationState.fromJson(Map<String, dynamic>.from(r)),
      };
    } catch (_) {
      return const {};
    }
  }

  /// Set one or more pin/mute/archive flags for a conversation (upsert).
  static Future<void> setConversationFlags(
    String conversationId, {
    bool? pinned,
    bool? muted,
    bool? archived,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    await _client.from('conversation_state').upsert({
      'user_id': user.id,
      'conversation_id': int.parse(conversationId),
      'pinned': ?pinned,
      'muted': ?muted,
      'archived': ?archived,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'user_id,conversation_id');
  }

  /// All messages the viewer has starred, across every chat, newest
  /// star first. Used by the Starred-messages screen.
  static Future<List<Message>> fetchStarredMessages() async {
    final user = _client.auth.currentUser;
    if (user == null) return const [];
    try {
      final rows = await _client
          .from('starred_messages')
          .select('created_at, messages!inner(*)')
          .eq('user_id', user.id)
          .order('created_at', ascending: false);
      return (rows as List)
          .map((r) => Message.fromJson(
              ((r as Map)['messages']) as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// The set of message ids the viewer has starred in a conversation.
  static Future<Set<String>> fetchStarredIds(String conversationId) async {
    try {
      final rows = await _client
          .from('starred_messages')
          .select('message_id, messages!inner(conversation_id)')
          .eq('messages.conversation_id', int.parse(conversationId));
      return (rows as List)
          .map((r) => (r as Map)['message_id'].toString())
          .toSet();
    } catch (_) {
      return <String>{};
    }
  }

  static Future<void> markMessagesDelivered(List<String> messageIds) async {
    if (messageIds.isEmpty) return;
    try {
      // patch_032: messages_update_sender RLS doesn't let the recipient
      // touch the row, so we route through a SECURITY DEFINER RPC that
      // only writes delivered_at on incoming messages.
      await _client.rpc(
        'mark_message_delivered',
        params: {'p_ids': messageIds},
      );
    } catch (_) {
      // Delivery receipts are best-effort — never block chat rendering.
    }
  }

  /// Bulk variant of [markMessagesDelivered]. The push handler only
  /// gets the conversation id off the FCM payload (no individual
  /// message ids), so we flip every undelivered incoming message in
  /// the conversation in one round-trip. Backed by
  /// `mark_conversation_delivered` (patch_038). Fires from
  /// PushService when an FCM "conversation" notification lands, so
  /// the sender's tick goes double as soon as the recipient's device
  /// receives the push — not when they later open the chat screen.
  static Future<void> markConversationDelivered(String conversationId) async {
    final id = int.tryParse(conversationId);
    if (id == null) return;
    try {
      await _client.rpc(
        'mark_conversation_delivered',
        params: {'p_conversation_id': id},
      );
    } catch (_) {
      // Best-effort — the next time the user opens the chat, the
      // per-message RPC catches anything we missed.
    }
  }

  /// Mark every unread message in this conversation that was sent by
  /// someone other than the current user as read. Called when the user
  /// opens the chat — the other party will then see the double-tick
  /// (via streamMessages picking up the updated rows).
  ///
  /// IMPORTANT: we always flip `read = true` regardless of whether the
  /// viewer has read receipts on or off. Previous behaviour was to
  /// skip the UPDATE entirely when receipts were off, but that ALSO
  /// meant the viewer's own inbox unread badge never cleared (the
  /// badge counts `read = false` rows from the other sender). The
  /// receipt opt-out should hide the blue tick from the SENDER, not
  /// disable the viewer's own bookkeeping. If the user wants the
  /// sender to never see read state, omit the `read_at` timestamp
  /// — `read = true` still resets the badge locally, and the sender's
  /// chat tick only flips blue when `read_at` is non-null.
  static Future<void> markConversationRead(String conversationId) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    try {
      final profileRow = await _client
          .from('profiles')
          .select('show_read_receipts')
          .eq('id', user.id)
          .maybeSingle();
      final wantsReceipts = profileRow == null ||
          profileRow['show_read_receipts'] != false;
      // patch_032: same RLS reason as markMessagesDelivered — recipient
      // cannot UPDATE the row directly, so we go through the SECURITY
      // DEFINER RPC. p_with_timestamp=false leaves read_at NULL so the
      // sender's blue tick never lights up when the viewer has read
      // receipts disabled.
      await _client.rpc(
        'mark_conversation_read',
        params: {
          'p_conversation_id': int.tryParse(conversationId) ?? conversationId,
          'p_with_timestamp': wantsReceipts,
        },
      );
      // Also stamp last_read_at so church groups (implicit membership,
      // no per-message read flag) clear their unread badge (patch_090).
      await _client.rpc('mark_conversation_read_at',
          params: {'p_conv': int.tryParse(conversationId) ?? conversationId});
    } catch (_) {
      // Read receipts are best-effort — never block chat rendering.
    }
    // Groups don't use the 1:1 read boolean — stamp the per-member
    // last-read marker so the group's unread badge clears (patch_060).
    try {
      await _client.rpc('mark_group_read', params: {
        'p_conversation': int.tryParse(conversationId) ?? conversationId,
      });
    } catch (_) {
      // Not a group / RPC issue — ignore.
    }
  }

  /// Subscribe to typing pings from the other party. Emits `true` for
  /// roughly the [staleAfter] duration after each ping; falls back to
  /// `false` if no follow-up arrives. The caller is responsible for
  /// cancelling the returned channel via [stopTyping] on dispose.
  ///
  /// Uses Supabase Realtime Broadcast (not DB-backed) — typing state is
  /// ephemeral and doesn't need to survive a refresh.
  static RealtimeChannel subscribeTyping({
    required String conversationId,
    required void Function(String typingUserId) onTyping,
  }) {
    final me = _client.auth.currentUser?.id;
    final channel = _client.channel(_typingChannelName(conversationId));
    channel
        .onBroadcast(
          event: 'typing',
          callback: (payload) {
            final from = (payload['user_id'] ?? '').toString();
            if (from.isEmpty || from == me) return;
            onTyping(from);
          },
        )
        .subscribe();
    return channel;
  }

  /// Send a "typing" ping on the conversation's broadcast channel.
  /// The caller should debounce — emitting once every 1.5-2 seconds
  /// while the input has text is plenty.
  static Future<void> broadcastTyping(RealtimeChannel channel) async {
    final me = _client.auth.currentUser?.id;
    if (me == null) return;
    try {
      await channel.sendBroadcastMessage(
        event: 'typing',
        payload: {'user_id': me, 'ts': DateTime.now().millisecondsSinceEpoch},
      );
    } catch (_) {
      // No-op: typing pings are decorative.
    }
  }

  /// Uploads a recorded voice clip and inserts a `message_type='voice'`
  /// row. The bucket is private, so [Message.mediaUrl] stores the
  /// storage path — playback resolves a signed URL on demand via
  /// [signedVoiceUrl]. RLS in patch_003 ensures only conversation
  /// participants can read/write.
  ///
  /// Path layout: `{conversation_id}/{sender_id}/{timestamp}.m4a` —
  /// matches the foldername-based policies in
  /// `database/patch_003_voice_notes.sql`.
  static Future<Message> sendVoiceNote({
    required String conversationId,
    required String localFilePath,
    required int durationSeconds,
    String? replyToId,
    void Function(double progress)? onProgress,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to send voice notes.');
    }
    final file = File(localFilePath);
    if (!await file.exists()) {
      throw const StorageException('Recording not found on disk.');
    }
    final ts = DateTime.now().millisecondsSinceEpoch;
    final storagePath = '$conversationId/${user.id}/$ts.m4a';
    final bytes = await file.readAsBytes();
    await _uploadWithProgress(
      bucket: _voiceBucket,
      storagePath: storagePath,
      bytes: bytes,
      contentType: 'audio/aac',
      onProgress: onProgress ?? (_) {},
    );

    final response = await _client
        .from(_messagesTable)
        .insert({
          'conversation_id': conversationId,
          'sender_id': user.id,
          'content': '🎙️ Voice note',
          'message_type': 'voice',
          'media_url': storagePath,
          'media_duration_seconds': durationSeconds,
          if (replyToId != null) 'reply_to_id': int.tryParse(replyToId),
        })
        .select()
        .single();
    final message = Message.fromJson(response);
    await _client.from(_conversationsTable).update({
      'last_message': '🎙️ Voice note',
      'last_sender_id': user.id,
      'last_message_at': message.createdAt.toIso8601String(),
    }).eq('id', conversationId);
    AnalyticsService.messageSent(source: 'voice');
    return message;
  }

  /// Returns a signed playback URL for a voice-note storage path
  /// (valid for [ttlSeconds]). The bucket is private — direct URLs
  /// won't work. Caller is responsible for caching during a session.
  static Future<String> signedVoiceUrl(
    String storagePath, {
    int ttlSeconds = 3600,
  }) async {
    return _client.storage
        .from(_voiceBucket)
        .createSignedUrl(storagePath, ttlSeconds);
  }

  /// Downloads the raw bytes of a voice note from the private bucket.
  /// Used by VoicePlayerService to cache the clip locally and play it
  /// from disk (streaming a signed URL truncated long notes on Android).
  static Future<Uint8List> downloadVoiceBytes(String storagePath) {
    return _client.storage.from(_voiceBucket).download(storagePath);
  }

  /// Streams a voice note over its signed URL, reporting download progress
  /// (0.0–1.0, or null when the server doesn't send a content-length) via
  /// [onProgress] — so the bubble can show a WhatsApp-style download ring.
  /// Falls back to a plain download if streaming fails.
  static Future<Uint8List> downloadVoiceWithProgress(
    String storagePath,
    void Function(double? progress) onProgress,
  ) async {
    try {
      final url = await signedVoiceUrl(storagePath);
      final client = HttpClient();
      final req = await client.getUrl(Uri.parse(url));
      final resp = await req.close();
      final total = resp.contentLength;
      final builder = BytesBuilder(copy: false);
      var received = 0;
      await for (final chunk in resp) {
        builder.add(chunk);
        received += chunk.length;
        onProgress(total > 0 ? received / total : null);
      }
      client.close();
      return builder.takeBytes();
    } catch (_) {
      onProgress(null);
      return downloadVoiceBytes(storagePath);
    }
  }

  // ===================================================================
  // CHAT MEDIA (images / documents — patch_051, private chat_media bucket)
  // ===================================================================

  static const _chatMediaBucket = 'chat_media';
  // Signed-URL memo so re-rendering an image bubble doesn't mint a fresh
  // URL each build (and so CachedImage can cache by a stable URL).
  static final Map<String, _SignedUrlEntry> _signedMediaCache = {};

  /// Uploads bytes to a private bucket while reporting upload progress
  /// (0.0–1.0) via [onProgress] — used so chat photo/voice bubbles can
  /// show a real progress BAR. Streams a PUT to a signed upload URL; on
  /// ANY failure it falls back to the plain SDK upload so a send never
  /// breaks just because the streamed path didn't work.
  static Future<void> _uploadWithProgress({
    required String bucket,
    required String storagePath,
    required Uint8List bytes,
    required String contentType,
    required void Function(double progress) onProgress,
  }) async {
    try {
      final signed =
          await _client.storage.from(bucket).createSignedUploadUrl(storagePath);
      final client = HttpClient();
      final req = await client.putUrl(Uri.parse(signed.signedUrl));
      req.headers.set(HttpHeaders.contentTypeHeader, contentType);
      req.headers.set('x-upsert', 'false');
      req.contentLength = bytes.length;
      const chunk = 64 * 1024;
      var sent = 0;
      for (var i = 0; i < bytes.length; i += chunk) {
        final end = (i + chunk < bytes.length) ? i + chunk : bytes.length;
        req.add(bytes.sublist(i, end));
        await req.flush();
        sent = end;
        onProgress(bytes.isEmpty ? 1.0 : sent / bytes.length);
      }
      final resp = await req.close();
      await resp.drain();
      client.close();
      if (resp.statusCode >= 300) {
        throw StorageException('Upload failed (${resp.statusCode})');
      }
    } catch (_) {
      onProgress(0.99); // show near-complete while the fallback runs
      await _client.storage.from(bucket).uploadBinary(
            storagePath,
            bytes,
            fileOptions: FileOptions(contentType: contentType, upsert: false),
          );
      onProgress(1.0);
    }
  }

  /// Uploads a compressed image to the private chat_media bucket and
  /// inserts a `message_type='image'` row. Path is conversation-scoped
  /// so the patch_051 RLS limits reads to participants.
  static Future<Message> sendImageMessage({
    required String conversationId,
    required Uint8List bytes,
    required String ext,
    void Function(double progress)? onProgress,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to send photos.');
    }
    final ts = DateTime.now().millisecondsSinceEpoch;
    final storagePath = '$conversationId/${user.id}/$ts.$ext';
    await _uploadWithProgress(
      bucket: _chatMediaBucket,
      storagePath: storagePath,
      bytes: bytes,
      contentType: _imageMime(ext),
      onProgress: onProgress ?? (_) {},
    );
    final response = await _client
        .from(_messagesTable)
        .insert({
          'conversation_id': conversationId,
          'sender_id': user.id,
          'content': '📷 Photo',
          'message_type': 'image',
          'media_url': storagePath,
        })
        .select()
        .single();
    final message = Message.fromJson(response);
    await _client.from(_conversationsTable).update({
      'last_message': '📷 Photo',
      'last_sender_id': user.id,
      'last_message_at': message.createdAt.toIso8601String(),
    }).eq('id', conversationId);
    AnalyticsService.messageSent(source: 'image');
    return message;
  }

  /// Forward a message to another conversation. Text re-sends the
  /// content; image/voice copy the underlying storage object into the
  /// target chat's folder (so the target's RLS lets its members read it)
  /// and insert a fresh media message. All marked forwarded=true.
  static Future<void> forwardMessage({
    required String targetConversationId,
    required Message original,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to forward.');
    }
    final type = original.messageType;
    final src = original.mediaUrl ?? '';
    if ((type == 'image' || type == 'voice') && src.isNotEmpty) {
      final bucket = type == 'image' ? _chatMediaBucket : _voiceBucket;
      final ext = src.contains('.')
          ? src.split('.').last
          : (type == 'image' ? 'jpg' : 'm4a');
      final ts = DateTime.now().millisecondsSinceEpoch;
      final dest = '$targetConversationId/${user.id}/$ts.$ext';
      await _client.storage.from(bucket).copy(src, dest);
      final content = type == 'image' ? '📷 Photo' : '🎙️ Voice note';
      final response = await _client
          .from(_messagesTable)
          .insert({
            'conversation_id': targetConversationId,
            'sender_id': user.id,
            'content': content,
            'message_type': type,
            'media_url': dest,
            if (type == 'voice')
              'media_duration_seconds': original.mediaDurationSeconds,
            'forwarded': true,
          })
          .select()
          .single();
      final message = Message.fromJson(response);
      await _client.from(_conversationsTable).update({
        'last_message': content,
        'last_sender_id': user.id,
        'last_message_at': message.createdAt.toIso8601String(),
      }).eq('id', targetConversationId);
      AnalyticsService.messageSent(source: 'forward_$type');
    } else {
      await sendMessage(
        conversationId: targetConversationId,
        content: original.content,
        forwarded: true,
      );
    }
  }

  /// Signed URL for a chat_media object, memoised until ~2 min before
  /// expiry so repeated bubble rebuilds don't hammer the API.
  static Future<String> signedChatMediaUrl(
    String storagePath, {
    int ttlSeconds = 3600,
  }) async {
    final now = DateTime.now();
    final cached = _signedMediaCache[storagePath];
    if (cached != null &&
        cached.expiry.isAfter(now.add(const Duration(minutes: 2)))) {
      return cached.url;
    }
    final url = await _client.storage
        .from(_chatMediaBucket)
        .createSignedUrl(storagePath, ttlSeconds);
    _signedMediaCache[storagePath] =
        _SignedUrlEntry(url, now.add(Duration(seconds: ttlSeconds)));
    return url;
  }

  static String _imageMime(String ext) {
    switch (ext.toLowerCase()) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      default:
        return 'image/jpeg';
    }
  }
}

class _SignedUrlEntry {
  const _SignedUrlEntry(this.url, this.expiry);
  final String url;
  final DateTime expiry;
}

/// Thrown by [MessagingService.sendMessage] when the device is offline
/// and the payload has been queued in the local outbox. Callers should
/// treat this as a soft success and show a "queued for sending" hint.
class OutboxQueuedException implements Exception {
  const OutboxQueuedException();

  @override
  String toString() => 'Message queued — will send when you reconnect.';
}
