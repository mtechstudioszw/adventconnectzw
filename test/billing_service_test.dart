// The purchase state machine, driven by a fake store.
//
// Money cannot be tested on this machine — full APK builds are blocked
// and Play billing needs a real device and a licence tester. So what is
// pinned here is everything EXCEPT the money: the states the screen
// renders from, and the two rules that decide whether a user who paid
// keeps what they paid for.
//
// The rule that matters most, and the one a refactor is most likely to
// break: a purchase is acknowledged to Play ONLY after our server has
// verified it. Acknowledge first and we've told Google we delivered
// something we never granted; never acknowledge and Google refunds the
// user after three days. Both directions are pinned below.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/services/billing/billing_platform.dart';
import 'package:advent_connect_zw/services/billing/billing_service.dart';
import 'package:advent_connect_zw/services/premium_service.dart';

class FakeBillingPlatform implements BillingPlatform {
  FakeBillingPlatform({
    this.available = true,
    this.offerExists = true,
    this.buySucceeds = true,
  });

  bool available;
  bool offerExists;
  bool buySucceeds;

  final _controller = StreamController<List<BillingPurchase>>.broadcast();

  int buyCalls = 0;
  int restoreCalls = 0;
  final List<BillingPurchase> completed = [];

  @override
  BillingStore get store => BillingStore.googlePlay;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<PremiumOffer?> loadOffer(String productId) async => offerExists
      ? PremiumOffer(
          productId: productId,
          title: 'Advent Connect Premium',
          description: 'No ads',
          price: 'US\$3.00',
          currencyCode: 'USD',
          rawPrice: 3.0,
          native: 'fake-product',
        )
      : null;

  @override
  Future<bool> buy(PremiumOffer offer) async {
    buyCalls++;
    return buySucceeds;
  }

  @override
  Stream<List<BillingPurchase>> get purchaseUpdates => _controller.stream;

  @override
  Future<void> restorePurchases() async => restoreCalls++;

  @override
  Future<void> completePurchase(BillingPurchase purchase) async =>
      completed.add(purchase);

  void emit(BillingPurchase purchase) => _controller.add([purchase]);

  @override
  void dispose() => _controller.close();
}

BillingPurchase _purchase({
  PurchaseOutcome outcome = PurchaseOutcome.purchased,
  String? token = 'token-abc',
  bool needsCompletion = true,
}) =>
    BillingPurchase(
      outcome: outcome,
      store: BillingStore.googlePlay,
      productId: 'premium_monthly',
      verificationToken: token,
      orderId: 'GPA.1234',
      needsCompletion: needsCompletion,
    );

