// Render harness for the chat redesign (not shipped).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/models/message_model.dart';
import 'package:advent_connect_zw/screens/messaging/chat_screen.dart';
import 'package:advent_connect_zw/screens/messaging/conversations_screen.dart';
import 'package:advent_connect_zw/screens/messaging/create_group_screen.dart';
import 'package:advent_connect_zw/screens/messaging/new_chat_screen.dart';
import 'package:advent_connect_zw/widgets/chat_contact_sheet.dart';

import '../test/helpers/fake_supabase.dart';
import 'shot.dart';

Map<String, Object?> _person(String id, String name, {String? church}) => {
  'id': id,
  'full_name': name,
  'username': name.toLowerCase().split(' ').first,
  'bio': 'Pathfinder leader. Singing in the Glen View choir every Sabbath.',
  'profile_photo_url': null,
  'cover_photo_url': null,
  'city': 'Harare',
  'country': 'ZW',
  'is_discoverable': true,
  'is_verified': id == 'u1',
  'created_at': '2025-02-01T00:00:00Z',
  'church_id': 4,
  'churches': {'name': church ?? 'Glen View SDA Church'},
};

final _people = [
  _person('u1', 'Rudo Moyo'),
  _person('u2', 'Tendai Chikwanha', church: 'Mabvuku SDA Church'),
  _person('u3', 'Nyasha Dube'),
  _person('u4', 'Farai Mutasa', church: 'Avondale SDA Church'),
  _person('u5', 'Chipo Ndlovu'),
];

class _Opener extends StatefulWidget {
  const _Opener();
  @override
  State<_Opener> createState() => _OpenerState();
}

class _OpenerState extends State<_Opener> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showChatContactSheet(
        context,
        userId: 'u1',
        fallbackName: 'Rudo Moyo',
        conversationId: 'c1',
      );
    });
  }

  @override
  Widget build(BuildContext context) =>
      const Scaffold(backgroundColor: Colors.transparent);
}

