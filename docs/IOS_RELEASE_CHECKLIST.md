# iOS release checklist

Use this checklist for the first iOS release and every later release. Nothing
here authorizes a change to Android production, Supabase data, or Firebase
data. Check an item only after verifying it in the named system.

## Repository work

- [ ] **Repository work — branch safety:** work only on `ios-preparation` (or
  its reviewed successor); never merge or push directly to `main`.
- [ ] **Repository work — versioning:** `pubspec.yaml` is currently
  `2.0.2+1040`. Preserve Android's release strategy. GitHub Actions supplies
  an iOS build number from its run number; choose a number greater than every
  prior App Store Connect build before uploading.
- [ ] **Repository work — CI:** run `.github/workflows/ios-build.yml` once in
  unsigned mode. It must pass package resolution, CocoaPods, analysis, tests,
  and `flutter build ios --release --no-codesign` on the macOS runner.
- [ ] **Repository work — Firebase:** confirm
  `ios/Runner/GoogleService-Info.plist` is the production iOS file and remains
  a Runner resource. The app initializes Firebase through Flutter; do not add
  PushKit or VoIP handling.
- [ ] **Repository work — notifications:** confirm the Runner entitlement is
  retained and ordinary FCM/APNs notifications work. The distribution profile,
  not source control, determines the production APNs environment.
- [ ] **Repository work — deep links:** retain the exact scheme
  `io.supabase.adventconnect` in `Info.plist`, app links, and routing. Keep
  `flutter_deeplinking_enabled=false`; `app_links` and `go_router` are the
  deliberate single handler.
- [ ] **Repository work — Apple Sign In:** retain the
  `com.apple.developer.applesignin` entitlement and the existing
  `sign_in_with_apple` implementation. Follow `docs/APPLE_SIGN_IN_SETUP.md`;
  do not remove Google or email sign-in.
- [ ] **Repository work — audio:** retain microphone usage text and the
  `audio` background mode for voice notes and library playback. Do not add
  CallKit, PushKit, WebRTC, or calling/video features.
- [ ] **Repository work — StoreKit:** read `docs/IOS_STOREKIT_PREPARATION.md`.
  StoreKit is not implemented yet; keep Google Play Billing and the
  `BillingPlatform` abstraction unchanged until a separately reviewed,
  server-authoritative App Store implementation exists.
- [ ] **Repository work — Appodeal:** verify the Flutter package resolves in
  the macOS CI pod install. Do not add app keys or network credentials to the
  repository.
- [ ] **Repository work — privacy manifest:** review
  `ios/Runner/PrivacyInfo.xcprivacy` against the resolved pods and actual app
  behaviour; update only with evidence from package/vendor documentation.
- [ ] **Repository work — final review:** run `git diff --check`, inspect the
  diff, and ensure no Android, backend, certificate, profile, private-key, or
  credential changes are staged.

## Apple Developer work

- [ ] **Apple Developer work — enrollment:** enroll the owning organization in
  the Apple Developer Program and record the Team ID securely.
- [ ] **Apple Developer work — App ID / bundle ID:** register the explicit App
  ID `io.supabase.adventconnectzw.adventConnectZw` (case-sensitive), matching
  `GoogleService-Info.plist` and the Xcode project. Do not reuse the Android
  application ID.
- [ ] **Apple Developer work — capabilities:** enable Push Notifications and
  Sign in with Apple for that App ID, then regenerate profiles after changing
  capabilities.
- [ ] **Apple Developer work — APNs:** create/configure the APNs credential
  needed by Firebase Cloud Messaging. Do not create a VoIP certificate.
- [ ] **Apple Developer work — signing:** create an Apple Distribution
  certificate and an App Store Connect provisioning profile for the exact App
  ID. Export the certificate with its private key as a password-protected P12;
  keep the P12 and profile outside the repository.

## Firebase work

- [ ] **Firebase work — iOS app record:** add/verify the iOS Firebase app with
  bundle ID `io.supabase.adventconnectzw.adventConnectZw`; download its
  `GoogleService-Info.plist` only from the correct production project.
- [ ] **Firebase work — FCM/APNs:** upload/configure the APNs authentication
  key or certificate in Firebase Console and test foreground, background, and
  terminated ordinary notifications. Verify no notification is configured as
  VoIP.
- [ ] **Firebase work — diagnostics:** verify Analytics and Crashlytics events
  appear from a TestFlight/real-device build, subject to the disclosed consent
  and privacy configuration.

## Supabase work

- [ ] **Supabase work — redirect URLs:** allow
  `io.supabase.adventconnect://` for production authentication callbacks,
  email verification, and password recovery; keep production web redirects
  explicitly reviewed.
- [ ] **Supabase work — Apple provider:** configure Apple as described in
  `docs/APPLE_SIGN_IN_SETUP.md` (Services ID, key, team ID, and redirect URL)
  without committing any Apple private key.