void main() {
  // Secure storage has no plugin under test; PremiumService catches that
  // and carries on. Initialising the binding keeps the failure a clean
  // MissingPluginException instead of a wall of binding advice.
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeBillingPlatform store;

  /// Waits for the async verify → acknowledge → refresh chain that a
  /// stream event kicks off. Several hops deep, so a single microtask
  /// drain isn't enough.
  ///
  /// This used to be a flat 20ms sleep, which is a race: the chain ends in
  /// a secure-storage write that has no plugin under a headless binding, so
  /// how long it takes is down to how fast the machine unwinds a failing
  /// platform channel. On a slow run the assertions landed while the state
  /// was still `verifying` and the whole file went red — a flake that
  /// looked exactly like a regression in whatever had just been changed.
  ///
  /// Now it keeps the same 20ms floor and then waits for the flow to
  /// actually leave its in-flight states, so it can only ever settle MORE
  /// than before, never less.
  Future<void> settle() async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    const inFlight = {
      PremiumFlowState.purchasing,
      PremiumFlowState.verifying,
      PremiumFlowState.loadingOffer,
    };
    for (var i = 0; i < 200; i++) {
      if (!inFlight.contains(BillingService.state.value)) return;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  setUp(() async {
    await BillingService.debugReset();
    PremiumService.debugReset();
    store = FakeBillingPlatform();
    BillingService.debugConfigure(
      platform: store,
      verifier: (_) async => const VerificationResult.success(),
    );
  });

  tearDown(() async {
    await BillingService.debugReset();
    PremiumService.debugReset();
  });

  group('loading the offer', () {
    test('shows the store\'s own localised price', () async {
      await BillingService.loadOffer();
      expect(BillingService.state.value, PremiumFlowState.ready);
      expect(BillingService.offer?.price, 'US\$3.00');
    });

    test('says unavailable rather than showing a dead button when there '
        'is no billing on the device', () async {
      store.available = false;
      await BillingService.loadOffer();
      expect(BillingService.state.value, PremiumFlowState.unavailable);
      expect(BillingService.errorMessage, isNotNull);
    });

    test('says unavailable when Play has never heard of the product', () async {
      // The real-world cause is a base plan left inactive in Play
      // Console, not a bug in the app.
      store.offerExists = false;
      await BillingService.loadOffer();
      expect(BillingService.state.value, PremiumFlowState.unavailable);
    });
  });

  group('buying', () {
    test('fails fast if the sheet cannot even be opened', () async {
      // Otherwise the screen spins forever: no sheet means the purchase
      // stream will never fire.
      store.buySucceeds = false;
      await BillingService.loadOffer();
      await BillingService.buy();
      expect(BillingService.state.value, PremiumFlowState.failed);
      expect(BillingService.errorMessage, isNotNull);
    });

    test('a successful purchase verifies, then acknowledges', () async {
      await BillingService.init();
      store.emit(_purchase());
      await settle();

      expect(store.completed, hasLength(1),
          reason: 'Play refunds an unacknowledged subscription after 3 days');
      expect(BillingService.state.value, PremiumFlowState.success);
    });

    test('a purchase the server rejects is NEVER acknowledged', () async {
      // This is the one that protects the user: leaving it unacknowledged
      // means Play replays it next launch, and refunds them if it truly
      // never verifies. Acknowledging would quietly keep their money.
      BillingService.debugConfigure(
        platform: store,
        verifier: (_) async => const VerificationResult.failure(null),
      );
      await BillingService.init();
      store.emit(_purchase());
      await settle();

      expect(store.completed, isEmpty);
      expect(BillingService.state.value, PremiumFlowState.failed);
    });

    test('a purchase with no receipt is rejected without calling the server',
        () async {
      var verifierCalls = 0;
      BillingService.debugConfigure(
        platform: store,
        verifier: (p) async {
          verifierCalls++;
          return const VerificationResult.success();
        },
      );
      await BillingService.init();
      store.emit(_purchase(token: null));
      await settle();

      expect(BillingService.state.value, PremiumFlowState.failed);
      expect(store.completed, isEmpty);
      // The real verifier short-circuits on an empty token; the fake one
      // stands in for it here, so it must not have been reached.
      expect(verifierCalls, 0);
    });

    test('an out-of-band payment is pending, not premium', () async {
      // Cash and carrier billing are common in Zimbabwe and can take
      // days. The user must not be told they are premium yet.
      await BillingService.init();
      store.emit(_purchase(outcome: PurchaseOutcome.pending));
      await settle();

      expect(BillingService.state.value, PremiumFlowState.pendingPayment);
      expect(PremiumService.isActive, isFalse);
      expect(store.completed, isEmpty);
    });

    test('backing out is cancelled, not an error', () async {
      await BillingService.init();
      store.emit(_purchase(outcome: PurchaseOutcome.cancelled));
      await settle();

      expect(BillingService.state.value, PremiumFlowState.cancelled);
      expect(BillingService.errorMessage, isNull,
          reason: 'changing your mind is not a failure to apologise for');
    });

    test('a store error surfaces as failed with a readable message',
        () async {
      await BillingService.init();
      store.emit(_purchase(outcome: PurchaseOutcome.error));
      await settle();

      expect(BillingService.state.value, PremiumFlowState.failed);
      expect(BillingService.errorMessage, isNotNull);
    });
  });

  group('restore', () {
    test('a restored entitlement is verified like any other purchase',
        () async {
      // A reinstall or a new phone must get premium back without support
      // having to touch anything.
      await BillingService.init();
      store.emit(_purchase(outcome: PurchaseOutcome.restored));
      await settle();

      expect(BillingService.state.value, PremiumFlowState.success);
      expect(store.completed, hasLength(1));
    });

    test('restore asks the store to replay entitlements', () async {
      await BillingService.restore();
      expect(store.restoreCalls, 1);
    });
  });

  group('a purchase already claimed by another account', () {
    test('says so in plain English', () async {
      BillingService.debugConfigure(
        platform: store,
        verifier: (_) async => const VerificationResult.failure(
            'That subscription is already linked to another Advent '
            'Connect account.'),
      );
      await BillingService.init();
      store.emit(_purchase());
      await settle();

      expect(BillingService.state.value, PremiumFlowState.failed);
      expect(BillingService.errorMessage, contains('already linked'));
      expect(store.completed, isEmpty);
    });
  });
}
