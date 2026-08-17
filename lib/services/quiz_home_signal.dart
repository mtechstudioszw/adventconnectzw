import 'dart:async';

import 'package:flutter/foundation.dart';

import 'presence_service.dart';
import 'quiz_match_service.dart';

/// The quiz's "someone wants you" signal, cached for Home.
///
/// ## Why this exists
///
/// Live match is the only real-time, person-to-person feature in the app,
/// and it was two taps deep behind a tile in the lobby — which is most of
/// why only ~11 members have ever played one. Surfacing it on Home needs a
/// pending-invite count, and the obvious way to get one is wrong:
/// [QuizMatchService.invites] is a **one-shot RPC**, not a stream, so a
/// widget that called it from `build` would fire a network round trip on
/// every rebuild of the busiest screen in the app.
///
/// This holds the answer instead. Home listens to [invites]; something
/// with a reason to believe it changed calls [refresh].
///
/// The online count needs no caching at all — [PresenceService.onChange]
/// is already a maintained roster — so it is re-exported here purely so
/// Home has one import and one mental model for "quiz signals".
class QuizHomeSignal {
  QuizHomeSignal._();

  /// Pending live-match invites aimed at me. Starts at 0 rather than null:
  /// Home should render the quiet state immediately, not a spinner, and
  /// "no invites" is the overwhelmingly common truth.
  static final ValueNotifier<int> invites = ValueNotifier<int>(0);

  /// Members online right now. Straight through to the presence roster.
  static ValueListenable<Set<String>> get online => PresenceService.onChange;

  /// Refreshes no more often than this however many times it is asked.
  ///
  /// Home calls [refresh] on mount, on pull-to-refresh and on app resume,
  /// and those legitimately coincide — an app resumed from a push lands on
  /// Home and triggers all three within a frame of each other. Without a
  /// floor that is three identical RPCs.
  static const _minInterval = Duration(seconds: 20);

  static DateTime? _lastRun;
  static Future<void>? _inFlight;

  /// Fetches the pending invite count.
  ///
  /// Never throws — [QuizMatchService.invites] already swallows its own
  /// errors and returns an empty list, and a failure here must not be able
  /// to break a Home refresh. Concurrent callers share one request.
  ///
  /// Pass [force] for a deliberate user action (pull-to-refresh), which
  /// should not be silently ignored because a timer says so.
  static Future<void> refresh({bool force = false}) {
    final existing = _inFlight;
    if (existing != null) return existing;

    final last = _lastRun;
    if (!force &&
        last != null &&
        DateTime.now().difference(last) < _minInterval) {
      return Future<void>.value();
    }

    final future = _run();
    _inFlight = future;
    return future;
  }

  static Future<void> _run() async {
    try {
      final rows = await QuizMatchService.invites();
      _lastRun = DateTime.now();
      // Assign unconditionally — ValueNotifier already no-ops on an equal
      // value, so this cannot cause a spurious rebuild.
      invites.value = rows.length;
    } catch (e) {
      debugPrint('QuizHomeSignal.refresh failed: $e');
    } finally {
      _inFlight = null;
    }
  }

  /// Drops the count locally, for when the member has just dealt with the
  /// invites — so the dot goes out immediately instead of staying lit
  /// until the next refresh window opens.
  static void markSeen() => invites.value = 0;

  /// Statics outlive a sign-out: the isolate is not restarted, so without
  /// this the next account on the same handset inherits the previous
  /// player's invite count and Home paints somebody else's live dot.
  /// Registered in `SessionReset.onSignOut`.
  static void resetForSignOut() {
    _lastRun = null;
    _inFlight = null;
    invites.value = 0;
  }
}
