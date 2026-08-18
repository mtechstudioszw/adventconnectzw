// Turning a typed phone number into something wa.me will open.
//
// Every WhatsApp handoff in the app used to do
// `raw.replaceAll(RegExp(r'\D'), '')` and hand the result straight to
// wa.me, which silently required every seller to type a full international
// number. Someone who wrote their number the way they say it out loud —
// "0778 092 494" — produced wa.me/0778092494, an error page. The marketplace
// has no payment rails, so that link IS the transaction.
//
// The cases below are the ones that actually occur in the sellers table:
// a leading +, a leading 00, a national 0, and a bare number.

import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/config/countries.dart';

void main() {
  group('already international — left alone', () {
    test('a + prefix is stripped to digits', () {
      expect(
        Countries.toWhatsAppDigits('+263 77 809 2494', countryCode: 'ZW'),
        '263778092494',
      );
    });

    test('00 is the other way of writing +, and people use it', () {
      expect(
        Countries.toWhatsAppDigits('00263 77 809 2494', countryCode: 'ZW'),
        '263778092494',
      );
    });

    test('a + number is trusted even when it disagrees with the country', () {
      // The seller typed their country code explicitly; believe them over
      // whatever their profile says.
      expect(
        Countries.toWhatsAppDigits('+254 712 345 678', countryCode: 'ZW'),
        '254712345678',
      );
    });
  });

  group('national format — the bug this exists to fix', () {
    test('a Zimbabwean 0 number gains +263', () {
      expect(
        Countries.toWhatsAppDigits('0778 092 494', countryCode: 'ZW'),
        '263778092494',
      );
    });

    test('a Kenyan 0 number gains +254, not +263', () {
      expect(
        Countries.toWhatsAppDigits('0712 345 678', countryCode: 'KE'),
        '254712345678',
      );
    });

    test('a bare number with no trunk 0 still gains the dial code', () {
      expect(
        Countries.toWhatsAppDigits('778092494', countryCode: 'ZW'),
        '263778092494',
      );
    });

    test('a number that already starts with the dial code is not doubled', () {
      expect(
        Countries.toWhatsAppDigits('263778092494', countryCode: 'ZW'),
        '263778092494',
      );
    });
  });

  group('no country — never guess', () {
    test('a national number is passed through unchanged', () {
      // Guessing would dial a stranger in whichever country we assumed.
      // Passing it through is exactly what the old code did, so this can
      // never make a working number worse.
      expect(Countries.toWhatsAppDigits('0778092494'), '0778092494');
    });

    test('an unknown country code is treated as no country', () {
      expect(
        Countries.toWhatsAppDigits('0778092494', countryCode: 'XX'),
        '0778092494',
      );
    });
  });

  group('nothing usable', () {
    test('empty and whitespace are null', () {
      expect(Countries.toWhatsAppDigits(''), isNull);
      expect(Countries.toWhatsAppDigits('   '), isNull);
    });

    test('letters alone are null, not an empty wa.me link', () {
      expect(Countries.toWhatsAppDigits('call me'), isNull);
    });

    test('a lone + is null', () {
      expect(Countries.toWhatsAppDigits('+', countryCode: 'ZW'), isNull);
    });
  });

  group('phoneHint follows the country', () {
    test('Kenya is offered a +254 example, not +263', () {
      expect(Countries.phoneHint('KE'), startsWith('+254'));
    });

    test('Zimbabwe keeps +263', () {
      expect(Countries.phoneHint('ZW'), startsWith('+263'));
    });

    test('an unknown country falls back to the home country', () {
      expect(Countries.phoneHint(null), startsWith('+263'));
    });
  });

  group('currency choices follow the country', () {
    test('Zimbabwe keeps the three it has always offered', () {
      expect(Countries.currencyChoices('ZW'), ['USD', 'ZWL', 'ZAR']);
    });

    test('Kenya leads with KES and still offers USD', () {
      expect(Countries.currencyChoices('KE'), ['KES', 'USD']);
    });

    test('a USD country is not offered USD twice', () {
      expect(Countries.currencyChoices('US'), ['USD']);
    });

    test('an unknown country gets USD alone rather than a guess', () {
      expect(Countries.currencyChoices('XX'), ['USD']);
      expect(Countries.currencyOf('XX'), isNull);
    });

    test('the list is never empty — the dropdown would assert', () {
      for (final c in Countries.all) {
        expect(
          Countries.currencyChoices(c.code),
          isNotEmpty,
          reason: '${c.code} has no currency to offer',
        );
      }
    });
  });
}
