# Resume prompt — Stage 19/20 finish

Paste this into the next Claude Code session in this repo:

---

We're mid-build on Stage 20 from `ADVENT_CONNECT_ZW_MASTER_REFERENCE_V4 (1).md`. Stage 19 (Firebase Analytics + Crashlytics) is fully wired. Stage 20 code is written and committed but **not yet compiled** because `flutter pub get` was hanging on slow internet at end of last session.

## Step 1 — finish dep install

Run `flutter pub get` (I'll do this myself if you ask — bandwidth limited). New packages added to pubspec:

- `firebase_analytics ^11.3.3`, `firebase_crashlytics ^4.1.3` (already resolved last session)
- `google_mobile_ads ^5.3.1`
- `shimmer ^3.0.0`
- `image_cropper ^8.0.2`
- `hive ^2.2.3`, `hive_flutter ^1.1.0`
- `connectivity_plus ^6.1.0`
- `google_sign_in ^6.2.2`
- `local_auth ^2.3.0`
- `geolocator ^13.0.2`

If resolution hangs again, the offender last time was `cached_network_image ^3.4.1` which references a non-existent `cached_network_image_web ^1.3.1`. Already removed from pubspec. If a different conflict appears, surface the conflict line and propose a downgrade.

## Step 2 — analyze + fix

Run `flutter analyze`. Likely remaining issues:

1. **`google_sign_in 6.x` API** — I called `GoogleSignIn().signIn()` / `.authentication` in `lib/services/auth_service.dart::signInWithGoogle()`. If v6 has dropped these (latest is v7 with different API), update to whichever shape pub resolved.
2. **`image_cropper 8.x` API** — I called `_cropper.cropImage(sourcePath:...)` in `lib/services/storage_service.dart`. If v8 changed the signature, fix.
3. **`hive_flutter`** — `Hive.openBox<String>(_boxName)` in `lib/services/cache_service.dart`. Verify.
4. **`connectivity_plus 6.x`** — `onConnectivityChanged` returns `Stream<List<ConnectivityResult>>` in v5+; should be fine but check.

Fix whatever analyze flags. **Do not** add new features in this pass — just make it green.

## Step 3 — test on Android

`flutter run`. Verify:

- App launches without Firebase crash
- AdMob test banner appears at the bottom of Home, Churches, Events, Marketplace, Jobs (Google test ad — small banner)
- Login screen shows the **Continue with Google** button (tap will fail until Supabase Auth → Google provider is configured with the right Android SHA-1; that's a separate setup task)
- Settings → biometric toggle appears (only if device has fingerprint enrolled)
- Churches list — distance sort kicks in after location permission grants
- Offline banner appears when you turn off wifi

## Step 4 — wire what wasn't reached

These were planned but not coded last session. Pick them up in order:

1. **Hive cache hookup.** `CacheService` is built but no service writes to it. Add `CacheService.writeString('feed', jsonEncode(items))` after a successful home-feed load, and read it on cold start in `home_screen.dart._bootstrap()` when `ConnectivityService.isOnline` is false.
2. **Message queue for offline sends.** When `MessagingService.sendMessage` throws on no network, push the payload into a hive box (`outbox`) and have `ConnectivityService.onChanged` trigger a flush.
3. **Distance chip on church cards.** The `Church` model now has `latitude`/`longitude`/`hasLocation`. Update `lib/widgets/church_card.dart` to show `LocationService.formatDistance(...)` when the user's `Position` is available.
4. **Real AdMob IDs.** Currently using Google test IDs in `AndroidManifest.xml`, `Info.plist`, and `lib/services/ads_service.dart`. Replace before release build per Part 24.
5. **Code obfuscation on release.** Per Part 26: `flutter build apk --obfuscate --split-debug-info=build/debug-info`. Add to a release script.

## What's already done (don't redo)

- All 8 Part-30 analytics events wired into their services
- Crashlytics + Firebase error routing in `main.dart`
- AdMob `<meta-data>` in AndroidManifest, `GADApplicationIdentifier` + SKAdNetwork in Info.plist
- Android Gradle plugin for Crashlytics declared in `settings.gradle.kts` + applied in `app/build.gradle.kts`
- iOS permission strings: Camera, Photo, Location, FaceID, Microphone (already had)
- `OfflineBanner` wrapped around the whole app in `main.dart`
- `ImageCropper` square crop on profile photo upload (`storage_service.dart`)
- `_GoogleButton` in `login_screen.dart`
- Biometric toggle row in Settings → Account section (only renders if hardware enrolled)
- Geolocator-based nearest-first sort in `churches_screen.dart` (graceful when permission denied or church has no lat/lng)

## Files added last session

- `lib/services/ads_service.dart`
- `lib/services/analytics_service.dart`
- `lib/services/biometric_service.dart`
- `lib/services/cache_service.dart`
- `lib/services/connectivity_service.dart`
- `lib/services/location_service.dart`
- `lib/widgets/ad_banner.dart`
- `lib/widgets/offline_banner.dart`
- `lib/widgets/shimmer_loaders.dart`