- [ ] **Supabase work — test flows:** verify sign-up/sign-in, email
  verification, password reset, product, job, seller, and event links on a
  physical iPhone.
- [ ] **Supabase work — purchases:** before StoreKit launch, design and review
  server-side receipt/JWS verification and entitlement mapping. Do not grant
  premium from the client or change production database/RLS during iOS prep.

## App Store Connect work

- [ ] **App Store Connect work — app record:** create the app record with the
  exact iOS bundle ID, SKU, primary language, category, and age rating.
- [ ] **App Store Connect work — API access:** request/enable App Store Connect
  API access as required, create a least-privilege key for CI, download its
  `.p8` exactly once, and store it only as a GitHub secret.
- [ ] **App Store Connect work — StoreKit products:** create separately named
  subscription groups/products, pricing, localizations, tax/banking details,
  and sandbox testers. Product IDs, prices, and server verification mapping
  must be explicitly chosen; they are not copied from Google Play.
- [ ] **App Store Connect work — privacy:** complete the privacy nutrition
  labels from observed data collection and third-party SDK behaviour (Firebase,
  Supabase, Appodeal, location, media, analytics, and crash reporting). Do not
  guess answers.
- [ ] **App Store Connect work — account deletion:** provide and test the
  required in-app account-deletion path, including its support/retention
  explanation, before submission.
- [ ] **App Store Connect work — listing:** supply description, keywords,
  support URL, privacy-policy URL, copyright, screenshots for required device
  sizes, and accurate App Review contact/demo instructions.
- [ ] **App Store Connect work — export compliance:** answer export compliance
  from the actual cryptography used by the app and dependencies; do not claim
  an exemption without verification.
- [ ] **App Store Connect work — TestFlight:** upload a signed IPA, wait for
  processing, complete beta review information if required, and test the exact
  processed build.
- [ ] **App Store Connect work — production:** select release timing, submit
  only after all required metadata, privacy, review, and device tests pass.

## Appodeal work

- [ ] **Appodeal work — iOS app:** create/configure the iOS app in Appodeal and
  obtain the iOS app key through the dashboard. Configure only the networks
  approved for this app and territory; keep all network credentials out of Git.
- [ ] **Appodeal work — mediation/privacy:** complete SDK/ad-network privacy,
  ATT/consent, SKAdNetwork, ads.txt, and seller-information requirements using
  Appodeal's current iOS documentation and the actual enabled networks.
- [ ] **Real-device testing — ads:** validate banner, MREC, interstitial, and
  rewarded formats with test ads; verify no production ad is accidentally
  clicked during testing.

## GitHub Actions secrets and release run

- [ ] **GitHub Actions work — signing secrets:** add repository/environment
  secrets `APPLE_CERTIFICATE_P12_BASE64`, `APPLE_CERTIFICATE_PASSWORD`,
  `APPLE_PROVISIONING_PROFILE_BASE64`, `APPLE_PROVISIONING_PROFILE_NAME`, and
  `APPLE_TEAM_ID`. Base64 is storage encoding, not encryption; restrict secret
  access and rotate/revoke compromised material.
- [ ] **GitHub Actions work — optional TestFlight secrets:** add
  `APP_STORE_CONNECT_API_KEY_ID`, `APP_STORE_CONNECT_API_ISSUER_ID`, and
  `APP_STORE_CONNECT_API_PRIVATE_KEY_BASE64` only when CI will upload to
  TestFlight.
- [ ] **GitHub Actions work — unsigned run:** push or open a PR on
  `ios-preparation` and confirm the unsigned job produces its app/log artifact.
- [ ] **GitHub Actions work — signed run:** manually dispatch the workflow with
  `signed_build=true`. It must produce `ios-signed-*`; it fails clearly if
  required signing secrets are absent.
- [ ] **GitHub Actions work — TestFlight run:** only after reviewing the signed
  IPA, manually dispatch with both options enabled to upload. Confirm the
  build appears in App Store Connect before inviting testers.

## Real-device testing and final release

- [ ] **Real-device testing — launch/auth:** cold launch; Apple, Google, and
  email login; logout; session restore; email verification; and password reset.
- [ ] **Real-device testing — links:** Supabase callback plus product, job,
  seller, and event links from Safari, Messages, and a notification.
- [ ] **Real-device testing — permissions:** microphone voice note, camera,
  photo read/save, location, notifications, and Face ID. Confirm each prompt
  describes a feature actually used.
- [ ] **Real-device testing — media/push:** background audio/lock-screen
  controls, audio interruption/recovery, FCM in foreground/background/closed
  states, and Firebase diagnostics.
- [ ] **Real-device testing — purchases:** after StoreKit implementation,
  sandbox purchase, cancellation, restore, renewal, and server-rejection
  flows; also execute an Android purchase regression test.
- [ ] **Production release — final gate:** re-check the final commit, CI
  artifacts, TestFlight build, privacy answers, support channels, and rollback
  plan. Merge to `main` only through the normal reviewed release process.
