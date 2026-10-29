import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'cache_service.dart';
import 'reading_plan_service.dart';
import 'sabbath_service.dart';

/// On-phone reminders for the Library: the daily Bible reading and the
/// Friday "Sabbath begins at …" note.
///
/// Both are scheduled as ABSOLUTE instants a week or two ahead and re-armed
/// whenever the app starts ([rearm]). A repeating daily alarm would need the
/// phone's real time zone, which the app does not read (WatchReminderService
/// pins Africa/Harare); and sundown moves every Friday, so it cannot repeat
/// anyway. Re-arming on launch also picks up a new plan, a new location or
/// a changed time without any extra bookkeeping.
///
/// Taps carry `reference_type=reading_plan` / `sabbath`, which main.dart's
/// push-tap switch routes to the matching screen.
class LibraryReminders {
  LibraryReminders._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'library_reminders',
    'Bible reading and Sabbath',
    description: 'Your daily reading and the Friday sundown reminder.',
    importance: Importance.defaultImportance,
  );

  // Fixed id blocks so cancelling is exact and never touches other
  // notifications.
  static const _readingBase = 710000;
  static const _readingDays = 14;
  static const _sabbathBase = 720000;
  static const _sabbathWeeks = 8;

  /// "HH:mm", or absent when off. The member's own choice → not `pref:`.
  static const _kReadingTime = 'reading_reminder_time';

  /// Minutes before Friday sundown, or absent when off. A device-level
  /// observance setting, like the other Sabbath prefs → `pref:`.
  static const _kSabbathLead = 'pref:sabbath_reminder_minutes';

  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static bool _ready = false;

  static Future<void> _ensureReady() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.createNotificationChannel(_channel);
    _ready = true;
  }

  /// Asks for notification permission when a reminder is switched on.
  /// Returns false if the member said no.
  static Future<bool> _askPermission() async {
    try {
      if (Platform.isAndroid) {
        final android = _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        return await android?.requestNotificationsPermission() ?? true;
      }
      if (Platform.isIOS) {
        final ios = _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >();
        return await ios?.requestPermissions(alert: true, sound: true) ?? true;
      }
    } catch (_) {}
    return true;
  }

  // ---- settings ------------------------------------------------------------

  /// (hour, minute) of the daily reading reminder, or null when off.
  static (int, int)? readingTime() {
    final raw = CacheService.readPref(_kReadingTime);
    if (raw == null) return null;
    final p = raw.split(':');
    if (p.length != 2) return null;
    final h = int.tryParse(p[0]);
    final m = int.tryParse(p[1]);
    if (h == null || m == null) return null;
    return (h, m);
  }

  static Future<bool> setReadingTime((int, int)? time) async {
    if (time != null && !await _askPermission()) return false;
    if (time == null) {
      await CacheService.deletePref(_kReadingTime);
    } else {
      await CacheService.writePref(
        _kReadingTime,
        '${time.$1.toString().padLeft(2, '0')}:'
        '${time.$2.toString().padLeft(2, '0')}',
      );
    }
    revision.value++;
    await rearmReading();
    return true;
  }

  static int? sabbathLead() =>
      int.tryParse(CacheService.readPref(_kSabbathLead) ?? '');

  static Future<bool> setSabbathLead(int? minutes) async {
    if (minutes != null && !await _askPermission()) return false;
    if (minutes == null) {
      await CacheService.deletePref(_kSabbathLead);
    } else {
      await CacheService.writePref(_kSabbathLead, '$minutes');
    }
    revision.value++;
    await rearmSabbath();
    return true;
  }

  // ---- scheduling ----------------------------------------------------------

  /// The next [count] reading reminders after [now], at [time] local.
  /// Public for the tests.
  static List<DateTime> readingInstants(
    (int, int) time, {
    DateTime? now,
    int count = _readingDays,
  }) {
    final t = now ?? DateTime.now();
    final out = <DateTime>[];
    var day = DateTime(t.year, t.month, t.day, time.$1, time.$2);
    if (!day.isAfter(t)) day = day.add(const Duration(days: 1));
    while (out.length < count) {
      out.add(day);
      day = DateTime(day.year, day.month, day.day + 1, time.$1, time.$2);
    }
    return out;
  }

  /// The next [count] "Sabbath begins soon" instants after [now].
  /// Public for the tests.
  static List<({DateTime fireAt, DateTime sunset})> sabbathInstants(
    int leadMinutes, {
    DateTime? now,
    int count = _sabbathWeeks,
    DateTime Function(DateTime localDate)? sunsetOn,
  }) {
    final t = now ?? DateTime.now();
    final sunset = sunsetOn ?? SabbathService.sunsetOn;
    final out = <({DateTime fireAt, DateTime sunset})>[];
    var friday = DateTime(t.year, t.month, t.day);
    while (friday.weekday != DateTime.friday) {
      friday = friday.add(const Duration(days: 1));
    }
    while (out.length < count) {
      final s = sunset(friday);
      final fire = s.subtract(Duration(minutes: leadMinutes));
      if (fire.isAfter(t.toUtc())) out.add((fireAt: fire, sunset: s));
      friday = DateTime(friday.year, friday.month, friday.day + 7);
    }
    return out;
  }

  static NotificationDetails get _details => NotificationDetails(
    android: AndroidNotificationDetails(
      _channel.id,
      _channel.name,
      channelDescription: _channel.description,
    ),
    iOS: const DarwinNotificationDetails(),
  );

  static Future<void> _schedule(
    int id,
    String title,
    String body,
    DateTime at,
    String type,
  ) => _plugin.zonedSchedule(
    id,
    title,
    body,
    tz.TZDateTime.from(at, tz.UTC),
    _details,
    // Exact alarms are a special permission on Android 14; a reading
    // or Sabbath reminder a few minutes late is fine.
    androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    uiLocalNotificationDateInterpretation:
        UILocalNotificationDateInterpretation.absoluteTime,
    payload: 'reference_type=$type',
  );

  static Future<void> rearmReading() async {
    try {
      await _ensureReady();
      for (var i = 0; i < _readingDays; i++) {
        await _plugin.cancel(_readingBase + i);
      }
      final time = readingTime();
      final active = ReadingPlanService.active();
      if (time == null || active.isEmpty) return;
      final (plan, progress) = active.first;
      var instants = readingInstants(time);
      // Already read today → no nag today.
      if (progress.done.contains(progress.scheduledDay(plan.days))) {
        final now = DateTime.now();
        instants = instants
            .where(
              (d) =>
                  d.year != now.year ||
                  d.month != now.month ||
                  d.day != now.day,
            )
            .toList();
      }
      for (var i = 0; i < instants.length; i++) {
        await _schedule(
          _readingBase + i,
          "Today's Bible reading",
          plan.title,
          instants[i],
          'reading_plan',
        );
      }
    } catch (e) {
      debugPrint('LibraryReminders.rearmReading: $e');
    }
  }

  static Future<void> rearmSabbath() async {
    try {
      await _ensureReady();
      for (var i = 0; i < _sabbathWeeks; i++) {
        await _plugin.cancel(_sabbathBase + i);
      }
      final lead = sabbathLead();
      if (lead == null) return;
      final list = sabbathInstants(lead);
      for (var i = 0; i < list.length; i++) {
        // In the chosen place's zone, matching the Sabbath hours screen.
        final local = SabbathService.placeTime(list[i].sunset);
        final hhmm =
            '${local.hour.toString().padLeft(2, '0')}:'
            '${local.minute.toString().padLeft(2, '0')}';
        await _schedule(
          _sabbathBase + i,
          'Sabbath begins at $hhmm',
          'Sundown is in ${_leadText(lead)}. Get ready to welcome the Sabbath.',
          list[i].fireAt,
          'sabbath',
        );
      }
    } catch (e) {
      debugPrint('LibraryReminders.rearmSabbath: $e');
    }
  }

  static String _leadText(int minutes) => minutes % 60 == 0
      ? (minutes == 60 ? '1 hour' : '${minutes ~/ 60} hours')
      : '$minutes minutes';

  /// Called on app start. Cheap when both reminders are off.
  static Future<void> rearm() async {
    if (readingTime() == null && sabbathLead() == null) return;
    await rearmReading();
    await rearmSabbath();
  }
}
