// The refusal copy carries decisions that are easy to undo by accident,
// because each one looks like a harmless wording tweak:
//
//   * selling to somebody who has already paid,
//   * selling access to a service that is currently down,
//   * dropping the "nothing else changes" line and turning a paywall
//     into a locked door,
//   * baking a US dollar figure into copy that a member in Harare reads.
//
// None of those would fail a build or look wrong in review. They are
// pinned here instead.

import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/screens/advent_ai/ai_gate_copy.dart';
import 'package:advent_connect_zw/services/ai/ai_balance_service.dart';
import 'package:advent_connect_zw/services/ai/ai_tiers.dart';

void main() {
  group('every refusal state', () {
    // ok is excluded: callers check canUse first and never render it.
    final states = AiGateReason.values
        .where((r) => r != AiGateReason.ok)
        .toList();

    test('says something', () {
      for (final r in states) {
        final copy = AiGateCopy.of(r);
        expect(copy.title, isNotEmpty, reason: '$r has no title');
        expect(copy.body, isNotEmpty, reason: '$r has no body');
      }
    });

    test('always carries the reassurance line', () {
      // The single most important line in the file. Without it a paywall
      // in a church app reads as the founder locking the doors.
      for (final r in states) {
        final copy = AiGateCopy.of(r);
        expect(copy.reassurance, isNotEmpty, reason: '$r lost it');
        expect(
          copy.reassurance.toLowerCase(),
          contains('free'),
          reason: '$r must say the rest of the app stays free',
        );
      }
    });

    test('always offers a way out of the sheet', () {
      for (final r in states) {
        expect(AiGateCopy.of(r).secondaryLabel, isNotNull, reason: '$r');
      }
    });

    test('never hardcodes a price', () {
      // The store returns a localised price. A literal "$3" in copy shows
      // the wrong figure to most of the user base.
      for (final r in states) {
        final copy = AiGateCopy.of(r, priceLabel: 'ZWL 45,00');
        final all = '${copy.title} ${copy.body} ${copy.primaryLabel ?? ''}';
        expect(all, isNot(contains(r'$3')), reason: '$r hardcodes a price');
        if (copy.primaryLabel != null) {
          expect(copy.primaryLabel, contains('ZWL 45,00'),
              reason: '$r ignored the localised price it was given');
        }
      }
    });
  });

  group('who may be sold to', () {
    test('a spent free sample is the one state that sells', () {
      final copy = AiGateCopy.of(AiGateReason.outOfFree);
      expect(copy.offersPremium, isTrue);
      expect(copy.benefits, isNotEmpty);
    });

    test('a subscriber who ran out is NOT sold anything', () {
      // They already pay. Showing them a Premium button is insulting and
      // reads as a bug.
      final copy = AiGateCopy.of(
        AiGateReason.outOfAllowance,
        resetsOn: DateTime(2026, 9, 1),
      );
      expect(copy.offersPremium, isFalse);
      expect(copy.primaryLabel, isNull);
      expect(copy.benefits, isEmpty);
    });

    test('a broken service is NOT sold anything', () {
      // Taking money for something that is currently down is the one
      // thing that would genuinely deserve the accusation the founder
      // was worried about.
      final copy = AiGateCopy.of(AiGateReason.serviceSuspended);
      expect(copy.offersPremium, isFalse);
      expect(copy.primaryLabel, isNull);
    });

    test('a blocked account is NOT sold anything', () {
      final copy = AiGateCopy.of(AiGateReason.blocked);
      expect(copy.offersPremium, isFalse);
      expect(copy.primaryLabel, isNull);
    });
  });

  group('tone', () {
    test('declining is never framed as rudeness', () {
      for (final r in AiGateReason.values.where((r) => r != AiGateReason.ok)) {
        final label = AiGateCopy.of(r).secondaryLabel!.toLowerCase();
        expect(label, isNot(contains('no thanks')), reason: '$r');
        expect(label, isNot(contains('no, ')), reason: '$r');
      }
    });

    test('no dark patterns', () {
      const banned = [
        'hurry', 'act now', 'limited time', 'don\'t miss',
        'expires', 'last chance', 'only today',
      ];
      for (final r in AiGateReason.values.where((r) => r != AiGateReason.ok)) {
        final copy = AiGateCopy.of(r);
        final all = '${copy.title} ${copy.body}'.toLowerCase();
        for (final phrase in banned) {
          expect(all, isNot(contains(phrase)), reason: '$r uses "$phrase"');
        }
      }
    });

    test('no Scripture beside a price', () {
      // A verse next to a Buy button reads as using the Bible to sell,
      // and this audience notices. Checked by looking for a chapter:verse
      // reference in any state that has a purchase button.
      final ref = RegExp(r'\b[A-Z][a-z]+\s+\d{1,3}:\d{1,3}\b');
      for (final r in AiGateReason.values.where((r) => r != AiGateReason.ok)) {
        final copy = AiGateCopy.of(r);
        if (!copy.offersPremium) continue;
        expect(ref.hasMatch('${copy.title} ${copy.body}'), isFalse,
            reason: '$r puts a verse next to a price');
      }
    });
  });

  group('the usage nudge', () {
    test('mentions the member\'s own usage when known', () {
      // Self-perception: people infer what they value from what they did.
      // This outperforms any benefit bullet, so it must survive edits.
      final copy = AiGateCopy.of(AiGateReason.outOfFree, used: 8);
      expect(copy.body, contains('8'));
    });

    test('says "time" not "times" for one', () {
      final copy = AiGateCopy.of(AiGateReason.outOfFree, used: 1);
      expect(copy.body, contains('1 time'));
      expect(copy.body, isNot(contains('1 times')));
    });

    test('is simply absent when usage is unknown', () {
      final copy = AiGateCopy.of(AiGateReason.outOfFree);
      expect(copy.body, isNotEmpty);
      expect(copy.body, isNot(contains('null')));
    });
  });

  group('benefits stay in step with the tier', () {
    test('the paywall lists exactly what Premium includes', () {
      // These drifted once already: the paywall still said "No ads
      // anywhere in the app" after that framing had been rewritten.
      expect(
        AiGateCopy.of(AiGateReason.outOfFree).benefits,
        equals(AiTiers.premium.benefits),
      );
    });

    test('"No ads" is never a benefit line on its own', () {
      // A negative benefit — charging to stop an annoyance. The framing
      // is who PAYS for the app, not what gets removed.
      for (final b in AiTiers.premium.benefits) {
        expect(b.toLowerCase().trim(), isNot(equals('no ads')));
        expect(b.toLowerCase().trim(),
            isNot(equals('no ads anywhere in the app')));
      }
      // The surviving line must still explain who funds it.
      expect(
        AiTiers.premium.benefits.any(
            (b) => b.toLowerCase().contains('members like you')),
        isTrue,
        reason: 'the member-funded framing was removed',
      );
    });
  });
}
