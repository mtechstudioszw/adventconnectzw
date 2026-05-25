class Conversation {
  const Conversation({
    required this.id,
    required this.otherUserId,
    required this.otherUserName,
    required this.lastMessage,
    required this.lastMessageAt,
    this.otherUserPhotoUrl,
    this.unreadCount = 0,
    this.lastSenderId,
    this.requestStatus = 'accepted',
    this.initiatorId,
    this.isBusiness = false,
    this.isSelfChat = false,
  });

  final String id;
  final String otherUserId;
  final String otherUserName;
  final String? otherUserPhotoUrl;
  final String lastMessage;
  final DateTime lastMessageAt;
  final int unreadCount;
  final String? lastSenderId;
  final String requestStatus;
  final String? initiatorId;
  final bool isBusiness;
  final bool isSelfChat;

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
    final selfChat =
        participantA.isNotEmpty && participantA == participantB;
    final isCurrentA = participantA == currentUserId;
    final otherId = selfChat
        ? currentUserId
        : (isCurrentA ? participantB : participantA);
    final otherName = selfChat
        ? 'Notes to self'
        : ((isCurrentA
                    ? json['participant_b_name']
                    : json['participant_a_name'])
                ?.toString() ??
            'Member');
    // The joined profile photo is brought in by fetchConversations
    // via select('*, participant_a:participant_a_id(profile_photo_url),
    // participant_b:participant_b_id(profile_photo_url)'). Pick the
    // side that ISN'T the viewer so the inbox tile shows the other
    // person's avatar.
    String? otherPhoto;
    final pa = json['participant_a'];
    final pb = json['participant_b'];
    if (selfChat) {
      otherPhoto = (pa is Map ? pa['profile_photo_url'] : null) as String?;
    } else if (isCurrentA) {
      otherPhoto = (pb is Map ? pb['profile_photo_url'] : null) as String?;
    } else {
      otherPhoto = (pa is Map ? pa['profile_photo_url'] : null) as String?;
    }
    return Conversation(
      id: json['id'].toString(),
      otherUserId: otherId,
      otherUserName: otherName,
      otherUserPhotoUrl: otherPhoto,
      lastMessage: (json['last_message'] ?? '') as String,
      lastMessageAt: DateTime.tryParse(
              json['last_message_at']?.toString() ?? '') ??
          DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      unreadCount: _readInt(json['unread_count']),
      lastSenderId: json['last_sender_id']?.toString(),
      requestStatus: (json['request_status'] ?? 'accepted') as String,
      initiatorId: json['initiator_id']?.toString(),
      isBusiness: json['is_business'] == true,
      isSelfChat: selfChat,
    );
  }

  Conversation copyWith({
    String? lastMessage,
    DateTime? lastMessageAt,
    int? unreadCount,
    String? lastSenderId,
    String? requestStatus,
    String? initiatorId,
    bool? isBusiness,
    bool? isSelfChat,
    String? otherUserPhotoUrl,
  }) {
    return Conversation(
      id: id,
      otherUserId: otherUserId,
      otherUserName: otherUserName,
      otherUserPhotoUrl: otherUserPhotoUrl ?? this.otherUserPhotoUrl,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      unreadCount: unreadCount ?? this.unreadCount,
      lastSenderId: lastSenderId ?? this.lastSenderId,
      requestStatus: requestStatus ?? this.requestStatus,
      initiatorId: initiatorId ?? this.initiatorId,
      isBusiness: isBusiness ?? this.isBusiness,
      isSelfChat: isSelfChat ?? this.isSelfChat,
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
    this.deliveredAt,
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
  // WhatsApp-style three-state tick:
  //   deliveredAt == null && !read → ✓  (single grey: sent only)
  //   deliveredAt != null && !read → ✓✓ (double grey: delivered)
  //   read                         → ✓✓ blue (read)
  final DateTime? deliveredAt;
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
      deliveredAt: json['delivered_at'] == null
          ? null
          : DateTime.tryParse(json['delivered_at'].toString()),
      messageType: (json['message_type'] ?? 'text') as String,
      mediaUrl: json['media_url'] as String?,
      mediaDurationSeconds: (json['media_duration_seconds'] as num?)?.toInt(),
    );
  }
}
