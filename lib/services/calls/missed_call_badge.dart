import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/call_model.dart';
import '../cache_service.dart';
import 'call_api.dart';

/// How many missed calls the member has not looked at yet.
///
/// Drives the red dot on the Calls button in the chat header (founder
/// request, 25 Aug 2026). Before this, a missed call left no trace
/// anywhere the member would look: the system's own missed-call
/// notification can be swiped away, and the call log is behind a header
/// icon with nothing on it. The call had happened and the app said
/// nothing.
///
/// # What counts
///
/// [CallHistoryEntry.missed] and nothing else — an INCOMING call that
/// never connected. A call the member placed that nobody picked up is
/// not a missed call and must never badge: it would put a permanent
/// alarm on their own history, which is the same reasoning that keeps
/// it out of the red rows in the log itself.
///
/// # "Not looked at yet"
///
/// A timestamp, not a per-call read flag. Opening the call log shows the
/// whole list at once, so "seen" is genuinely a single moment rather
/// than a per-row fact, and a timestamp needs no server column, no
/// migration and no write path — [markSeen] is one local put.
///
/// The key is deliberately NOT `pref:`-prefixed. `CacheService`'s rule
/// is that `pref:` survives sign-out and everything else is wiped by
/// `clearUserData()`, and "which calls has this member seen" is about
/// the member, not the handset. Prefixing it would show the next person
/// to sign in on this phone a badge cleared by someone else's reading —
/// or, worse, hide one of their own.
class MissedCallBadge {
  MissedCallBadge._();

  static const _kSeenKey = 'calls_seen_at_v1';

  /// How far back to look. A missed call from three weeks ago is
  /// history, not a notification, and badging it forever would train
  /// the member to ignore the dot.
  static const Duration _window = Duration(days: 7);

  static final ValueNotifier<int> _count = ValueNotifier<int>(0);

  /// Unseen missed calls. Watch this to paint the dot.
  static ValueListenable<int> get count => _count;

  static bool get hasAny => _count.value > 0;

  static bool _refreshing = false;

  /// Recount from the server.
  ///
  /// Best-effort and never throws: the badge is an embellishment on a
  /// button that works without it, so a failed refresh leaves the last
  /// count alone rather than clearing a dot the member has not acted on.
  static Future<void> refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final entries = await CallApi.history(limit: 40);
      final seenAt = _seenAt();
      final cutoff = DateTime.now().toUtc().subtract(_window);
      var unseen = 0;
      for (final e in entries) {
        if (!e.missed) continue;
        final at = e.startedAt.toUtc();
        if (at.isBefore(cutoff)) continue;
        if (seenAt != null && !at.isAfter(seenAt)) continue;
        unseen++;
      }
      _count.value = unseen;
    } catch (e) {
      debugPrint('MissedCallBadge.refresh failed (keeping count): $e');
    } finally {
      _refreshing = false;
    }
  }

  /// The member is looking at the call log. Clear the dot immediately —
  /// waiting for a round trip would leave it lit on the very screen that
  /// answers it.
  static Future<void> markSeen() async {
    _count.value = 0;
    try {
      await CacheService.writePref(
        _kSeenKey,
        DateTime.now().toUtc().toIso8601String(),
      );
    } catch (e) {
      debugPrint('MissedCallBadge.markSeen could not persist: $e');
    }
  }

  /// A call just ended as missed, on this device, while the app was
  /// open. Counting it here rather than waiting for the next [refresh]
  /// is what makes the dot appear the moment the ringing stops.
  static void noteMissed() => _count.value = _count.value + 1;

  /// Sign-out. The next member starts with a clean button.
  static Future<void> clear() async {
    _count.value = 0;
    try {
      await CacheService.deletePref(_kSeenKey);
    } catch (_) {
      // The in-memory count is already zero, which is the part that
      // shows.
    }
  }

  static DateTime? _seenAt() {
    try {
      final raw = CacheService.readPref(_kSeenKey);
      if (raw == null || raw.isEmpty) return null;
      return DateTime.tryParse(raw)?.toUtc();
    } catch (_) {
      return null;
    }
  }
}
