// The plan picker, tested against the prices that are ACTUALLY live in
// Play Console (23 Aug 2026): premium_monthly carries two active base
// plans, `monthly` at US$3.00 and `annual` at US$30.00.
//
// The promo is CALCULATED, not written down: nothing in the app says
// "2 months free". It is derived from the two prices Play returns, so
// the badge cannot disagree with what the member is charged. That makes
// the arithmetic worth pinning — if it drifts, the app advertises a
// discount that is not real, which is a consumer-protection problem
// rather than a cosmetic one.
//
// It also covers the state BEFORE an annual plan exists, because the
// picker has to degrade to a single clean row rather than an empty box.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/screens/premium/widgets/plan_picker.dart';
import 'package:advent_connect_zw/services/billing/billing_platform.dart';
import 'package:advent_connect_zw/theme/app_theme.dart';

/// The live monthly base plan.
const _monthly = PremiumOffer(
  productId: 'premium_monthly',
  title: 'Premium',
  description: 'Monthly',
  price: r'US$3.00',
  currencyCode: 'USD',
  rawPrice: 3.00,
);

/// The live annual base plan.
const _annual = PremiumOffer(
  productId: 'premium_monthly',
  title: 'Premium',
  description: 'Annual',
  price: r'US$30.00',
  currencyCode: 'USD',
  rawPrice: 30.00,
);

/// A member in Harare seeing local currency — the same maths must hold
/// on numbers that are not round dollars.
const _monthlyZwl = PremiumOffer(
  productId: 'premium_monthly',
  title: 'Premium',
  description: 'Monthly',
  price: 'ZWL 45,00',
  currencyCode: 'ZWL',
  rawPrice: 45.00,
);
const _annualZwl = PremiumOffer(
  productId: 'premium_monthly',
  title: 'Premium',
  description: 'Annual',
  price: 'ZWL 450,00',
  currencyCode: 'ZWL',
  rawPrice: 450.00,
);

Future<void> _pump(
  WidgetTester t,
  List<PremiumOffer> offers, {
  PremiumOffer? selected,
  double textScale = 1.0,
}) async {
  await t.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: MediaQuery(
      data: MediaQueryData(
        size: const Size(360, 780),
        textScaler: TextScaler.linear(textScale),
      ),
      child: Scaffold(
        body: SingleChildScrollView(
          child: PlanPicker(
            offers: offers,
            selected: selected ?? (offers.isEmpty ? null : offers.last),
            onSelect: (_) {},
          ),
        ),
      ),
    ),
  ));
  await t.pumpAndSettle();
}

/// Everything painted, flattened.
String _text(WidgetTester t) {
  final b = StringBuffer();
  for (final w in t.widgetList<Text>(find.byType(Text))) {
    if (w.data != null) b.write('${w.data}\n');
  }
  return b.toString();
}

void main() {
  group('both plans live — the real Play Console state', () {
    testWidgets('shows yearly and monthly', (t) async {
      await _pump(t, const [_monthly, _annual]);
      final out = _text(t);
      expect(out, contains('Yearly'));
      expect(out, contains('Monthly'));
      expect(t.takeException(), isNull);
    });

    testWidgets('yearly is listed FIRST, so it anchors', (t) async {
      // The store returns cheapest-first. Showing $3 then $30 makes the
      // annual look expensive; showing $30 then $3 makes the monthly
      // look small. Same two numbers, opposite feeling.
      await _pump(t, const [_monthly, _annual]);
      final yearly = t.getTopLeft(find.text('Yearly')).dy;
      final monthly = t.getTopLeft(find.text('Monthly')).dy;
      expect(yearly, lessThan(monthly),
          reason: 'yearly must be the anchor, above monthly');
    });

    testWidgets('computes "2 months free" from the prices', (t) async {
      // US$30 / US$3 = 10 months paid for out of 12.
      // Nothing hardcodes "2" — change either price and this moves.
      await _pump(t, const [_monthly, _annual]);
      expect(_text(t), contains('2 months free'));
    });

    testWidgets('shows the per-month equivalent', (t) async {
      // US$30 / 12 = US$2.50. Never make a member divide.
      await _pump(t, const [_monthly, _annual]);
      expect(_text(t), contains('2.50'));
    });

    testWidgets('the maths holds in local currency', (t) async {
      // ZWL 450 / ZWL 45 = 10 months paid -> 2 free; 450/12 = 37.50.
      await _pump(t, const [_monthlyZwl, _annualZwl]);
      final out = _text(t);
      expect(out, contains('2 months free'));
      expect(out, contains('37.50'));
    });

    testWidgets('never claims a saving the prices do not support',
        (t) async {
      // An annual priced at 12x monthly saves nothing. Badging it
      // "0 months free" — or worse, "2" — would be a false discount.
      const noSaving = PremiumOffer(
        productId: 'premium_monthly',
        title: 'Premium',
        description: 'Annual',
        price: r'US$36.00',
        currencyCode: 'USD',
        rawPrice: 36.00,
      );
      await _pump(t, const [_monthly, noSaving]);
      expect(_text(t), isNot(contains('months free')));
    });
  });

  group('before the annual plan existed', () {
    testWidgets('one plan collapses to a single row, not an empty box',
        (t) async {
      await _pump(t, const [_monthly]);
      final out = _text(t);
      expect(out, contains(r'US$3.00'));
      expect(out, isNot(contains('Yearly')),
          reason: 'no choice to present with one plan',);
      expect(t.takeException(), isNull);
    });

    testWidgets('no plans renders nothing rather than throwing', (t) async {
      // The store can return nothing — offline, or a Play cache miss.
      // The screen must still paint.
      await _pump(t, const []);
      expect(t.takeException(), isNull);
    });
  });

  group('text scaling on a 360dp phone', () {
    for (final scale in const [1.0, 1.6, 2.5]) {
      testWidgets('two plans survive ${scale}x', (t) async {
        await _pump(t, const [_monthly, _annual], textScale: scale);
        expect(t.takeException(), isNull);
      });
    }
  });
}
