/// The friend-graph edge between two users. Mirrors public.friendships
/// (patch_011). Only one row exists per unordered pair (enforced server
/// side via a functional unique index on LEAST/GREATEST).
enum FriendshipStatus { pending, accepted, declined }

class Friendship {
  const Friendship({
    required this.id,
    required this.requesterId,
    required this.addresseeId,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String requesterId;
  final String addresseeId;
  final FriendshipStatus status;
  final DateTime createdAt;

  bool involves(String userId) =>
      userId == requesterId || userId == addresseeId;

  String otherUserId(String viewerId) =>
      viewerId == requesterId ? addresseeId : requesterId;

  bool get isPending => status == FriendshipStatus.pending;
  bool get isAccepted => status == FriendshipStatus.accepted;

  /// True when the row is a pending request the viewer needs to act on
  /// (i.e. they are the addressee, not the requester).
  bool isIncomingPendingFor(String viewerId) =>
      isPending && addresseeId == viewerId;

  factory Friendship.fromJson(Map<String, dynamic> json) {
    final statusStr = (json['status'] ?? 'pending').toString();
    final status = switch (statusStr) {
      'accepted' => FriendshipStatus.accepted,
      'declined' => FriendshipStatus.declined,
      _ => FriendshipStatus.pending,
    };
    return Friendship(
      id: json['id'].toString(),
      requesterId: (json['requester_id'] ?? '').toString(),
      addresseeId: (json['addressee_id'] ?? '').toString(),
      status: status,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}
