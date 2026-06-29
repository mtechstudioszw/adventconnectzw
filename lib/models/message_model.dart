/// Per-user pin/mute/archive flags for a conversation (patch_058).
class ConversationState {
  const ConversationState({
    this.pinned = false,
    this.muted = false,
    this.archived = false,
    this.clearedAt,
  });

  final bool pinned;
  final bool muted;
  final bool archived;
  // When the user cleared the chat (patch_081) — the inbox hides the
  // preview of any message at/before this time.
  final DateTime? clearedAt;

  factory ConversationState.fromJson(Map<String, dynamic> json) {
    return ConversationState(
      pinned: json['pinned'] == true,
      muted: json['muted'] == true,
      archived: json['archived'] == true,
      clearedAt: json['cleared_at'] == null
          ? null
          : DateTime.tryParse(json['cleared_at'].toString()),
    );
  }
}

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
    this.isGroup = false,
    this.churchKind,
    this.churchId,
    this.deletedAt,
    this.pinnedMessageId,
    this.lastDelivered = false,
    this.lastRead = false,
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
  // Group chats (patch_052): a conversations row with is_group=TRUE. For
  // groups, [otherUserName]/[otherUserPhotoUrl] hold the GROUP name + icon
  // so inbox tiles and the chat header render uniformly with 1:1 chats.
  final bool isGroup;
  // Church groups (patch_065): 'channel' (admin-post announcements) or
  // 'members' (open church chat). Null for normal chats/groups. These are
  // force-pinned and can't be left/unpinned.
  final String? churchKind;
  // The church this group belongs to (patch_065) — used to submit an
  // admin claim from the announcements channel.
  final String? churchId;
  // Set when an admin soft-deleted the group (patch_095) — read-only.
  final DateTime? deletedAt;
  bool get isDeletedGroup => deletedAt != null;
  // Pinned message id for this conversation (patch_106), or null.
  final String? pinnedMessageId;
  // Delivery state of the LAST message when the viewer sent it (patch_075)
  // — drives the inbox tick (✓ / ✓✓ / ✓✓ blue). Both false otherwise.
  final bool lastDelivered;
  final bool lastRead;

  bool get isChurchGroup => churchKind != null;
  bool get isChurchChannel => churchKind == 'channel';

  /// True when this conversation is a pending message request the
  /// current viewer hasn't accepted yet *and* isn't the initiator of —
  /// i.e. the row should live in the Requests inbox, not the main one.
  bool isIncomingRequestFor(String currentUserId) =>
      requestStatus == 'pending' && initiatorId != currentUserId;

  factory Conversation.fromJson(
    Map<String, dynamic> json, {
    required String currentUserId,
  }) {
    final isGroup = json['is_group'] == true;
    if (isGroup) {
      return Conversation(
        id: json['id'].toString(),
        otherUserId: '',
        otherUserName:
            (json['name'] as String?)?.trim().isNotEmpty == true
                ? (json['name'] as String).trim()
                : 'Group',
        otherUserPhotoUrl: json['photo_url'] as String?,
        lastMessage: (json['last_message'] ?? '') as String,
        lastMessageAt: DateTime.tryParse(
                json['last_message_at']?.toString() ?? '') ??
            DateTime.tryParse(json['created_at']?.toString() ?? '') ??
            DateTime.now(),
        unreadCount: _readInt(json['unread_count']),
        lastSenderId: json['last_sender_id']?.toString(),
        isGroup: true,
        churchKind: json['church_kind'] as String?,
        churchId: json['church_id']?.toString(),
        pinnedMessageId: json['pinned_message_id']?.toString(),
        deletedAt: json['deleted_at'] == null
            ? null
            : DateTime.tryParse(json['deleted_at'].toString()),
        // Hydrate the inbox tick from the (cached) row so a cache-restore
        // keeps ✓✓ instead of reverting to a single ✓.
        lastDelivered: json['last_delivered'] == true,
        lastRead: json['last_read'] == true,
      );
    }
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
      pinnedMessageId: json['pinned_message_id']?.toString(),
      // Hydrate the inbox tick from the (cached) row so a cache-restore
      // keeps ✓✓ instead of reverting to a single ✓ — the "lying tick" bug.
      lastDelivered: json['last_delivered'] == true,
      lastRead: json['last_read'] == true,
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
    bool? isGroup,
    String? otherUserPhotoUrl,
    bool? lastDelivered,
    bool? lastRead,
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
      isGroup: isGroup ?? this.isGroup,
      churchKind: churchKind,
      churchId: churchId,
      lastDelivered: lastDelivered ?? this.lastDelivered,
      lastRead: lastRead ?? this.lastRead,
    );
  }

  static int _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }
}

/// One hit from full-text message search (patch_130 `search_my_messages`).
class MessageSearchHit {
  const MessageSearchHit({
    required this.messageId,
    required this.conversationId,
    required this.content,
    required this.createdAt,
    this.senderId,
  });

  final String messageId;
  final String conversationId;
  final String content;
  final DateTime createdAt;
  final String? senderId;
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
    this.replyToId,
    this.forwarded = false,
    this.editedAt,
    this.isDeleted = false,
    this.meta,
    this.clientId,
    this.voicePlayedAt,
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
  // Phase 4: reply/quote, forward label, edit indicator.
  final String? replyToId;
  final bool forwarded;
  final DateTime? editedAt;
  // Soft-deleted "This message was deleted" tombstone (patch_063).
  final bool isDeleted;
  // Arbitrary message metadata (patch_064). For message_type='product':
  // {product_id, image, title, price}.
  final Map<String, dynamic>? meta;
  // Client idempotency key (patch_070) — lets optimistic rows dedupe
  // against the server echo even when the temp id never became canonical
  // (offline outbox flush).
  final String? clientId;
  // Voice-note play receipt (patch_137): set when the recipient first plays
  // this voice note, so the sender sees a "played" state (WhatsApp blue mic).
  final DateTime? voicePlayedAt;

  bool get isEdited => editedAt != null;
  bool get isVoicePlayed => voicePlayedAt != null;

  Message copyWith({String? content, bool? isDeleted}) {
    return Message(
      id: id,
      conversationId: conversationId,
      senderId: senderId,
      senderName: senderName,
      content: content ?? this.content,
      createdAt: createdAt,
      read: read,
      readAt: readAt,
      deliveredAt: deliveredAt,
      messageType: messageType,
      mediaUrl: mediaUrl,
      mediaDurationSeconds: mediaDurationSeconds,
      replyToId: replyToId,
      forwarded: forwarded,
      editedAt: editedAt,
      isDeleted: isDeleted ?? this.isDeleted,
      meta: meta,
      clientId: clientId,
      voicePlayedAt: voicePlayedAt,
    );
  }

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
      replyToId: json['reply_to_id']?.toString(),
      forwarded: json['forwarded'] == true,
      editedAt: json['edited_at'] == null
          ? null
          : DateTime.tryParse(json['edited_at'].toString()),
      isDeleted: json['is_deleted'] == true,
      meta: json['meta'] is Map
          ? Map<String, dynamic>.from(json['meta'] as Map)
          : null,
      clientId: json['client_id'] as String?,
      voicePlayedAt: json['voice_played_at'] == null
          ? null
          : DateTime.tryParse(json['voice_played_at'].toString()),
    );
  }
}
