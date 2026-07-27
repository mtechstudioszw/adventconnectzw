import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/youtube_video.dart';
import 'cache_service.dart';

/// "Remind me" for a scheduled broadcast.
///
/// DEVICE-LOCAL by design. A cross-device version would need a table plus
/// a scheduled fan-out on the server; this needs neither, works with no
/// signal, and costs nothing to run. The trade-off is that a reminder
/// does not survive a reinstall or follow the user to a second phone —
/// if that becomes a complaint, the upgrade path is a `youtube_reminders`
/// table and the same UI.
///
/// Scheduling is INEXACT on purpose. Exact alarms need
/// `SCHEDULE_EXACT_ALARM`, which Google restricts to genuine alarm-clock
/// apps and will reject a content reminder for. Inexact delivery can slip
/// by a few minutes, so the reminder is set [_leadMinutes] before the
/// broadcast — late-by-a-few still lands before the stream starts.
class WatchReminderService {
  WatchReminderService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const _prefsKey = 'watch:reminders_v1';

  /// How far ahead of the broadcast to fire.
  static const int _leadMinutes = 10;

  /// Zimbabwe has no DST, and SabbathService already computes in
  /// Africa/Harare wall-clock — keeping one assumption avoids a second
  /// dependency just to read the device zone.
  static const _zone = 'Africa/Harare';

  static const AndroidNotificationChannel _channel =
      AndroidNotificationChannel(
    'advent_connect_zw_reminders',
    'Broadcast reminders',
    description: 'Reminders for live services you asked to be told about.',
    importance: Importance.high,
  );

  static bool _ready = false;

  /// Safe to call repeatedly. Called lazily on first use so app start-up
  /// doesn't pay for the timezone database unless a reminder is set.
  static Future<void> _ensureReady() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation(_zone));
    } catch (_) {
      // Falls back to UTC; instants are absolute so the reminder still
      // fires at the right moment.
    }
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(_channel);
    _ready = true;
  }

  // ------------------------------ state ------------------------------
  /// Video ids with a reminder set, read synchronously so a card can
  /// paint the right bell state on first frame.
  static Set<String> all() {
    final raw = CacheService.readPref(_prefsKey);
    if (raw == null || raw.isEmpty) return <String>{};
    try {
      return (jsonDecode(raw) as List).map((e) => e.toString()).toSet();
    } catch (_) {
      return <String>{};
    }
  }

  static bool isSet(String videoId) => all().contains(videoId);

  static Future<void> _persist(Set<String> ids) =>
      CacheService.writePref(_prefsKey, jsonEncode(ids.toList()));

  /// Stable per-video notification id. Android needs a 32-bit int, and
  /// reusing the same id for the same video is what makes cancelling and
  /// re-setting a reminder idempotent.
  static int _idFor(String videoId) => videoId.hashCode & 0x7FFFFFFF;

  // ----------------------------- actions -----------------------------
  /// Turns the reminder on or off. Returns the new state, so the caller
  /// can correct its optimistic UI if scheduling was refused.
  static Future<bool> toggle(YoutubeVideo video) async {
    final wasSet = isSet(video.videoId);
    return wasSet ? !(await cancel(video.videoId)) : await schedule(video);
  }

  /// Returns false when there is nothing to schedule — no start time, or
  /// the broadcast already started.
  static Future<bool> schedule(YoutubeVideo video) async {
    final start = video.scheduledStartAt;
    if (start == null) return false;

    final fireAt = start.subtract(const Duration(minutes: _leadMinutes));
    // Too close to be worth a reminder — the user is already here.
    if (fireAt.isBefore(DateTime.now())) return false;

    await _ensureReady();
    try {
      await _plugin.zonedSchedule(
        _idFor(video.videoId),
        'Starting in $_leadMinutes minutes',
        video.channelTitle.isEmpty
            ? video.title
            : '${video.channelTitle} · ${video.title}',
        tz.TZDateTime.from(fireAt, tz.local),
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channel.id,
            _channel.name,
            channelDescription: _channel.description,
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: const DarwinNotificationDetails(),
        ),
        // See the class comment: exact alarms are not available to a
        // content reminder, so inexact + a 10-minute lead.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        // A broadcast starts at an absolute instant, not at a wall-clock
        // time that should shift with the device's zone.
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        // The payload is what the tap handler deep-links on.
        payload: 'video:${video.videoId}',
      );
    } catch (_) {
      return false;
    }

    await _persist(all()..add(video.videoId));
    return true;
  }

  /// Returns true once the reminder is gone.
  static Future<bool> cancel(String videoId) async {
    await _ensureReady();
    try {
      await _plugin.cancel(_idFor(videoId));
    } catch (_) {/* best effort — clear the flag either way */}
    await _persist(all()..remove(videoId));
    return true;
  }

  /// Drop reminders for broadcasts that have already been and gone, so
  /// the stored set doesn't grow forever.
  static Future<void> prune(Iterable<YoutubeVideo> upcoming) async {
    final live = {
      for (final v in upcoming)
        if ((v.scheduledStartAt ?? DateTime(0)).isAfter(DateTime.now()))
          v.videoId,
    };
    final stored = all();
    final dead = stored.difference(live);
    if (dead.isEmpty) return;
    await _ensureReady();
    for (final id in dead) {
      try {
        await _plugin.cancel(_idFor(id));
      } catch (_) {}
    }
    await _persist(stored..removeAll(dead));
  }
}
