// When the app is allowed to ask someone to pay.
//
// The founder's rule is "at most once per 14 days, and never during
// login, typing or checkout". Every clause of that is pinned here,
// because the failure mode is invisible in testing and expensive in
// production: a promo that lands on a prayer request or a half-typed
// message doesn't annoy a user slightly, it uninstalls the app.

import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/services/premium_promo_service.dart';

void main() {
  final now = DateTime(2026, 8, 3, 12);

  bool ask({
    bool isPremium = false,
    String route = '/home',
    bool isTyping = false,
    bool shownThisSession = false,
    DateTime? lastShown,
    DateTime? firstSeen,
  }) =>
      PremiumPromoService.shouldShow(
        isPremium: isPremium,
        route: route,
        isTyping: isTyping,
        shownThisSession: shownThisSession,
        now: now,
        lastShown: lastShown,
        // Default to an established user so individual tests only have
        // to set the thing they're actually testing.
        firstSeen: firstSeen ?? now.subtract(const Duration(days: 30)),
      );

  group('cadence', () {
    test('shows to a settled free user who has never been asked', () {
      expect(ask(), isTrue);
    });

    test('never shows to a paying user', () {
      expect(ask(isPremium: true), isFalse);
    });

    test('stays quiet for 14 days after being shown', () {
      expect(ask(lastShown: now.subtract(const Duration(days: 13))), isFalse);
      expect(
        ask(lastShown: now.subtract(const Duration(days: 13, hours: 23))),
        isFalse,
      );
    });

    test('comes back on day 14', () {
      expect(ask(lastShown: now.subtract(const Duration(days: 14))), isTrue);
    });

    test('only once per app run, even after 14 days', () {
      expect(
        ask(
          lastShown: now.subtract(const Duration(days: 30)),
          shownThisSession: true,
        ),
        isFalse,
      );
    });

    test('leaves a brand-new user alone during the warm-up', () {
      // Nobody has seen enough ads on day one for "remove the ads" to
      // mean anything.
      expect(ask(firstSeen: now.subtract(const Duration(hours: 6))), isFalse);
      expect(ask(firstSeen: now.subtract(const Duration(days: 1))), isFalse);
      expect(ask(firstSeen: now.subtract(const Duration(days: 2))), isTrue);
    });
  });

  group('never interrupts', () {
    test('someone who is typing', () {
      expect(ask(isTyping: true), isFalse);
    });

    // Every route the founder named, plus the ones that carry the same
    // risk. A regression here is silent, so the list is asserted whole.
    const mustNeverShow = [
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
      '/chat',
      '/messages',
      '/conversation',
      '/prayer',
      '/cart',
      '/checkout',
      '/donate',
      '/premium',
    ];

    for (final route in mustNeverShow) {
      test('on $route', () {
        expect(ask(route: route), isFalse);
      });
    }

    test('including nested routes under a blocked prefix', () {
      expect(ask(route: '/chat/1234'), isFalse);
      expect(ask(route: '/prayer/new'), isFalse);
      expect(ask(route: '/checkout/confirm'), isFalse);
    });

    test('but does show on ordinary browsing routes', () {
      for (final route in ['/home', '/watch', '/library', '/marketplace']) {
        expect(ask(route: route), isTrue, reason: route);
      }
    });
  });

  group('who it targets', () {
    test('a church admin who has not paid still sees it', () {
      // Founder's rule: paying is the only route to ad-free. The promo
      // has no concept of a role at all, which is what guarantees this —
      // if a role exemption ever creeps in, it has to come through
      // isPremium, and that is server-controlled.
      expect(ask(isPremium: false), isTrue);
    });
  });
}
