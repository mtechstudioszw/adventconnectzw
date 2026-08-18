// Guards the Sabbath sundown calculation after it went global.
//
// Before the Adventist Super App rebrand this code resolved location as
// `province() ?? 'Harare'` and hardcoded `+2` hours for Africa/Harare at
// both ends of the astronomy. Both assumptions are Zimbabwe-only, so every
// member abroad was shown Harare's sundown — silently, with no error and
// nothing on screen to suggest the time was wrong.
//
// Sabbath times are the one number this audience will not forgive being
// wrong, and the failure is invisible to anyone testing from Zimbabwe.
// Hence these tests.

import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/services/sabbath_service.dart';

void main() {
  // A fixed Wednesday, so "the next Friday" is unambiguous and these
  // assertions don't drift with the calendar.
  final wednesday = DateTime.utc(2026, 8, 19, 10);

  group('sundown is an instant, not Harare wall-clock', () {
    test('nextSabbathStart returns UTC', () {
      final start = SabbathService.nextSabbathStart(from: wednesday);
      expect(start, isNotNull);
      expect(start!.isUtc, isTrue,
          reason: 'callers do .difference(DateTime.now()) and .toLocal()');
    });

    test('it lands on a Friday', () {
      final start = SabbathService.nextSabbathStart(
        from: wednesday,
        overrideProvince: 'Harare',
      )!;
      expect(start.toLocal().weekday, DateTime.friday);
    });
  });

  group('country actually changes the answer', () {
    // The regression that matters. If these ever collapse to the same
    // instant, the country is being ignored again and everyone abroad is
    // back on Harare time.
    test('Zimbabwe and the United Kingdom differ', () {
      final zw = SabbathService.nextSabbathStart(
        from: wednesday,
        overrideCountry: 'ZW',
      )!;
      final gb = SabbathService.nextSabbathStart(
        from: wednesday,
        overrideCountry: 'GB',
      )!;
      expect(zw, isNot(equals(gb)));
      // London in August sets far later than Harare — hours, not minutes.
      expect(gb.difference(zw).inMinutes.abs(), greaterThan(60));
    });

    test('northern and southern hemisphere differ in August', () {
      final ke = SabbathService.nextSabbathStart(
        from: wednesday,
        overrideCountry: 'KE',
      )!;
      final no = SabbathService.nextSabbathStart(
        from: wednesday,
        overrideCountry: 'NO',
      )!;
      expect(ke, isNot(equals(no)));
    });

    test('an unknown country code falls back rather than throwing', () {
      final bogus = SabbathService.nextSabbathStart(
        from: wednesday,
        overrideCountry: 'XX',
      );
      expect(bogus, isNotNull);
    });
  });

  group('Zimbabwe behaviour is unchanged', () {
    // The existing user base is entirely Zimbabwean, so the rewrite has to
    // be a no-op for them.
    test('a Zimbabwean province still wins over the country', () {
      final byProvince = SabbathService.nextSabbathStart(
        from: wednesday,
        overrideProvince: 'Bulawayo',
      )!;
      final byCountry = SabbathService.nextSabbathStart(
        from: wednesday,
        overrideCountry: 'ZW',
      )!;
      // Bulawayo is ~2.4° west of Harare, so it sets measurably later.
      expect(byProvince, isNot(equals(byCountry)));
    });

    test('Harare sundown matches the real world', () {
      final start = SabbathService.nextSabbathStart(
        from: wednesday,
        overrideProvince: 'Harare',
      )!;
      // Friday 21 Aug 2026. Real Harare sunset is ~17:47 SAST = ~15:47Z.
      //
      // This value is the regression guard for the ~2-hour error that
      // shipped for the life of the app: a non-integer `n` (days since
      // J2000) fed into the solar-position terms. Anything that reopens
      // that hole moves this by about two hours, which is exactly the
      // size of mistake nobody notices by eye.
      expect(start.year, 2026);
      expect(start.month, 8);
      expect(start.day, 21);
      expect(start.hour, 15);
      expect(start.minute, closeTo(47, 3));
    });
  });

  group('the ~2-hour regression, pinned per hemisphere', () {
    test('London midsummer sundown matches the real world', () {
      // Friday 19 Jun 2026. Real London sunset ~21:21 BST = ~20:21Z.
      // A second reference, deliberately far from Harare in latitude,
      // longitude and season — one city can agree with a wrong formula
      // by luck; two of these cannot.
      final start = SabbathService.nextSabbathStart(
        from: DateTime.utc(2026, 6, 17, 10),
        overrideCountry: 'GB',
      )!;
      expect(start.day, 19);
      expect(start.hour, 20);
      expect(start.minute, closeTo(21, 3));
    });
  });

  group('the Sabbath window', () {
    test('currentSabbathEnd is null midweek', () {
      expect(
        SabbathService.currentSabbathEnd(
          from: wednesday,
          overrideProvince: 'Harare',
        ),
        isNull,
      );
      expect(
        SabbathService.isSabbathNow(
          from: wednesday,
          overrideProvince: 'Harare',
        ),
        isFalse,
      );
    });

    test('Saturday midday IS inside the Sabbath', () {
      // 22 Aug 2026 is a Saturday. Midday UTC is comfortably between
      // Friday and Saturday sundown for Harare.
      final saturdayNoon = DateTime.utc(2026, 8, 22, 10);
      final end = SabbathService.currentSabbathEnd(
        from: saturdayNoon,
        overrideProvince: 'Harare',
      );
      expect(end, isNotNull);
      expect(end!.isUtc, isTrue);
      expect(end.isAfter(saturdayNoon), isTrue);
      expect(
        SabbathService.isSabbathNow(
          from: saturdayNoon,
          overrideProvince: 'Harare',
        ),
        isTrue,
      );
    });

    test('the window ends on Saturday, not Sunday', () {
      final saturdayNoon = DateTime.utc(2026, 8, 22, 10);
      final end = SabbathService.currentSabbathEnd(
        from: saturdayNoon,
        overrideProvince: 'Harare',
      )!;
      expect(end.toLocal().weekday, DateTime.saturday);
    });
  });
}
