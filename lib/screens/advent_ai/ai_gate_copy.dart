import '../../config/platform_flags.dart';
import '../../services/ai/ai_balance_service.dart';
import '../../services/ai/ai_tiers.dart';
import '../../services/billing/billing_config.dart';

/// Every word the member reads when Advent AI will not answer them.
///
/// One file, because these five states are easy to conflate and the cost
/// of conflating them is high. Telling a Premium member "you've used your
/// free messages" when they already pay, or offering to sell a
/// subscription while the service is down, is the kind of mistake that
/// loses a member permanently. Keeping the copy together makes the
/// differences visible.
///
/// ## The persuasion here is deliberate, and deliberately honest
///
///  * **Reframed from buying to supporting.** In a church community
///    "your subscription keeps this free for everyone else" outperforms
///    "unlock premium features", and it is true: Premium income is what
///    pays for the AI other members are sampling.
///  * **Continuity, not loss.** "Keep going", never "you've lost
///    access". The member has not been demoted; they finished a sample.
///  * **What stays free is stated explicitly, every time.** The single
///    most important line in the file. Without it a paywall in a church
///    app reads as the founder locking the doors.
///  * **The real reason is given plainly.** Telling members that each
///    answer costs money persuades this audience better than hiding it.
///
/// ## What is deliberately NOT here
///
///  * **No Scripture beside a price.** A verse next to a Buy button
///    reads as using the Bible to sell, and this audience notices.
///  * **No guilt, no scarcity, no countdowns, no "don't miss out".**
///  * **No hardcoded price.** The store returns a localised price in the
///    member's own currency; a literal "$3/month" baked into copy shows
///    a member in Harare the wrong figure. [priceLabel] is passed in,
///    and [AiTiers]/[BillingConfig] hold the fallback.
///  * **No upsell on [AiGateReason.outOfAllowance] or
///    [AiGateReason.serviceSuspended].** There is nothing to sell a
///    member who has already paid, and selling a subscription for a
///    service that is currently down is indefensible.
class AiGateCopy {
  const AiGateCopy({
    required this.title,
    required this.body,
    required this.reassurance,
    this.primaryLabel,
    this.secondaryLabel,
    this.benefits = const <String>[],
  });

  /// Short headline. Sentence case, no exclamation marks.
  final String title;

  /// The explanation. Two short paragraphs at most.
  final String body;

  /// The "nothing has been taken from you" line. Always shown, always
  /// last, always muted. This is what stops a paywall reading as a
  /// locked door.
  final String reassurance;

  /// The action button, or null when there is nothing honest to offer.
  final String? primaryLabel;

  /// The dismiss button. Never "No thanks" — that frames declining as
  /// rudeness. "Maybe later" leaves the door open without pressure.
  final String? secondaryLabel;

  /// Value points, shown only on a state that may sell.
  final List<String> benefits;

  /// Whether this state shows the Premium call to action at all.
  bool get offersPremium => primaryLabel != null && benefits.isNotEmpty;

  /// The reassurance line, in one place because it must be identical
  /// everywhere. Naming the features matters — a vague "the rest of the
  /// app" is not believed, a list is.
  static const _nothingLost =
      'Everything else stays exactly as it is, free — the Bible, Sabbath '
      'School, the Hymnal, EGW, Quiz, churches, events, chat and the '
      'marketplace.';

