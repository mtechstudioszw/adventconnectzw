import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'secure_storage_service.dart';

/// Single source of truth for "is this user a paying subscriber?".
///
/// The app never decides this for itself. Premium is granted **only** by
/// the server, which writes `profiles.premium_until` after verifying a
/// purchase with the store. The client's job is to read that timestamp,
/// cache it, and answer [isPremium] instantly — including offline, and
/// including the first frame of a cold start.
///
/// Why a timestamp and not a bool:
///   * it expires by itself, so a stale cache can never grant free
///     premium forever — the worst case is premium until the date the
///     server last confirmed, which the user had already paid for;
///   * the grace period (Google retrying a failed card) and account hold
///     are just the server pushing the date out, so the client needs no
///     concept of either;
///   * a refund is the server pulling the date back to now, which the
///     next [refresh] picks up.
///
/// Store-agnostic on purpose. Nothing here knows what Google Play is —
/// when iOS/StoreKit arrives it writes the same column and this file
/// does not change. See `lib/services/billing/`.
class PremiumService {
  PremiumService._();

  // Late-bound: a field initializer would run before any test seam and
  // assert on an uninitialised Supabase. (Testing rule, learned twice.)
  static SupabaseClient get _client => Supabase.instance.client;

  /// Absolute instant premium lapses, cached so an offline launch still
  /// knows. Stored as an ISO-8601 UTC string.
  static const _kUntilKey = 'premium_until_v1';

  /// Which user the cached date belongs to. Without this, signing out and
  /// signing in as someone else would inherit the previous user's
  /// premium until the first successful refresh.
  static const _kOwnerKey = 'premium_owner_v1';

  static final ValueNotifier<bool> _isPremium = ValueNotifier<bool>(false);

  /// Listen to this to rebuild when premium starts or lapses. Read-only
  /// by design — the only ways to move it are [refresh] (server truth),
  /// [clear] (sign-out) and the debug seam below. Nothing in the app may
  /// promote itself.
  static ValueListenable<bool> get isPremium => _isPremium;

  /// Convenience for non-widget code (services, managers).
  static bool get isActive => _isPremium.value;

  static DateTime? _premiumUntil;

  /// When the current subscription lapses, in UTC. Null when not premium.
  /// The Premium screen shows this as "Renews on …".
  static DateTime? get premiumUntil => _premiumUntil;

  static String? _owner;
  static bool _initialized = false;
  static Timer? _expiryTimer;

