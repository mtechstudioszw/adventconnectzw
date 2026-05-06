import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/message_model.dart';

class MessagingService {
  MessagingService._();

  static final SupabaseClient _client = Supabase.instance.client;

  static const _conversationsTable = 'conversations';
  static const _messagesTable = 'messages';

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
}
