import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/message_model.dart';
import 'analytics_service.dart';
import 'connectivity_service.dart';

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
  static Future<List<Conversation>> fetchConversations() async {
    final user = _client.auth.currentUser;
    if (user == null) return const [];
    final response = await _client
        .from(_conversationsTable)
        .select()
        .or(
          'participant_a_id.eq.${user.id},participant_b_id.eq.${user.id}',
        )
        .order('last_message_at', ascending: false)
        .limit(100);
    return (response as List)
        .map((row) => Conversation.fromJson(
              row as Map<String, dynamic>,
              currentUserId: user.id,
            ))
        .toList();
  }

  /// Creates a conversation (or returns an existing one between the
  /// two users) and posts [firstMessage] into it. New conversations are
  /// inserted with `request_status='pending'` so the recipient sees it
  /// in their Requests inbox until they accept. If a conversation
  /// already exists between the pair in either participant ordering,
  /// it's reused and the message is appended — no duplicate row.
  ///
  /// Returns the conversation (post-insert / post-update) so the caller
  /// can immediately navigate into the chat.
  static Future<Conversation> createConversation({
    required String otherUserId,
    required String otherUserName,
    required String firstMessage,
    String source = 'direct',
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to send a message request.');
    }
    final body = firstMessage.trim();
    if (body.isEmpty) {
      throw ArgumentError('firstMessage cannot be empty.');
    }
    final meta = user.userMetadata ?? const {};
    final myName = ((meta['full_name'] as String?)?.trim().isNotEmpty == true)
        ? (meta['full_name'] as String).trim()
        : 'Member';

    // Reuse an existing conversation between us if one already exists,
    // regardless of which side seeded it (a/b ordering).
    final existingRows = await _client
        .from(_conversationsTable)
        .select()
        .or(
          'and(participant_a_id.eq.${user.id},participant_b_id.eq.$otherUserId),'
          'and(participant_a_id.eq.$otherUserId,participant_b_id.eq.${user.id})',
        )
        .limit(1);

    Map<String, dynamic> convoRow;
    if ((existingRows as List).isNotEmpty) {
      convoRow = (existingRows.first as Map).cast<String, dynamic>();
    } else {
      final inserted = await _client
          .from(_conversationsTable)
          .insert({
            'participant_a_id': user.id,
            'participant_b_id': otherUserId,
            'participant_a_name': myName,
            'participant_b_name': otherUserName,
            'initiator_id': user.id,
            'conversation_source': source,
            // request_status defaults to 'pending' (patch_005).
          })
          .select()
          .single();
      convoRow = (inserted as Map).cast<String, dynamic>();
    }

    final conversationId = convoRow['id'].toString();
    final now = DateTime.now().toUtc().toIso8601String();
    await _client.from(_messagesTable).insert({
      'conversation_id': conversationId,
      'sender_id': user.id,
      'sender_name': myName,
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

  /// Promotes a pending request to a normal conversation. Idempotent.
  static Future<void> acceptRequest(String conversationId) async {
    await _client
        .from(_conversationsTable)
        .update({'request_status': 'accepted'})
        .eq('id', conversationId);
  }

  /// Declines a pending request by deleting the conversation row.
  /// Messages cascade away. RLS (patch_005) permits this only for
  /// participants.
  static Future<void> declineRequest(String conversationId) async {
    await _client
        .from(_conversationsTable)
        .delete()
        .eq('id', conversationId);
  }

  static Future<List<Message>> fetchMessages(String conversationId) async {
    final response = await _client
        .from(_messagesTable)
        .select()
        .eq('conversation_id', conversationId)
        .order('created_at', ascending: true)
        .limit(500);
    return (response as List)
        .map((row) => Message.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  static Future<Message> sendMessage({
    required String conversationId,
    required String content,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to send messages.');
    }
    final meta = user.userMetadata ?? const {};
    final senderName = (meta['full_name'] as String?)?.trim();
    final resolvedName =
        senderName?.isNotEmpty == true ? senderName! : 'Member';
    final body = content.trim();
    final payload = <String, dynamic>{
      'conversation_id': conversationId,
      'sender_id': user.id,
      'sender_name': resolvedName,
      'content': body,
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

  /// Mark every unread message in this conversation that was sent by
  /// someone other than the current user as read. Called when the user
  /// opens the chat — the other party will then see the double-tick
  /// (via streamMessages picking up the updated rows).
  static Future<void> markConversationRead(String conversationId) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    try {
      await _client
          .from(_messagesTable)
          .update({
            'read': true,
            'read_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('conversation_id', conversationId)
          .eq('read', false)
          .neq('sender_id', user.id);
    } catch (_) {
      // Read receipts are best-effort — never block chat rendering.
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
    await _client.storage.from(_voiceBucket).upload(
          storagePath,
          file,
          fileOptions: const FileOptions(
            contentType: 'audio/aac',
            upsert: false,
          ),
        );

    final meta = user.userMetadata ?? const {};
    final senderName = (meta['full_name'] as String?)?.trim();
    final response = await _client
        .from(_messagesTable)
        .insert({
          'conversation_id': conversationId,
          'sender_id': user.id,
          'sender_name':
              senderName?.isNotEmpty == true ? senderName : 'Member',
          'content': '🎙️ Voice note',
          'message_type': 'voice',
          'media_url': storagePath,
          'media_duration_seconds': durationSeconds,
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
}

/// Thrown by [MessagingService.sendMessage] when the device is offline
/// and the payload has been queued in the local outbox. Callers should
/// treat this as a soft success and show a "queued for sending" hint.
class OutboxQueuedException implements Exception {
  const OutboxQueuedException();

  @override
  String toString() => 'Message queued — will send when you reconnect.';
}