  /// Load the cached state. Call once at startup **after** Supabase is
  /// ready (so `currentUser` is restored), and before AdMob is
  /// initialised — a premium user should never even start the ad SDK.
  ///
  /// Cheap: one secure-storage read, no network. [refresh] does the
  /// network part and can run unawaited.
  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final until = await SecureStorageService.read(_kUntilKey);
      _owner = await SecureStorageService.read(_kOwnerKey);
      _premiumUntil = DateTime.tryParse(until ?? '')?.toUtc();
    } catch (e) {
      // Secure storage is not universally reliable on Android. A read
      // failure means we start as free and the first refresh() fixes it
      // — never a crash on the startup path.
      debugPrint('PremiumService.init could not read the cache: $e');
    }
    _apply();
  }

  /// Ask the server whether this user is premium, and cache the answer.
  ///
  /// Best-effort: offline or a failed request leaves the cached state
  /// alone rather than dropping a paying user back into ads because
  /// their bus went through a tunnel.
  static Future<bool> refresh() async {
    final userId = _currentUserIdOrNull;
    if (userId == null) {
      await clear();
      return false;
    }
    try {
      final row = await _client
          .from('profiles')
          .select('premium_until')
          .eq('id', userId)
          .maybeSingle();
      final raw = row?['premium_until'];
      final until = raw == null ? null : DateTime.tryParse('$raw')?.toUtc();
      await _store(userId: userId, until: until);
    } catch (e) {
      debugPrint('PremiumService.refresh failed (keeping cache): $e');
    }
    return _isPremium.value;
  }

  /// Wipe every trace on sign-out. The next user starts as not-premium
  /// and earns their own state from the server.
  static Future<void> clear() async {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _premiumUntil = null;
    _owner = null;
    _isPremium.value = false;
    try {
      await SecureStorageService.delete(_kUntilKey);
      await SecureStorageService.delete(_kOwnerKey);
    } catch (e) {
      // In-memory state is already false, which is the part that matters.
      debugPrint('PremiumService.clear could not wipe the cache: $e');
    }
  }

  static Future<void> _store({
    required String userId,
    required DateTime? until,
  }) async {
    _owner = userId;
    _premiumUntil = until;
    try {
      await SecureStorageService.write(_kOwnerKey, userId);
      if (until == null) {
        await SecureStorageService.delete(_kUntilKey);
      } else {
        await SecureStorageService.write(_kUntilKey, until.toIso8601String());
      }
    } catch (e) {
      // The user is still premium for this session; only the offline
      // cache is missing, and the next refresh will try again.
      debugPrint('PremiumService could not cache premium state: $e');
    }
    _apply();
  }

  /// Recompute [isPremium] from the cached date + the signed-in user.
  static void _apply() {
    _isPremium.value = _evaluate(
      until: _premiumUntil,
      owner: _owner,
      currentUserId: _currentUserIdOrNull,
      now: DateTime.now().toUtc(),
    );
    _scheduleExpiry();
  }

  /// Reading `currentUser` before Supabase is initialised throws, and
  /// [init] can legitimately run early in a test. Treat that as "nobody
  /// is signed in" rather than crashing startup.
  static String? get _currentUserIdOrNull {
    try {
      return _client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  /// The whole decision, as a pure function, so it can be tested without
  /// Supabase, secure storage or a clock.
  @visibleForTesting
  static bool evaluate({
    required DateTime? until,
    required String? owner,
    required String? currentUserId,
    required DateTime now,
  }) =>
      _evaluate(
          until: until, owner: owner, currentUserId: currentUserId, now: now);

  static bool _evaluate({
    required DateTime? until,
    required String? owner,
    required String? currentUserId,
    required DateTime now,
  }) {
    if (until == null) return false;
    // A cached date with no signed-in user, or one belonging to a
    // different account, grants nothing.
    if (currentUserId == null || owner == null) return false;
    if (owner != currentUserId) return false;
    return until.isAfter(now);
  }

  /// Bring the ads back the moment the subscription lapses, without
  /// waiting for a relaunch. Only armed when expiry is close — a timer
  /// held for the other 29 days of the month buys nothing, and [refresh]
  /// re-arms it on every app start and resume.
  static void _scheduleExpiry() {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    final until = _premiumUntil;
    if (until == null || !_isPremium.value) return;
    final left = until.difference(DateTime.now().toUtc());
    if (left <= Duration.zero || left > const Duration(days: 2)) return;
    _expiryTimer = Timer(left, () {
      _expiryTimer = null;
      _isPremium.value = _evaluate(
        until: _premiumUntil,
        owner: _owner,
        currentUserId: _currentUserIdOrNull,
        now: DateTime.now().toUtc(),
      );
    });
  }

  /// Test seam. Sets the in-memory state directly — no storage, no
  /// network — so widget tests can put the app in either state.
  @visibleForTesting
  static void debugSet({DateTime? until, String? owner, bool? premium}) {
    _initialized = true;
    _premiumUntil = until;
    _owner = owner;
    _expiryTimer?.cancel();
    _expiryTimer = null;
    if (premium != null) {
      _isPremium.value = premium;
    } else {
      _apply();
    }
  }

  /// Test seam: back to a signed-out, never-initialised service.
  @visibleForTesting
  static void debugReset() {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _premiumUntil = null;
    _owner = null;
    _initialized = false;
    _isPremium.value = false;
  }
}
