# iOS StoreKit preparation

This document records the iOS purchase work that is intentionally deferred
until an Apple Developer account, App Store Connect products, and a Mac are
available. It does not change the live Google Play purchase flow.

## Current architecture

`lib/services/billing/billing_platform.dart` is the store-neutral boundary.
It already defines both `BillingStore.googlePlay` and `BillingStore.appStore`.
`PlayBillingPlatform` is the sole Play-specific implementation, and returns
unavailable on non-Android platforms. The app UI and premium-state logic must
continue to use the `BillingPlatform` interface rather than importing a store
SDK directly.

Premium entitlement remains server-authoritative. A store purchase only yields
a verification token; the client must not grant premium locally. The existing
Play flow sends the token to `verify-purchase`, waits for server verification,
then completes the store purchase and refreshes `PremiumService`.

## Future iOS implementation

When App Store products are ready, add an `AppStoreBillingPlatform` alongside
`PlayBillingPlatform`. It should:

1. Be selected only on iOS; leave `PlayBillingPlatform` and Android unchanged.
2. Query only App Store Connect product identifiers that have been created and
   approved for sandbox testing.
3. Map StoreKit purchase updates and restores to `BillingPurchase` with
   `BillingStore.appStore`.
4. Send the StoreKit receipt/JWS transaction to a separate, server-authorized
   App Store verification path before calling `completePurchase`.
5. Support Restore Purchases and complete transactions only after verification.

Do not infer an App Store plan from a Google Play base-plan identifier, price,
or display name. The products and verification rules must be explicitly mapped
server-side after approval. No database schema, RLS policy, or production
verification function is changed by this preparation phase.

## External prerequisites

- Apple Developer Program membership and a registered bundle identifier.
- App Store Connect subscription products, localizations, pricing, tax/banking
  setup, and sandbox tester accounts.
- A Mac with Xcode for a real-device StoreKit sandbox build.
- An authorized server-side receipt/JWS verification design. This requires a
  separate review because it affects production backend behavior.

## Required test matrix

Before release, test on a physical iPhone with StoreKit sandbox/TestFlight:

- product discovery and localized prices;
- purchase, cancellation, pending purchase, restore, and renewal;
- interrupted purchase recovery after relaunch;
- server rejection without granting premium;
- successful verification followed by transaction completion;
- an Android Play purchase and restore regression test to confirm the two
  store implementations remain independent.
