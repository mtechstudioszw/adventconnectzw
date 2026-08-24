import 'package:flutter/foundation.dart';

import 'premium_service.dart';
import 'secure_storage_service.dart';

/// Decides when the app may ask someone to subscribe.
///
/// The rule the founder set: at most once every 14 days, and never in
/// the middle of something. "Something" is not a vague idea here — the
/// blocked list below is explicit, because an upgrade prompt landing on
/// a prayer request, a chat you're typing into, or a checkout is how an
/// app gets uninstalled rather than upgraded.
///
/// Who sees it: everyone who has not paid. Holding a role — church
/// admin, verified admin, super admin — grants nothing (founder's rule,
/// 3 Aug 2026), so admins get the promo like anyone else.
class PremiumPromoService {
  PremiumPromoService._();

  static const _kLastShown = 'premium_promo_last_v1';
  static const _kFirstSeen = 'premium_promo_first_seen_v1';

  /// The founder's cadence.
  static const Duration gap = Duration(days: 14);

  /// Don't pitch to someone who has barely arrived. They haven't seen
  /// enough ads for "remove the ads" to mean anything yet, and a
  /// day-one paywall is the fastest way to lose a new user.
  static const Duration warmUp = Duration(days: 2);

  /// Routes where an upgrade prompt is never acceptable.
  ///
  /// Chat and prayer are here for the same reason ads are banned from
  /// them: they are the two places people bring something private.
  /// Checkout and donate are here because interrupting a payment with a
  /// different payment is the worst possible timing.
  static const List<String> blockedRoutePrefixes = [
    '/splash',
    '/login',
    '/signup',
    '/onboarding',
    '/intro',
    '/email-verification',
    '/profile-setup',
    '/forgot-password',
    '/reset-password',
    '/biometric-lock',
    '/account-banned',
    '/update-required',
    '/admin',
    // Private, or mid-transaction.
    '/chat',
    '/messages',
    '/conversation',
    '/prayer',
    '/cart',
    '/checkout',
    '/donate',
    '/iphone-fundraiser',
    // Don't pitch the thing they're already looking at.
    '/premium',
  ];

  /// Once per app run, whatever else happens.
  static bool _shownThisSession = false;

  static DateTime? _lastShown;
  static DateTime? _firstSeen;
  static bool _loaded = false;

  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      _lastShown =
          DateTime.tryParse(await SecureStorageService.read(_kLastShown) ?? '');
      final first = await SecureStorageService.read(_kFirstSeen);
      _firstSeen = DateTime.tryParse(first ?? '');
      if (_firstSeen == null) {
        // First run: start the warm-up clock now.
        _firstSeen = DateTime.now();
        await SecureStorageService.write(
            _kFirstSeen, _firstSeen!.toIso8601String());
      }
    } catch (e) {
      debugPrint('PremiumPromoService.load failed: $e');
    }
  }

  /// The whole decision, pure, so every rule can be tested without a
  /// clock, a router or storage.
  @visibleForTesting
  static bool shouldShow({
    required bool isPremium,
    required String route,
    required bool isTyping,
    required bool shownThisSession,
    required DateTime now,
    DateTime? lastShown,
    DateTime? firstSeen,
  }) {
    // Paying users are never asked to pay again.
    if (isPremium) return false;
    if (shownThisSession) return false;
    // Someone with a keyboard up is mid-thought. Never interrupt it.
    if (isTyping) return false;
    if (blockedRoutePrefixes.any(route.startsWith)) return false;
    if (firstSeen != null && now.difference(firstSeen) < warmUp) return false;
    if (lastShown != null && now.difference(lastShown) < gap) return false;
    return true;
  }

  /// Live version of [shouldShow], reading the app's own state.
  static Future<bool> canShowNow({
    required String route,
    required bool isTyping,
  }) async {
    await load();
    return shouldShow(
      isPremium: PremiumService.isActive,
      route: route,
      isTyping: isTyping,
      shownThisSession: _shownThisSession,
      now: DateTime.now(),
      lastShown: _lastShown,
      firstSeen: _firstSeen,
    );
  }

  /// Record that we asked. Call when the promo is actually shown, not
  /// when it is merely allowed — otherwise a suppressed prompt would
  /// silently burn the fortnight.
  static Future<void> markShown() async {
    _shownThisSession = true;
    _lastShown = DateTime.now();
    try {
      await SecureStorageService.write(
          _kLastShown, _lastShown!.toIso8601String());
    } catch (e) {
      debugPrint('PremiumPromoService.markShown could not persist: $e');
    }
  }

  @visibleForTesting
  static void debugReset() {
    _shownThisSession = false;
    _lastShown = null;
    _firstSeen = null;
    _loaded = false;
  }
}
