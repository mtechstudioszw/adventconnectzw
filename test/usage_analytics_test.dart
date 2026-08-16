// Feature-usage tracking.
//
// The route map is the whole thing: if it returns null for a real
// feature, that feature silently reads as "nobody uses this" on the
// admin dashboard and the founder makes a product decision on a number
// that is wrong. Nothing throws when that happens, so it is pinned here.

import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/services/usage_analytics.dart';

void main() {
  setUp(UsageAnalytics.debugStart);
  tearDown(UsageAnalytics.debugReset);

  group('route to feature', () {
    // These are the app's REAL paths, read out of router_config.dart.
    // Three of them are not the obvious guess, and each wrong guess
    // fails silently as "nobody uses this feature".
    const cases = <String, String>{
      '/home': Feature.home,
      '/messages': Feature.chat,
      '/messages/new-chat': Feature.chat,
      '/watch': Feature.watch,
      '/marketplace': Feature.marketplace,
      '/cart': Feature.marketplace,
      '/events': Feature.events,
      '/churches': Feature.churches,
      '/prayer': Feature.prayer,
      '/quiz': Feature.quiz,
      '/jobs': Feature.jobs,
      '/news': Feature.news,
      '/profile': Feature.profile,
      '/premium': Feature.premium,
    };

    cases.forEach((route, feature) {
      test('$route -> $feature', () {
        expect(Feature.fromRoute(route), feature);
      });
    });

    test('search is nested under /home and must not be eaten by it', () {
      // The real path is /home/search. Checking '/home' first would
      // silently record every search as home-feed usage, and Search
      // would rank dead last on the dashboard forever.
      expect(Feature.fromRoute('/home/search'), Feature.search);
      expect(Feature.fromRoute('/home'), Feature.home);
    });

    test('chat lives at /messages — there is no /chat route', () {
      expect(Feature.fromRoute('/messages'), Feature.chat);
      expect(Feature.fromRoute('/chat'), isNull);
    });

    test('/library maps to nothing — its sections are tabs, not routes', () {
      // The five library sections are selected by an `extra` int inside
      // one screen. The router genuinely cannot tell them apart, so the
      // screen reports its own tab and this must not guess.
      expect(Feature.fromRoute('/library'), isNull);
      expect(Feature.fromLibraryTab(0), Feature.libraryBible);
      expect(Feature.fromLibraryTab(1), Feature.librarySabbath);
      expect(Feature.fromLibraryTab(2), Feature.libraryHymnal);
      expect(Feature.fromLibraryTab(3), Feature.libraryEgw);
      expect(Feature.fromLibraryTab(4), Feature.libraryMusic);
      expect(Feature.fromLibraryTab(9), isNull);
    });

    test('nested screens count as their section', () {
      // A new detail screen under an existing section must be measured
      // without anyone remembering to add tracking to it.
      expect(Feature.fromRoute('/events/42/attendees'), Feature.events);
      expect(Feature.fromRoute('/marketplace/product/7'), Feature.marketplace);
      expect(Feature.fromRoute('/users/abc'), Feature.profile);
    });

    test('non-features are not counted', () {
      // Counting these would push real features down the ranking that
      // decides what gets built next.
      for (final route in [
        '/splash',
        '/login',
        '/signup',
        '/settings',
        '/admin',
        '/biometric-lock',
      ]) {
        expect(Feature.fromRoute(route), isNull, reason: route);
      }
    });
  });

  group('session id', () {
    // `track_app_events` declares `p_session_id uuid`. Postgres parses
    // that argument BEFORE the function body runs, so an id it cannot
    // cast fails the whole call with 22P02 — and UsageAnalytics.flush()
    // swallows the error into a debugPrint. The result is a release
    // build that looks fully instrumented and writes nothing, forever.
    //
    // That is exactly what happened: the original generator emitted
    // groups of 8-4-4-5-12 (a stray 'a' prefixed to an already-4-char
    // group), and app_events sat at 0 rows from 3 Aug 2026 while the
    // admin console had no data to show.
    final uuidV4 = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );

    test('is a UUID Postgres will accept', () {
      for (var i = 0; i < 200; i++) {
        final id = UsageAnalytics.newSessionIdForTest();
        expect(
          uuidV4.hasMatch(id),
          isTrue,
          reason: 'not a valid v4 UUID: "$id" '
              '(groups ${id.split('-').map((g) => g.length).join('-')})',
        );
      }
    });

    test('start() sets a valid session id', () {
      expect(UsageAnalytics.sessionId, isNotNull);
      expect(uuidV4.hasMatch(UsageAnalytics.sessionId!), isTrue);
    });

    test('ids are unique, so two sessions never merge', () {
      // The time-derived generator returned byte-identical ids for
      // everything inside the same millisecond, which made
      // resetSession() a no-op and would merge two people sharing a
      // phone into one session — the exact thing it exists to prevent.
      final ids = {
        for (var i = 0; i < 1000; i++) UsageAnalytics.newSessionIdForTest(),
      };
      expect(ids.length, 1000);
    });

    test('resetSession() actually changes the id', () {
      final before = UsageAnalytics.sessionId;
      UsageAnalytics.resetSession();
      expect(UsageAnalytics.sessionId, isNot(before));
    });
  });

  group('queueing', () {
    test('records opens and engagements', () {
      UsageAnalytics.open(Feature.chat);
      UsageAnalytics.engage(Feature.chat);
      expect(UsageAnalytics.queuedCount, 2);
    });

    test('does not re-count staying inside the same feature', () {
      // Sitting in the Bible for an hour is one open, not one per
      // rebuild — otherwise the ranking measures rebuilds, not people.
      UsageAnalytics.open(Feature.libraryBible);
      UsageAnalytics.open(Feature.libraryBible);
      UsageAnalytics.open(Feature.libraryBible);
      expect(UsageAnalytics.queuedCount, 1);
    });

    test('counts a genuine return to a feature', () {
      UsageAnalytics.open(Feature.libraryBible);
      UsageAnalytics.open(Feature.chat);
      UsageAnalytics.open(Feature.libraryBible);
      expect(UsageAnalytics.queuedCount, 3);
    });

    test('engagements are always counted, even repeated ones', () {
      // Ten messages is ten engagements; that is the number that
      // separates a feature people use from one they merely opened.
      for (var i = 0; i < 5; i++) {
        UsageAnalytics.engage(Feature.chat);
      }
      expect(UsageAnalytics.queuedCount, 5);
    });

    test('records nothing before start()', () {
      UsageAnalytics.debugReset();
      UsageAnalytics.open(Feature.home);
      expect(UsageAnalytics.queuedCount, 0);
    });
  });
}
