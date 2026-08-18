import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/screens/messaging/chat_screen.dart';

/// The composer gate must agree with the production trigger
/// `enforce_non_friend_message_cap`, verified against the live database
/// on 18 Aug 2026. Its branches, in order:
///
///   1. the other participant has sent anything  -> allow, unconditionally
///   2. who_can_message = 'nobody'               -> refuse, friends included
///   3. are_friends()                            -> allow
///   4. who_can_message = 'friends'              -> refuse
///   5. 'everyone' and sender count >= 1         -> refuse
///
/// Drift here is silent and only shows up as a member being blocked from
/// a message the server would have taken, or being invited to write one
/// it will bounce. These tests are the pin.
void main() {
  ComposerGate? gate({
    String otherName = 'Tendai',
    bool theyHaveSpoken = false,
    bool areFriends = false,
    bool requestPending = false,
    String whoCanMessage = 'everyone',
    int myMessageCount = 0,
  }) => composerGateFor(
    otherName: otherName,
    theyHaveSpoken: theyHaveSpoken,
    areFriends: areFriends,
    requestPending: requestPending,
    whoCanMessage: whoCanMessage,
    myMessageCount: myMessageCount,
  );

  group('a reply lifts every gate (trigger branch 1)', () {
    test('outranks the one-message cap', () {
      expect(gate(theyHaveSpoken: true, myMessageCount: 5), isNull);
    });

    test('outranks friends-only', () {
      expect(
        gate(theyHaveSpoken: true, whoCanMessage: 'friends'),
        isNull,
      );
    });

    test('outranks nobody — the trigger checks the reply first, and '
        're-gating a thread already spoken in would break it', () {
      expect(gate(theyHaveSpoken: true, whoCanMessage: 'nobody'), isNull);
    });
  });

  group('who_can_message = nobody (branch 2)', () {
    test('blocks a stranger', () {
      expect(gate(whoCanMessage: 'nobody'), isNotNull);
    });

    test('blocks a FRIEND too — the only setting that does', () {
      expect(gate(whoCanMessage: 'nobody', areFriends: true), isNotNull);
    });

    test('offers no Add friend button, because it would not help', () {
      expect(gate(whoCanMessage: 'nobody')!.showAddFriend, isFalse);
    });
  });

  group('friends (branch 3)', () {
    test('chat freely on the default setting', () {
      expect(gate(areFriends: true, myMessageCount: 40), isNull);
    });

    test('friends beat the friends-only setting', () {
      expect(
        gate(areFriends: true, whoCanMessage: 'friends', myMessageCount: 9),
        isNull,
      );
    });
  });

  group('who_can_message = friends (branch 4)', () {
    test('blocks a non-friend outright — before the first message, not '
        'after it', () {
      expect(gate(whoCanMessage: 'friends', myMessageCount: 0), isNotNull);
    });

    test('offers Add friend, which is the action that clears it', () {
      expect(gate(whoCanMessage: 'friends')!.showAddFriend, isTrue);
    });

    test('stops offering Add friend once one is pending', () {
      expect(
        gate(whoCanMessage: 'friends', requestPending: true)!.showAddFriend,
        isFalse,
      );
    });
  });

  group('everyone: exactly one message (branch 5)', () {
    test('the first message is allowed', () {
      expect(gate(myMessageCount: 0), isNull);
    });

    test('the second is not — the cap is 1, not the 3 patch_118 shipped', () {
      expect(gate(myMessageCount: 1), isNotNull);
    });

    test('wording changes once a request is pending', () {
      final asked = gate(myMessageCount: 1, requestPending: true)!;
      final notAsked = gate(myMessageCount: 1)!;
      expect(asked.body, isNot(equals(notAsked.body)));
      expect(asked.showAddFriend, isFalse);
      expect(notAsked.showAddFriend, isTrue);
    });
  });

  group('copy', () {
    test('no gate claims the member can keep chatting — that contradiction '
        'is the bug this replaced', () {
      final bodies = [
        gate(myMessageCount: 1)!.body,
        gate(myMessageCount: 1, requestPending: true)!.body,
        gate(whoCanMessage: 'friends')!.body,
        gate(whoCanMessage: 'nobody')!.body,
      ];
      for (final body in bodies) {
        expect(body.toLowerCase(), isNot(contains('you can still')));
        expect(body.toLowerCase(), isNot(contains('keep chatting')));
      }
    });

    test('falls back to a usable noun when the name is blank', () {
      expect(
        gate(otherName: '   ', myMessageCount: 1)!.title,
        contains('This person'),
      );
    });

    test('names the person when there is a name', () {
      expect(gate(myMessageCount: 1)!.title, contains('Tendai'));
    });
  });
}
