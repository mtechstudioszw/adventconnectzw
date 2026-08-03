import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_version.dart';

/// Feature-usage tracking that lands in **Supabase**, where the admin
/// console can read it.
///
/// Why this exists alongside AnalyticsService: that one writes to
/// Firebase, and Firebase is not queryable from the admin dashboard
/// without a BigQuery export nobody has set up. The founder's central
/// question — "which features do people actually use, and which are
/// ignored?" — could not be answered at all before this.
///
/// Cheap by construction:
///   * events are queued in memory and flushed in batches, so scrolling
///     the feed is one round trip rather than forty;
///   * an 'open' for the same feature is not re-sent while the user
///     stays in it, so sitting in the Bible for an hour is one event,
///     not one per rebuild;
///   * everything is best-effort — analytics must never surface an
///     error, block a screen, or retry hard enough to cost battery.
///
/// Privacy: no message contents, no names, no free text. A feature key
/// from a fixed server-side vocabulary, an action, and a timestamp.
class UsageAnalytics {
  UsageAnalytics._();

  static SupabaseClient get _client => Supabase.instance.client;

  static const Duration _flushEvery = Duration(seconds: 20);

  /// Above this the queue is dropping events anyway; better to drop
  /// them than to hold a growing list in memory for a user who has been
  /// offline for an hour.
  static const int _maxQueue = 200;

  static final List<Map<String, dynamic>> _queue = [];
  static String? _sessionId;
  static Timer? _timer;
  static bool _started = false;
  static bool _flushing = false;

  /// The last 'open' we sent, so re-entering the same screen repeatedly
  /// doesn't inflate the numbers the founder makes decisions on.
  static String? _lastOpenFeature;

  static String get _platform {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return Platform.operatingSystem;
  }

  static String get _osVersion {
    if (kIsWeb) return 'web';
    try {
      return Platform.operatingSystemVersion;
    } catch (_) {
      return 'unknown';
    }
  }

  /// Begin a session. Safe to call more than once; only the first wins.
  static void start() {
    if (_started) return;
    _started = true;
    // A v4-ish id generated client-side: the server only uses it to
    // group events, and it is scoped to the caller's own user id.
    _sessionId = _newSessionId();
    _timer = Timer.periodic(_flushEvery, (_) => unawaited(flush()));
  }

  /// The user entered a feature.
  static void open(String feature, {String? screen}) {
    if (_lastOpenFeature == feature) return;
    _lastOpenFeature = feature;
    _record(feature, 'open', screen);
  }

  /// The user did the thing the feature is FOR — sent the message, read
  /// the chapter, played the hymn. This is the number that separates a
  /// feature people use from one they merely open.
  static void engage(String feature, {String? screen}) {
    _record(feature, 'engage', screen);
  }

  /// A multi-step flow finished (a quiz round, a checkout).
  static void complete(String feature, {String? screen}) {
    _record(feature, 'complete', screen);
  }

  static void _record(String feature, String action, String? screen) {
    if (!_started) return;
    if (_queue.length >= _maxQueue) return;
    _queue.add({
      'feature': feature,
      'action': action,
      'screen': ?screen,
      // Stamped client-side so an event queued offline keeps its real
      // time when it eventually flushes. The server clamps anything in
      // the future.
      'at': DateTime.now().toUtc().toIso8601String(),
    });
    if (_queue.length >= 20) unawaited(flush());
  }

  /// Send whatever is queued. Called on a timer, when the batch fills,
  /// and when the app goes to the background.
  static Future<void> flush() async {
    if (_flushing || _queue.isEmpty || _sessionId == null) return;
    if (_client.auth.currentUser == null) {
      // Signed out — these events have nobody to belong to.
      _queue.clear();
      return;
    }
    _flushing = true;
    // Take the batch out first: a failure drops it rather than
    // retrying forever, because stale usage data is worth less than
    // the battery a retry loop costs.
    final batch = List<Map<String, dynamic>>.from(_queue);
    _queue.clear();
    try {
      await _client.rpc('track_app_events', params: {
        'p_session_id': _sessionId,
        'p_platform': _platform,
        'p_app_version': '$kAppBuildNumber',
        'p_os_version': _osVersion,
        'p_events': batch,
      });
    } catch (e) {
      debugPrint('UsageAnalytics flush failed (dropped ${batch.length}): $e');
    } finally {
      _flushing = false;
    }
  }

