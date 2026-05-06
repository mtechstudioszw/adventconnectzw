class Conversation {
  const Conversation({
    required this.id,
    required this.otherUserId,
    required this.otherUserName,
    required this.lastMessage,
    required this.lastMessageAt,
    this.unreadCount = 0,
    this.lastSenderId,
  });

  final String id;
  final String otherUserId;
  final String otherUserName;
  final String lastMessage;
  final DateTime lastMessageAt;
  final int unreadCount;
  final String? lastSenderId;

  factory Conversation.fromJson(
    Map<String, dynamic> json, {
    required String currentUserId,
  }) {
    final participantA = (json['participant_a_id'] ?? '').toString();
    final participantB = (json['participant_b_id'] ?? '').toString();
    final isCurrentA = participantA == currentUserId;
    final otherId = isCurrentA ? participantB : participantA;
    final otherName = (isCurrentA
            ? json['participant_b_name']
            : json['participant_a_name'])
        ?.toString() ??
        'Member';
    return Conversation(
      id: json['id'].toString(),
      otherUserId: otherId,
      otherUserName: otherName,
      lastMessage: (json['last_message'] ?? '') as String,
      lastMessageAt: DateTime.tryParse(
              json['last_message_at']?.toString() ?? '') ??
          DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      unreadCount: _readInt(json['unread_count']),
      lastSenderId: json['last_sender_id']?.toString(),
    );
  }

  Conversation copyWith({
    String? lastMessage,
    DateTime? lastMessageAt,
    int? unreadCount,
    String? lastSenderId,
  }) {
    return Conversation(
      id: id,
      otherUserId: otherUserId,
      otherUserName: otherUserName,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      unreadCount: unreadCount ?? this.unreadCount,
      lastSenderId: lastSenderId ?? this.lastSenderId,
    );
  }

  static int _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }
}

class Message {
  const Message({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.senderName,
    required this.content,
    required this.createdAt,
  });

  final String id;
  final String conversationId;
  final String senderId;
  final String senderName;
  final String content;
  final DateTime createdAt;

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'].toString(),
      conversationId: (json['conversation_id'] ?? '').toString(),
      senderId: (json['sender_id'] ?? '').toString(),
      senderName: (json['sender_name'] ?? 'Member') as String,
      content: (json['content'] ?? '') as String,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}
