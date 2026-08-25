// Guards the call state machine against LATE EVENTS.
//
// The class of bug this file exists to prevent: a call that has already
// finished being dragged back to life by something that arrived after
// the fact. Signalling and media are both asynchronous and both can
// deliver seconds late — an ICE state change from a peer connection that
// is already being torn down, a heartbeat reply for a call the member
// hung up, a CallKit `accept` for a call that rang out in a pocket.
// Every one of those calls into the state machine, and every one of them
// must bounce off a terminal phase.
//
// The transition table is the single place that rule lives, so this
// file tests the TABLE rather than any one call site. Everything is
// driven off `CallPhase.values`: a phase added later with no table row,
// or a terminal phase that quietly gains an escape hatch, fails here
// instead of in somebody's call.
//
// Pure Dart. No bindings, no Supabase, no WebRTC.

import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/services/calls/call_state.dart';

void main() {
  const terminals = <CallPhase>[
    CallPhase.ended,
    CallPhase.rejected,
    CallPhase.missed,
    CallPhase.failed,
    CallPhase.busy,
  ];

  /// Walks a path, asserting every step is a legal move.
  void walk(List<CallPhase> path) {
    for (var i = 0; i < path.length - 1; i++) {
      expect(
        canTransition(path[i], path[i + 1]),
        isTrue,
        reason:
            '${path[i].name} -> ${path[i + 1].name} is part of a normal call '
            'and must be allowed',
      );
    }
  }

  group('terminal states are absorbing', () {
    // The headline rule. Iterated, never hand-written: a new CallPhase
    // added to the enum is covered the moment it exists.
    for (final terminal in terminals) {
      test('a call that is ${terminal.name} can only leave via idle', () {
        for (final to in CallPhase.values) {
          if (to == CallPhase.idle) continue;
          if (to == terminal) continue; // re-entry, covered below
          expect(
            canTransition(terminal, to),
            isFalse,
            reason:
                'a delayed packet moved a ${terminal.name} call to ${to.name}',
          );
        }
      });

      test('${terminal.name} -> idle is the one way out', () {
        expect(canTransition(terminal, CallPhase.idle), isTrue);
      });
    }

    test('a call that has ended cannot become connected again', () {
      expect(canTransition(CallPhase.ended, CallPhase.connected), isFalse);
      expect(canTransition(CallPhase.ended, CallPhase.connecting), isFalse);
      expect(canTransition(CallPhase.ended, CallPhase.reconnecting), isFalse);
    });

    test('a declined call cannot become connected', () {
      expect(canTransition(CallPhase.rejected, CallPhase.connected), isFalse);
      expect(canTransition(CallPhase.rejected, CallPhase.ringing), isFalse);
    });

    test('a missed call cannot become connected by a late accept', () {
      expect(canTransition(CallPhase.missed, CallPhase.connected), isFalse);
      expect(canTransition(CallPhase.missed, CallPhase.connecting), isFalse);
    });

    test('a failed or busy call cannot be resurrected', () {
      expect(canTransition(CallPhase.failed, CallPhase.connected), isFalse);
      expect(canTransition(CallPhase.busy, CallPhase.connected), isFalse);
      expect(canTransition(CallPhase.busy, CallPhase.ringing), isFalse);
    });

    test('one terminal state cannot be overwritten by another', () {
      // "Ended" then a late "rejected" would rewrite the outcome the
      // member has already been shown.
      for (final a in terminals) {
        for (final b in terminals) {
          if (a == b) continue;
          expect(
            canTransition(a, b),
            isFalse,
            reason: '${a.name} was rewritten as ${b.name}',
          );
        }
      }
    });
  });

  group('re-entry is idempotent', () {
    test('every phase can transition to itself', () {
      // Duplicate events are normal: two ICE callbacks, a snapshot that
      // repeats what we already knew. Re-entering the same phase must be
      // a no-op, not a refusal the caller has to special-case.
      for (final phase in CallPhase.values) {
        expect(
          canTransition(phase, phase),
          isTrue,
          reason: '${phase.name} refused a duplicate of itself',
        );
      }
    });
  });

  group('the legal happy paths', () {
    test('outgoing: idle -> initiating -> ringing -> connecting -> connected',
        () {
      walk(const [
        CallPhase.idle,
        CallPhase.initiating,
        CallPhase.ringing,
        CallPhase.connecting,
        CallPhase.connected,
      ]);
    });

    test('incoming: idle -> incoming -> connecting -> connected', () {
      walk(const [
        CallPhase.idle,
        CallPhase.incoming,
        CallPhase.connecting,
        CallPhase.connected,
      ]);
    });

    test('a wobble is not a failure: connected -> reconnecting -> connected',
        () {
      walk(const [
        CallPhase.connected,
        CallPhase.reconnecting,
        CallPhase.connected,
      ]);
    });

    test('rejoining a group goes initiating -> connecting, skipping ringing',
        () {
      expect(canTransition(CallPhase.initiating, CallPhase.connecting), isTrue);
    });

    test('every live phase can reach a terminal one', () {
      // A phase with no way out is a screen a member can never leave.
      for (final phase in CallPhase.values) {
        if (phase == CallPhase.idle || phase.isTerminal) continue;
        final outs = kCallTransitions[phase] ?? const <CallPhase>{};
        expect(
          outs.any((p) => p.isTerminal),
          isTrue,
          reason: '${phase.name} has no terminal successor — it is a dead end',
        );
      }
    });
  });

  group('specific illegal moves are refused', () {
    test('a ringing call cannot jump backwards to initiating', () {
      expect(canTransition(CallPhase.ringing, CallPhase.initiating), isFalse);
    });

    test('an outgoing call cannot become an incoming one', () {
      expect(canTransition(CallPhase.initiating, CallPhase.incoming), isFalse);
      expect(canTransition(CallPhase.ringing, CallPhase.incoming), isFalse);
    });

    test('an incoming call cannot be marked busy by this device', () {
      // Busy is a statement about the OTHER end of an outgoing call.
      expect(canTransition(CallPhase.incoming, CallPhase.busy), isFalse);
      expect(canTransition(CallPhase.connecting, CallPhase.busy), isFalse);
      expect(canTransition(CallPhase.connected, CallPhase.busy), isFalse);
    });

    test('a connected call cannot go back to ringing', () {
      expect(canTransition(CallPhase.connected, CallPhase.ringing), isFalse);
      expect(canTransition(CallPhase.connected, CallPhase.connecting), isFalse);
      expect(canTransition(CallPhase.connected, CallPhase.incoming), isFalse);
    });

    test('a connected call cannot be marked missed or rejected', () {
      // Both mean "never answered", which this call plainly was.
      expect(canTransition(CallPhase.connected, CallPhase.missed), isFalse);
      expect(canTransition(CallPhase.connected, CallPhase.rejected), isFalse);
      expect(canTransition(CallPhase.connecting, CallPhase.missed), isFalse);
    });

    test('no phase may return to idle except a terminal one', () {
      // Idle is reached by the service explicitly clearing a finished
      // call, never by a live one deciding it is over.
      for (final phase in CallPhase.values) {
        if (phase == CallPhase.idle) continue;
        expect(
          canTransition(phase, CallPhase.idle),
          phase.isTerminal,
          reason: '${phase.name} -> idle disagrees with the table',
        );
      }
    });
  });

  group('idle -> connected is allowed on purpose', () {
    // Documented in kCallTransitions: recovery after a force-quit. The
    // server says we are already in a call, so the app rejoins one in
    // progress rather than starting from ringing. This is the
    // counter-intuitive entry in the table, so it gets its own test —
    // "tighten" it and reconnect-after-crash silently stops working.
    test('a cold start can rejoin a call already in progress', () {
      expect(canTransition(CallPhase.idle, CallPhase.connected), isTrue);
      expect(canTransition(CallPhase.idle, CallPhase.connecting), isTrue);
    });

    test('idle can still start a call in either direction', () {
      expect(canTransition(CallPhase.idle, CallPhase.initiating), isTrue);
      expect(canTransition(CallPhase.idle, CallPhase.incoming), isTrue);
    });

    test('idle cannot jump straight to an outcome', () {
      // There is nothing to end, decline or miss.
      for (final terminal in terminals) {
        expect(
          canTransition(CallPhase.idle, terminal),
          isFalse,
          reason: 'idle -> ${terminal.name} invents an outcome from nothing',
        );
      }
      expect(canTransition(CallPhase.idle, CallPhase.ringing), isFalse);
      expect(canTransition(CallPhase.idle, CallPhase.reconnecting), isFalse);
    });
  });

  group('the table covers the whole enum', () {
    test('every CallPhase has a row', () {
      // A phase with no row means canTransition() is false for
      // everything out of it — a state the app can enter and never
      // leave.
      for (final phase in CallPhase.values) {
        expect(
          kCallTransitions.containsKey(phase),
          isTrue,
          reason: '${phase.name} is missing from kCallTransitions',
        );
      }
    });

    test('no row lists itself', () {
      // Self-transition is handled by canTransition, not the data.
      for (final entry in kCallTransitions.entries) {
        expect(
          entry.value.contains(entry.key),
          isFalse,
          reason: '${entry.key.name} lists itself as a transition',
        );
      }
    });

    test('canTransition agrees with the table for every pair', () {
      for (final from in CallPhase.values) {
        for (final to in CallPhase.values) {
          final expected =
              from == to || (kCallTransitions[from]?.contains(to) ?? false);
          expect(
            canTransition(from, to),
            expected,
            reason: '${from.name} -> ${to.name}',
          );
        }
      }
    });
  });

  group('phase classification is consistent', () {
    test('exactly the five outcomes are terminal', () {
      for (final phase in CallPhase.values) {
        expect(
          phase.isTerminal,
          terminals.contains(phase),
          reason: '${phase.name}.isTerminal is wrong',
        );
      }
    });

    test('nothing is both terminal and live', () {
      for (final phase in CallPhase.values) {
        expect(
          phase.isTerminal && phase.isLive,
          isFalse,
          reason: '${phase.name} claims to be both finished and holding the '
              'microphone',
        );
      }
    });

    test('idle is the only phase that is neither terminal nor live', () {
      for (final phase in CallPhase.values) {
        final classified = phase.isTerminal || phase.isLive;
        expect(
          classified,
          phase != CallPhase.idle,
          reason: '${phase.name} falls through both classifications',
        );
      }
    });

    test('only connected and reconnecting count time', () {
      // The billing/timer rule: ringing time is not call time. A brief
      // wobble mid-call still counts, because the call is still up.
      for (final phase in CallPhase.values) {
        expect(
          phase.countsTime,
          phase == CallPhase.connected || phase == CallPhase.reconnecting,
          reason: '${phase.name}.countsTime is wrong',
        );
      }
    });

    test('anything that counts time is live and not terminal', () {
      for (final phase in CallPhase.values) {
        if (!phase.countsTime) continue;
        expect(phase.isLive, isTrue, reason: phase.name);
        expect(phase.isTerminal, isFalse, reason: phase.name);
      }
    });

    test('no ringing phase counts time', () {
      // The one that would show up as an overcharge.
      expect(CallPhase.ringing.countsTime, isFalse);
      expect(CallPhase.incoming.countsTime, isFalse);
      expect(CallPhase.initiating.countsTime, isFalse);
      expect(CallPhase.connecting.countsTime, isFalse);
    });
  });

  group('no state is an unlabelled spinner', () {
    test('every phase except idle has a label', () {
      for (final phase in CallPhase.values) {
        if (phase == CallPhase.idle) continue;
        expect(
          phase.label.trim(),
          isNotEmpty,
          reason: '${phase.name} would paint an indefinite spinner with no '
              'word under it',
        );
      }
    });

    test('idle has no label because there is no call to describe', () {
      expect(CallPhase.idle.label, isEmpty);
    });

    test('every terminal phase says something different', () {
      // "Call ended" for a decline, a miss and a failure would make the
      // outcome screen useless.
      final labels = terminals.map((p) => p.label).toSet();
      expect(labels.length, terminals.length);
    });
  });
}
