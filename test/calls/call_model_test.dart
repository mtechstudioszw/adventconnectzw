// Guards the wire models against the two bugs that cost real money and
// real trust:
//
//   1. BILLING RINGING TIME. `elapsed` is measured from connected_at, so
//      a call nobody answered is zero seconds long. Anything that starts
//      the clock at started_at charges members for a phone that rang.
//
//   2. A PEER CONNECTION OUTLIVING ITS PARTICIPANT. `peerIdsFor` is the
//      list the mesh is driven from. If it ever includes somebody who is
//      merely invited (no media stack yet) or who has left (torn down),
//      the mesh holds a connection to a person who is not in the room —
//      which is how a "ghost" stays audible after hanging up.
//
// Plus the ordinary forward-compatibility rule: the server can add
// fields at any time, and an old client must keep parsing. Every fixture
// here is shaped exactly like what `call_snapshot`, `call_history` and
// `call_my_usage` return (database/patch_261_calls_rpcs.sql).
//
// Pure Dart. No bindings, no Supabase.

import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/models/call_model.dart';

void main() {
  // ---------------------------------------------------------------
  // Fixtures, shaped exactly like call_snapshot's jsonb_build_object.
  // ---------------------------------------------------------------
  Map<String, dynamic> participant({
    required String userId,
    required String status,
    String name = 'Member',
    String role = 'callee',
    bool muted = false,
    String? joinedAt,
    String? photoUrl,
  }) => <String, dynamic>{
    'user_id': userId,
    'role': role,
    'status': status,
    'muted': muted,
    'joined_at': joinedAt,
    'name': name,
    'photo_url': photoUrl,
  };

  /// A group call in progress: two other people in the room, one still
  /// being rung, one who never picked up, one who has left.
  Map<String, dynamic> snapshot({
    String kind = 'group',
    String status = 'active',
    String? connectedAt = '2026-08-24T10:00:07Z',
    String? endedAt,
    String? roomToken = 'a3f1c9de-0000-4000-8000-1234567890ab',
    String myStatus = 'joined',
    Object? endReason,
  }) => <String, dynamic>{
    'id': '11111111-2222-4333-8444-555555555555',
    'kind': kind,
    'status': status,
    'end_reason': endReason,
    'conversation_id': '99999999-8888-4777-8666-555555555555',
    'created_by': 'alice',
    'started_at': '2026-08-24T10:00:00Z',
    'connected_at': connectedAt,
    'ended_at': endedAt,
    'ring_expires_at': '2026-08-24T10:00:45Z',
    'hard_expires_at': '2026-08-24T11:30:00Z',
    'max_participants': 5,
    'my_status': myStatus,
    'room_token': roomToken,
    'participants': [
      participant(
        userId: 'alice',
        role: 'caller',
        name: 'Alice Moyo',
        status: 'joined',
        joinedAt: '2026-08-24T10:00:00Z',
        photoUrl: 'https://example.test/a.jpg',
      ),
      participant(
        userId: 'bob',
        name: 'Bob Ncube',
        status: 'joined',
        muted: true,
        joinedAt: '2026-08-24T10:00:07Z',
      ),
      participant(
        userId: 'me',
        name: 'Tendai',
        status: 'joined',
        joinedAt: '2026-08-24T10:00:09Z',
      ),
      participant(userId: 'carol', name: 'Carol', status: 'invited'),
      participant(userId: 'dave', name: 'Dave', status: 'ringing'),
      participant(userId: 'erin', name: 'Erin', status: 'left'),
    ],
  };

  group('CallSession.fromJson reads what the server actually sends', () {
    test('a full snapshot parses field for field', () {
      final s = CallSession.fromJson(snapshot());

      expect(s.id, '11111111-2222-4333-8444-555555555555');
      expect(s.isGroup, isTrue, reason: "kind == 'group'");
      expect(s.status, CallStatus.active);
      expect(s.myStatus, ParticipantStatus.joined);
      expect(s.roomToken, 'a3f1c9de-0000-4000-8000-1234567890ab');
      expect(s.createdBy, 'alice');
      expect(s.conversationId, '99999999-8888-4777-8666-555555555555');
      expect(s.maxParticipants, 5);
      expect(s.participants, hasLength(6));
      expect(s.startedAt, DateTime.utc(2026, 8, 24, 10));
      expect(s.startedAt.isUtc, isTrue);
      expect(s.connectedAt, DateTime.utc(2026, 8, 24, 10, 0, 7));
      expect(s.endedAt, isNull);
      expect(s.ringExpiresAt, DateTime.utc(2026, 8, 24, 10, 0, 45));
      expect(s.hardExpiresAt, DateTime.utc(2026, 8, 24, 11, 30));
      expect(s.isOver, isFalse);
    });

    test('a direct call is not a group call', () {
      final s = CallSession.fromJson(snapshot(kind: 'direct'));
      expect(s.isGroup, isFalse);
    });

    test('an unknown kind is not silently treated as a group', () {
      final s = CallSession.fromJson(snapshot(kind: 'conference'));
      expect(s.isGroup, isFalse);
    });

    test('an ended call reports isOver and its reason', () {
      final s = CallSession.fromJson(snapshot(
        status: 'ended',
        endedAt: '2026-08-24T10:05:07Z',
        endReason: 'completed',
        roomToken: null,
      ));
      expect(s.isOver, isTrue);
      expect(s.status, CallStatus.ended);
      expect(s.endReason, CallEndReason.completed);
      expect(
        s.roomToken,
        isNull,
        reason: 'the server withholds the signalling capability once the '
            'call is over',
      );
    });

    test('participants carry name, photo, role and muted', () {
      final s = CallSession.fromJson(snapshot());
      final alice = s.participants.firstWhere((p) => p.userId == 'alice');
      final bob = s.participants.firstWhere((p) => p.userId == 'bob');

      expect(alice.name, 'Alice Moyo');
      expect(alice.photoUrl, 'https://example.test/a.jpg');
      expect(alice.isCaller, isTrue);
      expect(alice.muted, isFalse);
      expect(bob.isCaller, isFalse);
      expect(bob.muted, isTrue);
      expect(bob.joinedAt, DateTime.utc(2026, 8, 24, 10, 0, 7));
    });

    test('a blank or missing name falls back to Member, never to empty', () {
      final s = CallSession.fromJson(<String, dynamic>{
        'participants': [
          participant(userId: 'x', status: 'joined', name: '   '),
          <String, dynamic>{'user_id': 'y', 'status': 'joined'},
        ],
      });
      expect(s.participants[0].name, 'Member');
      expect(s.participants[1].name, 'Member');
    });
  });

  group('elapsed never bills ringing time', () {
    test('elapsed is zero while the phone is still ringing', () {
      // connected_at null is the ONLY thing that decides this — not the
      // status, not started_at.
      final s = CallSession.fromJson(
        snapshot(status: 'ringing', connectedAt: null),
      );
      expect(s.connectedAt, isNull);
      expect(s.elapsed, Duration.zero);
    });

    test('a call that rang out and ended is still zero seconds long', () {
      final s = CallSession.fromJson(snapshot(
        status: 'ended',
        connectedAt: null,
        endedAt: '2026-08-24T10:00:45Z',
        endReason: 'missed',
      ));
      expect(
        s.elapsed,
        Duration.zero,
        reason: '45 seconds of ringing must not be charged as call time',
      );
    });

    test('elapsed is connected_at -> ended_at when both are present', () {
      final s = CallSession.fromJson(snapshot(
        status: 'ended',
        connectedAt: '2026-08-24T10:00:07Z',
        endedAt: '2026-08-24T10:05:07Z',
      ));
      expect(s.elapsed, const Duration(minutes: 5));
    });

    test('elapsed excludes the 7 seconds spent ringing', () {
      // started_at 10:00:00, connected_at 10:00:07, ended 10:05:07.
      // Wall time is 5m07s; billable time is 5m00s.
      final s = CallSession.fromJson(snapshot(
        status: 'ended',
        endedAt: '2026-08-24T10:05:07Z',
      ));
      expect(s.elapsed, const Duration(minutes: 5));
      expect(s.endedAt!.difference(s.startedAt), const Duration(seconds: 307));
    });

    test('elapsed is never negative when the clocks disagree', () {
      // A device with a skewed clock, or a server row written out of
      // order, must not produce a negative duration on the timer.
      final s = CallSession.fromJson(snapshot(
        status: 'ended',
        connectedAt: '2026-08-24T10:05:00Z',
        endedAt: '2026-08-24T10:00:00Z',
      ));
      expect(s.elapsed, Duration.zero);
      expect(s.elapsed.isNegative, isFalse);
    });

    test('a live call measures against now', () {
      final connected = DateTime.now().toUtc().subtract(
        const Duration(seconds: 90),
      );
      final s = CallSession.fromJson(<String, dynamic>{
        'status': 'active',
        'connected_at': connected.toIso8601String(),
      });
      expect(s.elapsed.inSeconds, greaterThanOrEqualTo(89));
      expect(s.elapsed.inSeconds, lessThan(120));
    });
  });

  group('peerIdsFor holds media only to people actually in the room', () {
    test('only joined participants, and never me', () {
      final s = CallSession.fromJson(snapshot());
      final peers = s.peerIdsFor('me');

      expect(peers, unorderedEquals(<String>['alice', 'bob']));
      expect(peers, isNot(contains('me')), reason: 'no loopback peer');
      expect(
        peers,
        isNot(contains('carol')),
        reason: 'an invited member has no media stack to negotiate with',
      );
      expect(
        peers,
        isNot(contains('dave')),
        reason: 'a ringing member has not answered',
      );
      expect(
        peers,
        isNot(contains('erin')),
        reason: 'a peer connection must not outlive the participant',
      );
    });

    test('a participant who leaves drops out of the peer list', () {
      final before = CallSession.fromJson(snapshot());
      expect(before.peerIdsFor('me'), contains('bob'));

      final after = snapshot();
      (after['participants'] as List)[1]['status'] = 'left';
      expect(CallSession.fromJson(after).peerIdsFor('me'), isNot(contains('bob')));
    });

    test('every terminal participant status is excluded', () {
      for (final gone in const [
        'left',
        'rejected',
        'missed',
        'busy',
        'failed',
        'removed',
        'something_new_from_the_server',
      ]) {
        final json = snapshot();
        (json['participants'] as List)[0]['status'] = gone;
        expect(
          CallSession.fromJson(json).peerIdsFor('me'),
          isNot(contains('alice')),
          reason: 'status "$gone" still got a peer connection',
        );
      }
    });

    test('a 1:1 call has exactly one peer', () {
      final s = CallSession.fromJson(<String, dynamic>{
        'kind': 'direct',
        'status': 'active',
        'participants': [
          participant(userId: 'alice', role: 'caller', status: 'joined'),
          participant(userId: 'me', status: 'joined'),
        ],
      });
      expect(s.peerIdsFor('me'), <String>['alice']);
    });

    test('peerIdsFor is empty while the only other person is ringing', () {
      final solo = CallSession.fromJson(<String, dynamic>{
        'participants': [
          participant(userId: 'me', role: 'caller', status: 'joined'),
          participant(userId: 'bob', status: 'ringing'),
        ],
      });
      expect(solo.peerIdsFor('me'), isEmpty);
    });

    test('a viewer who is not in the call sees every joined member', () {
      final s = CallSession.fromJson(snapshot());
      expect(s.peerIdsFor('nobody-by-that-name'), hasLength(3));
    });
  });

  group('roster helpers', () {
    test('othersFor excludes me and nobody else', () {
      final s = CallSession.fromJson(snapshot());
      final others = s.othersFor('me');
      expect(others, hasLength(5));
      expect(others.map((p) => p.userId), isNot(contains('me')));
    });

    test('othersFor with an unknown id returns everyone', () {
      final s = CallSession.fromJson(snapshot());
      expect(s.othersFor('not-in-this-call'), hasLength(6));
    });

    test('active is the joined participants', () {
      final s = CallSession.fromJson(snapshot());
      expect(
        s.active.map((p) => p.userId),
        unorderedEquals(<String>['alice', 'bob', 'me']),
      );
    });

    test('pending is invited + ringing, the ones shown as "Ringing…"', () {
      final s = CallSession.fromJson(snapshot());
      expect(
        s.pending.map((p) => p.userId),
        unorderedEquals(<String>['carol', 'dave']),
      );
    });

    test('caller is the role, not the first row', () {
      final s = CallSession.fromJson(snapshot());
      expect(s.caller?.userId, 'alice');

      final reordered = snapshot();
      final list = reordered['participants'] as List;
      final head = list.removeAt(0);
      list.add(head); // caller last
      expect(CallSession.fromJson(reordered).caller?.userId, 'alice');
    });

    test('caller is null when the server sent no roles', () {
      final s = CallSession.fromJson(<String, dynamic>{
        'participants': [
          <String, dynamic>{'user_id': 'a', 'status': 'joined'},
        ],
      });
      expect(s.caller, isNull);
    });

    test('isActive / isPending / isGone partition every status', () {
      const all = ParticipantStatus.values;
      for (final status in all) {
        final p = CallParticipant(
          userId: 'u',
          name: 'n',
          status: status,
          isCaller: false,
        );
        final flags = [p.isActive, p.isPending, p.isGone];
        expect(
          flags.where((f) => f).length,
          1,
          reason: '$status is in ${flags.where((f) => f).length} buckets',
        );
      }
    });
  });

  group('an old client survives whatever the server sends', () {
    test('an empty object does not throw', () {
      final s = CallSession.fromJson(<String, dynamic>{});
      expect(s.id, '');
      expect(s.isGroup, isFalse);
      expect(s.status, CallStatus.unknown);
      expect(s.myStatus, ParticipantStatus.unknown);
      expect(s.endReason, CallEndReason.unknown);
      expect(s.roomToken, isNull);
      expect(s.connectedAt, isNull);
      expect(s.endedAt, isNull);
      expect(s.participants, isEmpty);
      expect(s.maxParticipants, 2, reason: 'a direct call is the safe default');
      expect(s.elapsed, Duration.zero);
      expect(s.startedAt.isUtc, isTrue);
    });

    test('explicit nulls everywhere do not throw', () {
      final s = CallSession.fromJson(<String, dynamic>{
        'id': null,
        'kind': null,
        'status': null,
        'end_reason': null,
        'conversation_id': null,
        'created_by': null,
        'started_at': null,
        'connected_at': null,
        'ended_at': null,
        'ring_expires_at': null,
        'hard_expires_at': null,
        'max_participants': null,
        'my_status': null,
        'room_token': null,
        'participants': null,
      });
      expect(s.participants, isEmpty);
      expect(s.conversationId, isNull);
      expect(s.elapsed, Duration.zero);
    });

    test('a participants field that is not a list is ignored, not fatal', () {
      final s = CallSession.fromJson(<String, dynamic>{'participants': 'oops'});
      expect(s.participants, isEmpty);
    });

    test('junk entries inside participants are skipped', () {
      final s = CallSession.fromJson(<String, dynamic>{
        'participants': [
          null,
          'string',
          42,
          <String, dynamic>{'user_id': 'real', 'status': 'joined'},
        ],
      });
      expect(s.participants, hasLength(1));
      expect(s.participants.single.userId, 'real');
    });

    test('unknown enum values degrade instead of throwing', () {
      final s = CallSession.fromJson(<String, dynamic>{
        'status': 'quantum',
        'my_status': 'levitating',
        'end_reason': 'act_of_god',
      });
      expect(s.status, CallStatus.unknown);
      expect(s.myStatus, ParticipantStatus.unknown);
      expect(s.endReason, CallEndReason.unknown);
    });

    test('fields a newer server adds are ignored', () {
      final json = snapshot()
        ..['recording_url'] = 'https://example.test/rec.ogg'
        ..['sfu_region'] = 'af-south-1';
      final s = CallSession.fromJson(json);
      expect(s.id, isNotEmpty);
      expect(s.participants, hasLength(6));
    });

    test('an unparseable timestamp becomes null, not a crash', () {
      final s = CallSession.fromJson(<String, dynamic>{
        'started_at': 'yesterday-ish',
        'connected_at': 'not a date',
        'ended_at': '',
      });
      expect(s.connectedAt, isNull);
      expect(s.endedAt, isNull);
      expect(s.elapsed, Duration.zero);
      expect(s.startedAt.isUtc, isTrue); // fell back to now
    });

    test('a numeric id is stringified rather than cast-crashing', () {
      final s = CallSession.fromJson(<String, dynamic>{'id': 12345});
      expect(s.id, '12345');
    });

    test('every documented end reason maps to its enum', () {
      const wire = <String, CallEndReason>{
        'completed': CallEndReason.completed,
        'rejected': CallEndReason.rejected,
        'cancelled': CallEndReason.cancelled,
        'missed': CallEndReason.missed,
        'busy': CallEndReason.busy,
        'unreachable': CallEndReason.unreachable,
        'failed': CallEndReason.failed,
        'max_duration': CallEndReason.maxDuration,
        'quota': CallEndReason.quota,
        'stale': CallEndReason.stale,
        'admin': CallEndReason.admin,
      };
      wire.forEach((raw, expected) {
        final s = CallSession.fromJson(<String, dynamic>{'end_reason': raw});
        expect(s.endReason, expected, reason: raw);
      });
    });

    test('every documented participant status maps to its enum', () {
      const wire = <String, ParticipantStatus>{
        'invited': ParticipantStatus.invited,
        'ringing': ParticipantStatus.ringing,
        'joined': ParticipantStatus.joined,
        'left': ParticipantStatus.left,
        'rejected': ParticipantStatus.rejected,
        'missed': ParticipantStatus.missed,
        'busy': ParticipantStatus.busy,
        'failed': ParticipantStatus.failed,
        'removed': ParticipantStatus.removed,
      };
      wire.forEach((raw, expected) {
        final s = CallSession.fromJson(<String, dynamic>{'my_status': raw});
        expect(s.myStatus, expected, reason: raw);
      });
    });
  });

  // -----------------------------------------------------------------
  // History
  // -----------------------------------------------------------------
  group('CallHistoryEntry: a call I placed is never a "missed call"', () {
    Map<String, dynamic> row({
      required bool outgoing,
      String? connectedAt,
      String myStatus = 'missed',
      String endReason = 'missed',
      String kind = 'direct',
      int duration = 0,
    }) => <String, dynamic>{
      'id': 'c-1',
      'kind': kind,
      'status': 'ended',
      'end_reason': endReason,
      'conversation_id': null,
      'created_by': outgoing ? 'me' : 'alice',
      'started_at': '2026-08-24T09:00:00Z',
      'connected_at': connectedAt,
      'ended_at': '2026-08-24T09:00:45Z',
      'duration_seconds': duration,
      'outgoing': outgoing,
      'my_status': myStatus,
      'my_seconds': duration,
      'group_name': null,
      'others': [
        <String, dynamic>{
          'user_id': 'alice',
          'status': 'joined',
          'name': 'Alice Moyo',
          'photo_url': null,
        },
      ],
    };

    test('an incoming call nobody answered IS missed', () {
      final e = CallHistoryEntry.fromJson(row(outgoing: false));
      expect(e.outgoing, isFalse);
      expect(e.answered, isFalse);
      expect(e.missed, isTrue, reason: 'this is the red row that needs action');
    });

    test('an OUTGOING call nobody answered is NOT missed', () {
      // Colouring my own unanswered call red puts a permanent alarm on
      // my history for something only I did.
      final e = CallHistoryEntry.fromJson(row(outgoing: true));
      expect(e.outgoing, isTrue);
      expect(e.answered, isFalse);
      expect(e.missed, isFalse);
    });

    test('an incoming call I answered is not missed', () {
      final e = CallHistoryEntry.fromJson(row(
        outgoing: false,
        connectedAt: '2026-08-24T09:00:05Z',
        myStatus: 'joined',
        endReason: 'completed',
        duration: 40,
      ));
      expect(e.answered, isTrue);
      expect(e.missed, isFalse);
    });

    test('an incoming call I declined is declined, not missed', () {
      final e = CallHistoryEntry.fromJson(
        row(outgoing: false, myStatus: 'rejected', endReason: 'rejected'),
      );
      expect(e.declined, isTrue);
      expect(e.missed, isFalse);
    });

    test('an outgoing call they declined is declined', () {
      final e = CallHistoryEntry.fromJson(
        row(outgoing: true, myStatus: 'joined', endReason: 'rejected'),
      );
      expect(e.declined, isTrue);
      expect(e.missed, isFalse);
    });

    test('a cancelled or stale incoming call still reads as missed', () {
      for (final reason in const ['cancelled', 'stale']) {
        final e = CallHistoryEntry.fromJson(
          row(outgoing: false, myStatus: 'left', endReason: reason),
        );
        expect(e.missed, isTrue, reason: reason);
      }
    });

    test('answered follows connected_at and nothing else', () {
      expect(
        CallHistoryEntry.fromJson(row(outgoing: false)).answered,
        isFalse,
      );
      expect(
        CallHistoryEntry.fromJson(
          row(outgoing: false, connectedAt: '2026-08-24T09:00:05Z'),
        ).answered,
        isTrue,
      );
      // Even a "completed" call that never connected did not happen.
      expect(
        CallHistoryEntry.fromJson(
          row(outgoing: true, myStatus: 'joined', endReason: 'completed'),
        ).answered,
        isFalse,
      );
    });

    test('title and peer for a 1:1 row', () {
      final e = CallHistoryEntry.fromJson(row(outgoing: true));
      expect(e.title, 'Alice Moyo');
      expect(e.peer?.userId, 'alice');
      expect(e.isGroup, isFalse);
    });

    test('a group row is titled by the group, and has no single peer', () {
      final json = row(outgoing: true, kind: 'group')
        ..['group_name'] = 'Youth Choir'
        ..['others'] = [
          <String, dynamic>{'user_id': 'a', 'status': 'joined', 'name': 'A'},
          <String, dynamic>{'user_id': 'b', 'status': 'joined', 'name': 'B'},
        ];
      final e = CallHistoryEntry.fromJson(json);
      expect(e.isGroup, isTrue);
      expect(e.title, 'Youth Choir');
      expect(e.peer, isNull);
    });

    test('a group row with no name still has a title', () {
      final e = CallHistoryEntry.fromJson(row(outgoing: true, kind: 'group'));
      expect(e.title, isNotEmpty);
    });

    test('a row with nobody else in it still has a title', () {
      final json = row(outgoing: true)..['others'] = null;
      final e = CallHistoryEntry.fromJson(json);
      expect(e.others, isEmpty);
      expect(e.title, isNotEmpty);
      expect(e.peer, isNull);
    });

    test('an empty history row does not throw', () {
      final e = CallHistoryEntry.fromJson(<String, dynamic>{});
      expect(e.id, '');
      expect(e.outgoing, isFalse);
      expect(e.durationSeconds, 0);
      expect(e.answered, isFalse);
      expect(e.missed, isFalse, reason: 'unknown status is not an alarm');
      expect(e.others, isEmpty);
    });

    test('duration_seconds is read as an int even when sent as a double', () {
      final json = row(outgoing: true)..['duration_seconds'] = 42.0;
      expect(CallHistoryEntry.fromJson(json).durationSeconds, 42);
    });
  });

  // -----------------------------------------------------------------
  // Usage
  // -----------------------------------------------------------------
  group('CallUsage never divides by zero and never over-reports', () {
    test('a fresh member is at zero', () {
      const u = CallUsage.empty;
      expect(u.dailyFraction, 0.0);
      expect(u.nearDailyLimit, isFalse);
      expect(u.dailyExhausted, isFalse);
      expect(u.monthlyExhausted, isFalse);
    });

    test('dailyFraction is the plain ratio', () {
      const u = CallUsage(
        todaySeconds: 3600,
        monthSeconds: 3600,
        dailyLimitSeconds: 7200,
        monthlyLimitSeconds: 90000,
        premium: false,
      );
      expect(u.dailyFraction, closeTo(0.5, 1e-9));
    });

    test('dailyFraction clamps to 1.0 when the member ran over', () {
      // Seconds are settled server-side after the fact, so today can
      // legitimately exceed the ceiling. A progress bar at 1.4 draws
      // outside its track.
      const u = CallUsage(
        todaySeconds: 10000,
        monthSeconds: 10000,
        dailyLimitSeconds: 7200,
        monthlyLimitSeconds: 90000,
        premium: false,
      );
      expect(u.dailyFraction, 1.0);
      expect(u.dailyExhausted, isTrue);
    });

    test('dailyFraction never goes below 0', () {
      const u = CallUsage(
        todaySeconds: -60,
        monthSeconds: 0,
        dailyLimitSeconds: 7200,
        monthlyLimitSeconds: 90000,
        premium: false,
      );
      expect(u.dailyFraction, 0.0);
      expect(u.dailyFraction, greaterThanOrEqualTo(0.0));
    });

    test('nearDailyLimit bites at exactly 0.8, not at 1.0', () {
      const at = CallUsage(
        todaySeconds: 5760, // 80% of 7200
        monthSeconds: 5760,
        dailyLimitSeconds: 7200,
        monthlyLimitSeconds: 90000,
        premium: false,
      );
      const justBelow = CallUsage(
        todaySeconds: 5759,
        monthSeconds: 5759,
        dailyLimitSeconds: 7200,
        monthlyLimitSeconds: 90000,
        premium: false,
      );
      expect(at.dailyFraction, closeTo(0.8, 1e-9));
      expect(at.nearDailyLimit, isTrue, reason: 'the warning must fire AT 0.8');
      expect(justBelow.nearDailyLimit, isFalse);
      expect(at.dailyExhausted, isFalse, reason: '80% is a warning, not a stop');
    });

    test('a zero daily limit does not divide by zero', () {
      const u = CallUsage(
        todaySeconds: 500,
        monthSeconds: 500,
        dailyLimitSeconds: 0,
        monthlyLimitSeconds: 0,
        premium: false,
      );
      expect(u.dailyFraction, 0.0);
      expect(u.dailyFraction.isNaN, isFalse);
      expect(u.dailyFraction.isInfinite, isFalse);
      expect(u.nearDailyLimit, isFalse);
    });

    test('a negative daily limit is treated as no ratio at all', () {
      const u = CallUsage(
        todaySeconds: 500,
        monthSeconds: 500,
        dailyLimitSeconds: -1,
        monthlyLimitSeconds: 90000,
        premium: false,
      );
      expect(u.dailyFraction, 0.0);
    });

    test('exhausted is >= not >', () {
      const u = CallUsage(
        todaySeconds: 7200,
        monthSeconds: 90000,
        dailyLimitSeconds: 7200,
        monthlyLimitSeconds: 90000,
        premium: false,
      );
      expect(u.dailyExhausted, isTrue);
      expect(u.monthlyExhausted, isTrue);
    });

    test('call_my_usage json parses, including premium ceilings', () {
      final u = CallUsage.fromJson(<String, dynamic>{
        'today_seconds': 1200,
        'month_seconds': 48000,
        'daily_limit_seconds': 21600, // 360 premium minutes
        'monthly_limit_seconds': 270000,
        'premium': true,
      });
      expect(u.todaySeconds, 1200);
      expect(u.monthSeconds, 48000);
      expect(u.dailyLimitSeconds, 21600);
      expect(u.monthlyLimitSeconds, 270000);
      expect(u.premium, isTrue);
    });

    test('missing usage fields fall back to the free ceilings', () {
      final u = CallUsage.fromJson(<String, dynamic>{});
      expect(u.todaySeconds, 0);
      expect(u.monthSeconds, 0);
      expect(u.dailyLimitSeconds, 7200, reason: '120 free minutes');
      expect(u.monthlyLimitSeconds, 90000, reason: '1500 free minutes');
      expect(u.premium, isFalse);
      expect(u.dailyFraction, 0.0);
    });

    test('premium is only true when the server says exactly true', () {
      for (final raw in <Object?>[null, false, 'true', 1]) {
        final u = CallUsage.fromJson(<String, dynamic>{'premium': raw});
        expect(u.premium, isFalse, reason: 'premium: $raw');
      }
    });
  });

  // -----------------------------------------------------------------
  // Failures
  // -----------------------------------------------------------------
  group('CallFailure sorts refusals into the right remedy', () {
    test('transient codes are the ones waiting fixes', () {
      for (final code in const [
        'RATE_LIMITED',
        'RECIPIENT_BUSY',
        'ALREADY_IN_CALL',
        'CALL_FULL',
      ]) {
        final f = CallFailure(code, 'Try again in a moment.');
        expect(f.isTransient, isTrue, reason: code);
        expect(f.isQuota, isFalse, reason: '$code is not a quota problem');
      }
    });

    test('quota codes are not transient — the remedy is different', () {
      for (final code in const ['QUOTA_EXCEEDED', 'QUOTA_REACHED']) {
        final f = CallFailure(code, 'You have used your calling time.');
        expect(f.isQuota, isTrue, reason: code);
        expect(
          f.isTransient,
          isFalse,
          reason: '$code must not offer "try again" — the fix is tomorrow, '
              'or Premium',
        );
      }
    });

    test('permanent refusals are neither', () {
      for (final code in const [
        'NOT_ALLOWED',
        'NOT_ALLOWED_GROUP',
        'NOT_A_PARTICIPANT',
        'CALL_OVER',
        'CALLS_DISABLED',
        'ACCOUNT_INACTIVE',
        'NOT_AUTHENTICATED',
        'INVALID_STATE',
        'SOMETHING_NEW',
        '',
      ]) {
        final f = CallFailure(code, 'No.');
        expect(f.isTransient, isFalse, reason: code);
        expect(f.isQuota, isFalse, reason: code);
      }
    });

    test('the code is matched exactly, not by prefix or case', () {
      expect(const CallFailure('rate_limited', 'x').isTransient, isFalse);
      expect(const CallFailure('RATE_LIMITED_HARD', 'x').isTransient, isFalse);
      expect(const CallFailure('QUOTA', 'x').isQuota, isFalse);
    });

    test('a failure is an Exception and prints both parts', () {
      const f = CallFailure('RATE_LIMITED', 'Slow down a moment.');
      expect(f, isA<Exception>());
      expect(f.toString(), contains('RATE_LIMITED'));
      expect(f.toString(), contains('Slow down a moment.'));
    });
  });
}