  /// Resolve the copy for a gate state.
  ///
  /// [priceLabel] must be the store's localised price where one is
  /// available. [used] is the member's message count this month — when
  /// supplied it opens the sell state, because showing someone what they
  /// actually did persuades far better than any benefit bullet does.
  static AiGateCopy of(
    AiGateReason reason, {
    DateTime? resetsOn,
    String? priceLabel,
    String? basePlanId,
    int? used,
  }) {
    final price = priceLabel ?? AiTiers.premium.priceLabel;

    // iOS: nothing is for sale (no In-App Purchase is configured), so the
    // two states that normally sell Premium say only what happened and when
    // it comes back. No price, no benefits, no mention of Premium.
    if (kHidePayments) {
      if (reason == AiGateReason.outOfFree) {
        return AiGateCopy(
          title: "That's your free questions used",
          body: [
            if (used != null && used > 0)
              "You've studied with Advent AI $used "
                  "${used == 1 ? 'time' : 'times'} this month.",
            'Your free questions come back on ${_monthDay(resetsOn)}.',
          ].join('\n\n'),
          secondaryLabel: 'Got it',
          reassurance: _nothingLost,
        );
      }
      if (reason == AiGateReason.freePoolClosed) {
        return const AiGateCopy(
          title: 'Free questions are all taken today',
          body:
              'We cover a set number of free Advent AI questions each day, '
              "and today's are gone.\n\n"
              'Please try again tomorrow.',
          secondaryLabel: 'Try tomorrow',
          reassurance: _nothingLost,
        );
      }
    }

    switch (reason) {
      // ---------------------------------------------------------------
      //  The sample is finished. The ONE state allowed to sell, shown
      //  straight after a real answer — they have just felt what it does.
      // ---------------------------------------------------------------
      case AiGateReason.outOfFree:
        return AiGateCopy(
          title: "That's your free questions used",
          body: [
            // Their own usage, first, when we know it. Self-perception:
            // people infer what they value from what they did, and this
            // lands harder than anything we could claim.
            if (used != null && used > 0)
              "You've studied with Advent AI $used "
                  "${used == 1 ? 'time' : 'times'} this month.",
            'Every answer costs real money to generate, and we cover that '
                'so anyone can try it. Premium is what keeps it running.',
          ].join('\n\n'),
          benefits: AiTiers.premium.benefits,
          primaryLabel:
    'Go Premium — $price a ${BillingConfig.periodLabelFor(basePlanId)}',
          secondaryLabel: 'Maybe later',
          reassurance: _nothingLost,
        );

      // ---------------------------------------------------------------
      //  Premium, allowance spent. They already pay. Nothing for sale —
      //  just when it returns, and thanks.
      // ---------------------------------------------------------------
      case AiGateReason.outOfAllowance:
        return AiGateCopy(
          title: "You've used this month's questions",
          body:
              "That's a lot of study — thank you for supporting the app.\n\n"
              'Your ${AiTiers.premium.monthlyMessages} questions come back '
              'on ${_monthDay(resetsOn)}.',
          secondaryLabel: 'Got it',
          reassurance: _nothingLost,
        );

      // ---------------------------------------------------------------
      //  They never got a sample — the app-wide daily free pool is
      //  spent. Saying "you've used yours" here would be a lie.
      // ---------------------------------------------------------------
      case AiGateReason.freePoolClosed:
        return AiGateCopy(
          title: 'Free questions are all taken today',
          body:
              'We cover a set number of free Advent AI questions each day, '
              "and today's are gone.\n\n"
              'Try again tomorrow, or go Premium to start straight away.',
          benefits: AiTiers.premium.benefits,
          primaryLabel: 'Go Premium — $price a ${BillingConfig.periodLabelFor(basePlanId)}',
          secondaryLabel: 'Try tomorrow',
          reassurance: _nothingLost,
        );

      // ---------------------------------------------------------------
      //  Provider outage, quota or billing failure — hits Premium too.
      //
      //  NO Premium button. Taking money for something currently broken
      //  is the one thing that would genuinely deserve the accusation
      //  the founder was worried about.
      // ---------------------------------------------------------------
      case AiGateReason.serviceSuspended:
        return const AiGateCopy(
          title: 'Advent AI is resting',
          body:
              'Advent AI is temporarily unavailable. Nothing has been '
              'charged, and any questions you have left are safe.\n\n'
              'Please try again a little later.',
          secondaryLabel: 'Close',
          reassurance: _nothingLost,
        );

      // ---------------------------------------------------------------
      //  Barred for abuse. Plain and unhumiliating — and it says the
      //  rest of their account is untouched, because it is.
      // ---------------------------------------------------------------
      case AiGateReason.blocked:
        return const AiGateCopy(
          title: 'Advent AI is unavailable on this account',
          body:
              'Advent AI has been switched off for this account.\n\n'
              'If you think that is a mistake, send us a message from '
              'Profile → Send feedback and we will look into it.',
          secondaryLabel: 'Close',
          reassurance: _nothingLost,
        );

      case AiGateReason.ok:
        // Never rendered — callers check canUse first. Present so the
        // switch stays exhaustive and a new reason is a compile error
        // rather than a blank sheet.
        return const AiGateCopy(title: '', body: '', reassurance: '');
    }
  }

  /// "1 September" — day and month, no year. A reset date inside the
  /// next few weeks does not need one, and "1 September 2026" reads like
  /// a legal notice.
  static String _monthDay(DateTime? when) {
    if (when == null) return 'the 1st of next month';
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${when.day} ${months[when.month - 1]}';
  }
}