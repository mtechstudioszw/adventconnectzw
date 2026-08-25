import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'billing/premium_tier.dart';
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

  /// Which LEVEL of premium, cached beside the date it expires.
  ///
  /// Deliberately a separate key rather than a v2 of [_kUntilKey]: an
  /// existing subscriber upgrading to this build has a valid cached
  /// date, and re-keying would drop them back to free until the first
  /// successful refresh — offline, that could be days. A missing tier
  /// beside a live date resolves to [PremiumTier.plus], which is what
  /// every pre-tier subscriber actually bought.
  static const _kTierKey = 'premium_tier_v1';

  static final ValueNotifier<bool> _isPremium = ValueNotifier<bool>(false);

  /// The level currently in force. [PremiumTier.none] whenever
  /// [isPremium] is false — the two can never disagree, because [_apply]
  /// derives both from the same evaluation.
  static final ValueNotifier<PremiumTier> _tier =
      ValueNotifier<PremiumTier>(PremiumTier.none);

  /// What the server last said, before expiry is applied.
  static PremiumTier _storedTier = PremiumTier.none;

  /// Listen to this to rebuild when premium starts or lapses. Read-only
  /// by design — the only ways to move it are [refresh] (server truth),
  /// [clear] (sign-out) and the debug seam below. Nothing in the app may
  /// promote itself.
  static ValueListenable<bool> get isPremium => _isPremium;

  /// Convenience for non-widget code (services, managers).
  static bool get isActive => _isPremium.value;

  /// Listen to this to rebuild when the LEVEL changes — including the
  /// Plus to Pro case, where [isPremium] never moves and a widget
  /// watching only that would never hear about the upgrade it was just
  /// paid for.
  static ValueListenable<PremiumTier> get tierListenable => _tier;

  /// The level in force right now.
  static PremiumTier get tier => _tier.value;

  /// Entitlements at the current level — call minutes, AI questions,
  /// ads. Always safe to read; free is a level like any other.
  static TierBenefits get benefits => TierBenefits.of(_tier.value);

  /// Does this member hold [required] or better?
  ///
  /// Prefer this to comparing [tier] directly, so a level added above
  /// Pro later does not lock existing members out of a feature they are
  /// paying more than enough for.
  static bool hasTier(PremiumTier required) => _tier.value.atLeast(required);

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
      _storedTier = _tierFromServer(
        await SecureStorageService.read(_kTierKey),
        _premiumUntil,
      );
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
      // `premium_tier` needs its own GRANT SELECT — `authenticated` has
      // no table-level SELECT on profiles, it reads entirely through
      // per-column grants, and a select naming an ungranted column fails
      // AS A WHOLE. Without the grant, premium would stop refreshing for
      // everybody rather than just missing the tier. patch_268 issues it;
      // that is why the column is added there and not casually here.
      final row = await _client
          .from('profiles')
          .select('premium_until, premium_tier')
          .eq('id', userId)
          .maybeSingle();
      final raw = row?['premium_until'];
      final until = raw == null ? null : DateTime.tryParse('$raw')?.toUtc();
      await _store(
        userId: userId,
        until: until,
        tier: _tierFromServer(row?['premium_tier'], until),
      );
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
    _storedTier = PremiumTier.none;
    _isPremium.value = false;
    _tier.value = PremiumTier.none;
    try {
      await SecureStorageService.delete(_kUntilKey);
      await SecureStorageService.delete(_kOwnerKey);
      await SecureStorageService.delete(_kTierKey);
    } catch (e) {
      // In-memory state is already false, which is the part that matters.
      debugPrint('PremiumService.clear could not wipe the cache: $e');
    }
  }

  /// Read the server's tier value, with one rule that matters: a member
  /// who HAS a live premium date but no tier is [PremiumTier.plus], not
  /// [PremiumTier.none].
  ///
  /// That is every subscriber who bought before tiers existed, read by a
  /// build that shipped after. Treating them as free would take the
  /// ad-free app away from people mid-subscription on nothing worse than
  /// a null. The server grandfathers them properly — patch_268 puts them
  /// on `pro` — but this client must not depend on that having run yet.
  static PremiumTier _tierFromServer(Object? raw, DateTime? until) {
    final parsed = PremiumTier.parse(raw);
    if (parsed != PremiumTier.none) return parsed;
    return until == null ? PremiumTier.none : PremiumTier.plus;
  }

  static Future<void> _store({
    required String userId,
    required DateTime? until,
    required PremiumTier tier,
  }) async {
    _owner = userId;
    _premiumUntil = until;
    _storedTier = tier;
    try {
      await SecureStorageService.write(_kOwnerKey, userId);
      await SecureStorageService.write(_kTierKey, tier.id);
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

  /// Recompute [isPremium] and [tier] from the cached date + the
  /// signed-in user. Both come from the same evaluation, so an expired
  /// date can never leave a live tier standing behind it.
  static void _apply() {
    final active = _evaluate(
      until: _premiumUntil,
      owner: _owner,
      currentUserId: _currentUserIdOrNull,
      now: DateTime.now().toUtc(),
    );
    _isPremium.value = active;
    _tier.value = active ? _storedTier : PremiumTier.none;
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
      // Through _apply, so the TIER drops with the flag. Setting
      // _isPremium alone here would have left a lapsed member on Pro
      // call minutes and Pro AI until the next refresh.
      _apply();
    });
  }

  /// Test seam. Sets the in-memory state directly — no storage, no
  /// network — so widget tests can put the app in either state.
  @visibleForTesting
  static void debugSet({
    DateTime? until,
    String? owner,
    bool? premium,
    PremiumTier? tier,
  }) {
    _initialized = true;
    _premiumUntil = until;
    _owner = owner;
    _expiryTimer?.cancel();
    _expiryTimer = null;
    // Defaults to Plus when a test forces `premium: true` without saying
    // which level — the same rule _tierFromServer applies to a real
    // pre-tier subscriber, so existing tests keep meaning what they meant.
    _storedTier = tier ?? (premium == true ? PremiumTier.plus : _storedTier);
    if (premium != null) {
      _isPremium.value = premium;
      _tier.value = premium ? _storedTier : PremiumTier.none;
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
    _storedTier = PremiumTier.none;
    _initialized = false;
    _isPremium.value = false;
    _tier.value = PremiumTier.none;
  }
}
