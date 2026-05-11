import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/message_model.dart';

class MessagingService {
  MessagingService._();

  static final SupabaseClient _client = Supabase.instance.client;

  static const _conversationsTable = 'conversations';
  static const _messagesTable = 'messages';

  /// Realtime Broadcast channel name for the typing indicator. Keeping
  /// the format here so subscribers and senders stay in sync.
  static String _typingChannelName(String conversationId) =>
      'chat:$conversationId:typing';

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
    final response = await _client
        .from(_messagesTable)
        .insert({
          'conversation_id': conversationId,
          'sender_id': user.id,
          'sender_name':
              senderName?.isNotEmpty == true ? senderName : 'Member',
          'content': content.trim(),
        })
        .select()
        .single();
    final message = Message.fromJson(response);
    await _client.from(_conversationsTable).update({
      'last_message': message.content,
      'last_sender_id': user.id,
      'last_message_at': message.createdAt.toIso8601String(),
    }).eq('id', conversationId);
    return message;
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
}
