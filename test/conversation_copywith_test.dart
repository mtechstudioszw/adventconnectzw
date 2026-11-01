// copyWith used to drop deletedAt and pinnedMessageId (1 Nov 2026): an
// unread reset made a deleted group look live and lost its pinned message.

import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/models/message_model.dart';

void main() {
  final group = Conversation.fromJson(
    {
      'id': 7,
      'is_group': true,
      'name': 'Pathfinders',
      'last_message': 'hi',
      'last_message_at': '2026-11-01T08:00:00Z',
      'unread_count': 4,
      'deleted_at': '2026-10-30T08:00:00Z',
      'pinned_message_id': 99,
      'admins_only_send': true,
    },
    currentUserId: 'me',
  );

  test('reads announcement mode', () {
    expect(group.adminsOnlySend, isTrue);
  });

  test('a copy keeps deleted, pinned and announcement state', () {
    final c = group.copyWith(unreadCount: 0);
    expect(c.unreadCount, 0);
    expect(c.isDeletedGroup, isTrue);
    expect(c.pinnedMessageId, '99');
    expect(c.adminsOnlySend, isTrue);
    expect(group.copyWith(adminsOnlySend: false).adminsOnlySend, isFalse);
  });
}
