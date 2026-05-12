class Conversation {
  const Conversation({
    required this.id,
    required this.otherUserId,
    required this.otherUserName,
    required this.lastMessage,
    required this.lastMessageAt,
    this.unreadCount = 0,
    this.lastSenderId,
    this.requestStatus = 'accepted',
    this.initiatorId,
  });

  final String id;
  final String otherUserId;
  final String otherUserName;
  final String lastMessage;
  final DateTime lastMessageAt;
  final int unreadCount;
  final String? lastSenderId;
  final String requestStatus;
  final String? initiatorId;

  /// True when this conversation is a pending message request the
  /// current viewer hasn't accepted yet *and* isn't the initiator of —
  /// i.e. the row should live in the Requests inbox, not the main one.
  bool isIncomingRequestFor(String currentUserId) =>
      requestStatus == 'pending' && initiatorId != currentUserId;

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
      requestStatus: (json['request_status'] ?? 'accepted') as String,
      initiatorId: json['initiator_id']?.toString(),
    );
  }

  Conversation copyWith({
    String? lastMessage,
    DateTime? lastMessageAt,
    int? unreadCount,
    String? lastSenderId,
    String? requestStatus,
    String? initiatorId,
  }) {
    return Conversation(
      id: id,
      otherUserId: otherUserId,
      otherUserName: otherUserName,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      unreadCount: unreadCount ?? this.unreadCount,
      lastSenderId: lastSenderId ?? this.lastSenderId,
      requestStatus: requestStatus ?? this.requestStatus,
      initiatorId: initiatorId ?? this.initiatorId,
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
    this.read = false,
    this.readAt,
    this.messageType = 'text',
    this.mediaUrl,
    this.mediaDurationSeconds,
  });

  final String id;
  final String conversationId;
  final String senderId;
  final String senderName;
  final String content;
  final DateTime createdAt;
  final bool read;
  final DateTime? readAt;
  final String messageType;
  final String? mediaUrl;
  final int? mediaDurationSeconds;

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'].toString(),
      conversationId: (json['conversation_id'] ?? '').toString(),
      senderId: (json['sender_id'] ?? '').toString(),
      senderName: (json['sender_name'] ?? 'Member') as String,
      content: (json['content'] ?? '') as String,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      read: json['read'] == true,
      readAt: json['read_at'] == null
          ? null
          : DateTime.tryParse(json['read_at'].toString()),
      messageType: (json['message_type'] ?? 'text') as String,
      mediaUrl: json['media_url'] as String?,
      mediaDurationSeconds: (json['media_duration_seconds'] as num?)?.toInt(),
    );
  }
}
