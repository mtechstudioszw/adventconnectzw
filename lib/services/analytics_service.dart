import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Thin wrapper around Firebase Analytics + Crashlytics so call sites
/// don't have to know which Firebase package owns which API, and so a
/// missing google-services.json / GoogleService-Info.plist (e.g. during
/// initial setup) can't crash the rest of the app.
///
/// Event names match Part 30 of the master reference — keep them stable
/// once they ship, since changing a name breaks the funnel in the
/// Firebase console.
class AnalyticsService {
  AnalyticsService._();

  static final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;
  static final FirebaseCrashlytics _crashlytics = FirebaseCrashlytics.instance;
  static bool _ready = false;

  /// Mark analytics as available. Called from main() after a successful
  /// Firebase.initializeApp(). When false, every method below silently
  /// no-ops so failed Firebase setup never bubbles up to the user.
  static void markReady() {
    _ready = true;
  }

  static Future<void> logEvent(
    String name, {
    Map<String, Object>? parameters,
  }) async {
    if (!_ready) return;
    try {
      await _analytics.logEvent(name: name, parameters: parameters);
    } catch (e, st) {
      debugPrint('AnalyticsService: logEvent $name failed: $e\n$st');
    }
  }

  static Future<void> setUserId(String? id) async {
    if (!_ready) return;
    try {
      await _analytics.setUserId(id: id);
      await _crashlytics.setUserIdentifier(id ?? '');
    } catch (e, st) {
      debugPrint('AnalyticsService: setUserId failed: $e\n$st');
    }
  }

  static Future<void> logScreen(String screenName) async {
    if (!_ready) return;
    try {
      await _analytics.logScreenView(screenName: screenName);
    } catch (e, st) {
      debugPrint('AnalyticsService: logScreen $screenName failed: $e\n$st');
    }
  }

  // Named helpers for the canonical events from Part 30 of the master
  // reference. Use these instead of raw strings so a typo can't quietly
  // create a new event in the console.

  static Future<void> churchFollowed(int churchId) =>
      logEvent('church_followed', parameters: {'church_id': churchId});

  static Future<void> messageSent({String? source}) =>
      logEvent('message_sent', parameters: {?'source': source});

  static Future<void> prayerPosted({required String visibility}) =>
      logEvent('prayer_posted', parameters: {'visibility': visibility});

  static Future<void> marketplaceContact(int productId) =>
      logEvent('marketplace_contact', parameters: {'product_id': productId});

  static Future<void> eventRsvp(int eventId, String status) =>
      logEvent('event_rsvp', parameters: {'event_id': eventId, 'status': status});

  static Future<void> churchClaimed(int churchId) =>
      logEvent('church_claimed', parameters: {'church_id': churchId});

  static Future<void> jobPosted(String category) =>
      logEvent('job_posted', parameters: {'category': category});

  static Future<void> sellerApplied() => logEvent('seller_applied');

  /// Record a non-fatal error to Crashlytics with optional context.
  /// Use for caught exceptions you still want visibility on (e.g. an
  /// upload that failed three times).
  static Future<void> recordError(
    Object error,
    StackTrace? stack, {
    String? reason,
    bool fatal = false,
  }) async {
    if (!_ready) {
      debugPrint('Crashlytics (not ready): $error\n$stack');
      return;
    }
    try {
      await _crashlytics.recordError(error, stack, reason: reason, fatal: fatal);
    } catch (e) {
      debugPrint('AnalyticsService: recordError failed: $e');
    }
  }
}