void main() {
  setUpAll(() async {
    await loadShotFonts();
    final mm = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final ch in [
      'xyz.luan/audioplayers',
      'xyz.luan/audioplayers.global',
      'xyz.luan/audioplayers.global/events',
    ]) {
      mm.setMockMethodCallHandler(MethodChannel(ch), (_) async => null);
    }
    await initFakeSupabase();
    await signInFake('me', metadata: {'full_name': 'Tanatswa Mikuwa'});
    setFakeSupabaseHandler((req) {
      final path = req.url.path;
      final single = req.headers.entries.any((e) => e.key.toLowerCase() == 'accept' && e.value.contains('vnd.pgrst.object'));
      if (path.endsWith('/profiles')) {
        final id = req.url.queryParameters['id'];
        if (single) {
          return _people.firstWhere(
            (p) => id != null && p['id'] == id.replaceFirst('eq.', ''),
            orElse: () => _people.first,
          );
        }
        if (id != null && id.startsWith('eq.')) {
          return _people.where((p) => p['id'] == id.substring(3)).toList();
        }
        return _people;
      }
      if (path.endsWith('/conversations')) {
        Map<String, Object?> dm(String id, String other, String name,
                String msg, int minsAgo, int unread) =>
            {
              'id': id,
              'participant_a_id': 'me',
              'participant_b_id': other,
              'participant_a_name': 'Tanatswa Mikuwa',
              'participant_b_name': name,
              'last_message': msg,
              'last_sender_id': unread > 0 ? other : 'me',
              'last_message_at': DateTime.now()
                  .subtract(Duration(minutes: minsAgo))
                  .toUtc()
                  .toIso8601String(),
              'unread_count': unread,
              'request_status': 'accepted',
              'participant_b': {'is_verified': other == 'u1'},
            };
        return [
          dm('c1', 'u1', 'Rudo Moyo', 'See you at choir practice tonight 🎶', 3, 2),
          {
            'id': 'g1',
            'is_group': true,
            'name': 'Glen View Pathfinders',
            'last_message': 'Camporee forms are due Friday',
            'last_sender_id': 'u2',
            'last_message_at': DateTime.now()
                .subtract(const Duration(minutes: 40))
                .toUtc()
                .toIso8601String(),
            'unread_count': 5,
          },
          dm('c2', 'u2', 'Tendai Chikwanha', '📷 Photo', 90, 0),
          dm('c3', 'u3', 'Nyasha Dube', 'Amen 🙏 praying for you', 300, 0),
          dm('c4', 'u4', 'Farai Mutasa', '🎙️ Voice note', 1500, 0),
          dm('c5', 'u5', 'Chipo Ndlovu', 'Thank you for the lesson study notes!', 3000, 0),
        ];
      }
      if (path.endsWith('/messages')) {
        var n = 0;
        Map<String, Object?> m(String from, String text, int minsAgo,
                {String type = 'text'}) =>
            {
              'id': '${++n}',
              'conversation_id': 'c1',
              'sender_id': from,
              'content': text,
              'message_type': type,
              'created_at': DateTime.now()
                  .subtract(Duration(minutes: minsAgo))
                  .toUtc()
                  .toIso8601String(),
              'sent_at': DateTime.now()
                  .subtract(Duration(minutes: minsAgo))
                  .toUtc()
                  .toIso8601String(),
              'read': true,
              'delivered_at': '2026-11-01T00:00:00Z',
            };
        return [
          m('u1', 'Morning! Are you coming to choir practice tonight?', 300),
          m('me', 'Yes, I will be there by 6', 290),
          m('me', 'Should I bring the new hymnals?', 289),
          m('u1', 'Please do. We are starting with hymn 100 — Great Is Thy Faithfulness', 280),
          m('u1', 'Also Pastor asked if you can lead the opening prayer', 279),
          m('me', 'Amen, happy to', 200),
          m('u1', 'See you at choir practice tonight', 3),
        ].reversed.toList();
      }
      if (path.endsWith('/rpc/my_friends')) {
        return [
          for (final p in _people.take(2))
            {
              'friend_id': p['id'],
              'full_name': p['full_name'],
              'profile_photo_url': null,
              'church_name': (p['churches'] as Map)['name'],
            },
        ];
      }
      if (path.contains('/rpc/')) return [];
      return single ? null : [];
    });
  });

  for (final dark in [true, false]) {
    final tag = dark ? 'dark' : 'light';
    testWidgets('mini profile $tag', (t) async {
      await pumpShot(t, const _Opener(), dark: dark);
      await saveShot(t, 'mini_profile_$tag');
    });
  }

  testWidgets('new chat', (t) async {
    await pumpShot(t, const NewChatScreen());
    await saveShot(t, 'new_chat');
  });

  testWidgets('find people', (t) async {
    await pumpShot(t, const NewChatScreen(startInFindPeople: true));
    await saveShot(t, 'find_people');
  });

  testWidgets('new chat light', (t) async {
    await pumpShot(t, const NewChatScreen(), dark: false);
    await saveShot(t, 'new_chat_light');
  });

  testWidgets('create group', (t) async {
    await pumpShot(t, const CreateGroupScreen());
    await saveShot(t, 'create_group');
  });

  testWidgets('chat', (t) async {
    await pumpShot(
      t,
      ChatScreen(
        conversationId: 'c1',
        initialConversation: Conversation(
          id: 'c1',
          otherUserId: 'u1',
          otherUserName: 'Rudo Moyo',
          lastMessage: '',
          lastMessageAt: DateTime.now(),
          unreadCount: 0,
          requestStatus: 'accepted',
        ),
      ),
    );
    await saveShot(t, 'chat');
  });

  testWidgets('inbox', (t) async {
    await pumpShot(t, const ConversationsScreen());
    await saveShot(t, 'inbox');
  });
}
