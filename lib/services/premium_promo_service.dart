import 'package:flutter/foundation.dart';

import 'billing/premium_tier.dart';
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

  /// In a member's first month the ask comes weekly instead (owner, 4 Nov
  /// 2026: "people are not reaching the premium screen … some users think
  /// we don't have premium"). New members are the ones who don't know.
  static const Duration newMemberGap = Duration(days: 7);
  static const Duration newMemberPeriod = Duration(days: 30);

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
    final isNew =
        firstSeen != null && now.difference(firstSeen) < newMemberPeriod;
    final wait = isNew ? newMemberGap : gap;
    if (lastShown != null && now.difference(lastShown) < wait) return false;
    return true;
  }

  // ------------------------------------------------------------ feed card
  //
  // The quiet, always-there promotion: one card in the Home feed (after
  // the 4th post), not a pop-up. Android only — the caller checks
  // kHidePayments. Shown from day one, because the complaint is that new
  // members never learn Premium exists; dismissing it snoozes it.

  static const _kCardDismissed = 'premium_card_dismissed_v1';
  static const _kCardDismissals = 'premium_card_dismissals_v1';
  static const _kUpgradeDismissed = 'premium_upgrade_dismissed_v1';

  /// First "Not now" hides it for 3 days; after the third, 10 days. A
  /// member who keeps saying no is told less often, not more.
  static const Duration cardSnooze = Duration(days: 3);
  static const Duration cardLongSnooze = Duration(days: 10);

  /// Plus members are offered Pro at most once a month — "few", as asked.
  static const Duration upgradeGap = Duration(days: 30);

  static DateTime? _cardDismissed;
  static int _cardDismissals = 0;
  static DateTime? _upgradeDismissed;
  static bool _cardLoaded = false;

  /// What the feed card should be right now. Rebuilds Home when it changes.
  static final ValueNotifier<FeedPromo> feedCard =
      ValueNotifier<FeedPromo>(FeedPromo.none);

  @visibleForTesting
  static FeedPromo feedCardFor({
    required PremiumTier tier,
    required DateTime now,
    DateTime? cardDismissed,
    int dismissals = 0,
    DateTime? upgradeDismissed,
  }) {
    switch (tier) {
      case PremiumTier.none:
        final snooze = dismissals >= 3 ? cardLongSnooze : cardSnooze;
        if (cardDismissed != null && now.difference(cardDismissed) < snooze) {
          return FeedPromo.none;
        }
        return FeedPromo.goPremium;
      case PremiumTier.plus:
        if (upgradeDismissed != null &&
            now.difference(upgradeDismissed) < upgradeGap) {
          return FeedPromo.none;
        }
        return FeedPromo.upgradePro;
      case PremiumTier.pro:
      case PremiumTier.business:
        return FeedPromo.none;
    }
  }

  /// Load the card's state (once) and recompute. Call from Home.
  static Future<void> refreshFeedCard() async {
    if (!_cardLoaded) {
      _cardLoaded = true;
      try {
        _cardDismissed = DateTime.tryParse(
            await SecureStorageService.read(_kCardDismissed) ?? '');
        _cardDismissals = int.tryParse(
                await SecureStorageService.read(_kCardDismissals) ?? '') ??
            0;
        _upgradeDismissed = DateTime.tryParse(
            await SecureStorageService.read(_kUpgradeDismissed) ?? '');
      } catch (e) {
        debugPrint('PremiumPromoService.refreshFeedCard: $e');
      }
    }
    feedCard.value = feedCardFor(
      tier: PremiumService.tier,
      now: DateTime.now(),
      cardDismissed: _cardDismissed,
      dismissals: _cardDismissals,
      upgradeDismissed: _upgradeDismissed,
    );
  }

  /// "Not now" on the card.
  static Future<void> dismissFeedCard() async {
    final now = DateTime.now();
    final kind = feedCard.value;
    feedCard.value = FeedPromo.none;
    try {
      if (kind == FeedPromo.upgradePro) {
        _upgradeDismissed = now;
        await SecureStorageService.write(
            _kUpgradeDismissed, now.toIso8601String());
      } else {
        _cardDismissed = now;
        _cardDismissals++;
        await SecureStorageService.write(
            _kCardDismissed, now.toIso8601String());
        await SecureStorageService.write(
            _kCardDismissals, '$_cardDismissals');
      }
    } catch (e) {
      debugPrint('PremiumPromoService.dismissFeedCard: $e');
    }
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
    _cardDismissed = null;
    _cardDismissals = 0;
    _upgradeDismissed = null;
    _cardLoaded = false;
    feedCard.value = FeedPromo.none;
    _shownThisSession = false;
    _lastShown = null;
    _firstSeen = null;
    _loaded = false;
  }
}

/// Which promotion card, if any, sits in the Home feed.
enum FeedPromo { none, goPremium, upgradePro }