  /// End of session — flush and stop the timer.
  static Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    await flush();
    _started = false;
    _sessionId = null;
    _lastOpenFeature = null;
  }

  /// A new session on sign-in, so one device shared by two people
  /// doesn't merge their usage.
  static void resetSession() {
    _lastOpenFeature = null;
    _sessionId = _newSessionId();
  }

  static String _newSessionId() {
    final now = DateTime.now().microsecondsSinceEpoch;
    final rand = now.hashCode.toUnsigned(32).toRadixString(16).padLeft(8, '0');
    final a = now.toUnsigned(32).toRadixString(16).padLeft(8, '0');
    final b = (now >> 32).toUnsigned(16).toRadixString(16).padLeft(4, '0');
    final c = (now ~/ 7).toUnsigned(16).toRadixString(16).padLeft(4, '0');
    final d = (now ~/ 13).toUnsigned(16).toRadixString(16).padLeft(4, '0');
    return '$a-$b-4${c.substring(1)}-a$d-$rand${a.substring(0, 4)}';
  }

  @visibleForTesting
  static int get queuedCount => _queue.length;

  @visibleForTesting
  static void debugStart() {
    _started = true;
    _sessionId = _newSessionId();
    _queue.clear();
    _lastOpenFeature = null;
  }

  @visibleForTesting
  static void debugReset() {
    _timer?.cancel();
    _timer = null;
    _started = false;
    _sessionId = null;
    _queue.clear();
    _lastOpenFeature = null;
  }
}

/// The feature vocabulary, mirroring `public.app_features`.
///
/// Kept as constants rather than raw strings so a typo is a compile
/// error instead of an event the server silently drops.
class Feature {
  Feature._();

  static const home = 'home';
  static const chat = 'chat';
  static const watch = 'watch';
  static const marketplace = 'marketplace';
  static const events = 'events';
  static const churches = 'churches';
  static const prayer = 'prayer';
  static const quiz = 'quiz';
  static const jobs = 'jobs';
  static const news = 'news';
  static const libraryBible = 'library_bible';
  static const librarySabbath = 'library_sabbath';
  static const libraryHymnal = 'library_hymnal';
  static const libraryEgw = 'library_egw';
  static const libraryMusic = 'library_music';
  static const search = 'search';
  static const profile = 'profile';
  static const premium = 'premium';

  /// Map a router path to a feature. One place, so instrumenting the
  /// whole app is a router observer rather than a line in ninety
  /// screens — and so a new screen under an existing section is counted
  /// automatically.
  /// These are the app's REAL paths, checked against router_config.dart
  /// rather than assumed. Three of them are not what you'd guess, and
  /// each would have failed silently — recording zero for a feature
  /// people use every day, which is worse than no dashboard at all:
  ///
  ///   * Search is `/home/search`, NOT `/search`. It has to be tested
  ///     BEFORE `/home` or it is swallowed as home-feed usage.
  ///   * Chat is `/messages`. There is no `/chat` route.
  ///   * `/library` has NO sub-routes at all — the five library
  ///     sections are TABS inside one screen, selected by an `extra`
  ///     int. The router can never see which one is open, so the
  ///     Library screen reports its own tab via [UsageAnalytics.open]
  ///     and this returns null for `/library` rather than guessing.
  static String? fromRoute(String path) {
    // Longest / most specific first.
    if (path.startsWith('/home/search')) return search;
    if (path.startsWith('/home')) return home;
    if (path.startsWith('/messages')) return chat;
    if (path.startsWith('/watch')) return watch;
    if (path.startsWith('/marketplace') || path.startsWith('/cart')) {
      return marketplace;
    }
    if (path.startsWith('/events')) return events;
    if (path.startsWith('/churches')) return churches;
    if (path.startsWith('/prayer')) return prayer;
    if (path.startsWith('/quiz')) return quiz;
    if (path.startsWith('/jobs')) return jobs;
    if (path.startsWith('/news')) return news;
    if (path.startsWith('/seller') || path.startsWith('/users/')) {
      return profile;
    }
    if (path.startsWith('/profile')) return profile;
    if (path.startsWith('/premium')) return premium;
    // '/library' handled by the screen itself — see the doc above.
    // Auth, splash, settings and admin are deliberately unmapped: they
    // are not "features" anyone chooses, and counting them would push
    // real features down the ranking.
    return null;
  }

  /// The library tab index the app uses (0=Bible, 1=Sabbath School,
  /// 2=Hymnal, 3=EGW, 4=Music) mapped to a feature key.
  static String? fromLibraryTab(int index) => switch (index) {
        0 => libraryBible,
        1 => librarySabbath,
        2 => libraryHymnal,
        3 => libraryEgw,
        4 => libraryMusic,
        _ => null,
      };
}
