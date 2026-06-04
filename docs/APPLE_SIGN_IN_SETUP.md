# Sign in with Apple — finish-line setup

The **code is already in place** (button on iOS, `AuthService.signInWithApple()`,
the `com.apple.developer.applesignin` entitlement, the `sign_in_with_apple`
dependency). It will **not authenticate** until the three things below are
done, because they all require the paid **Apple Developer Program account**
($99/yr) and the Supabase Apple provider config. Until then the iOS button
shows but returns a friendly error — that's expected and harmless.

Do these in order once you have the Apple Developer account + the Mac.

---

## 0. Prerequisites
- Apple Developer Program membership (paid).
- The Mac with Xcode installed.
- `flutter pub get` has been run on the Mac (resolves `sign_in_with_apple`
  + `crypto`), then `cd ios && pod install`.

---

## 1. Apple Developer portal — enable the capability + make a key

1. **developer.apple.com → Certificates, IDs & Profiles → Identifiers.**
2. Open your App ID `io.supabase.adventconnectzw.adventConnectZw`
   (iOS bundle id). Tick **Sign In with Apple** → Save.
3. Still under Identifiers, create a **Services ID** (this is what Supabase
   uses as the OAuth client):
   - Identifier e.g. `io.supabase.adventconnectzw.signin`
   - Enable **Sign In with Apple**, click **Configure**:
     - Primary App ID = the App ID above.
     - **Domains:** `eqbyvasteolqyktbqbem.supabase.co`
     - **Return URLs:** `https://eqbyvasteolqyktbqbem.supabase.co/auth/v1/callback`
4. **Keys → +** → create a key with **Sign In with Apple** enabled.
   Download the `.p8` file (you can only download it ONCE). Note the
   **Key ID** and your **Team ID** (top-right of the portal).

---

## 2. Supabase → Authentication → Providers → Apple

Enable Apple and fill in:
- **Client IDs:** both the **bundle id** (`io.supabase.adventconnectzw.adventConnectZw`)
  AND the **Services ID** from step 1.3, comma-separated. The bundle id is
  what native iOS sign-in presents; the Services ID covers the web/OAuth path.
- **Secret Key (for OAuth):** Supabase generates the client secret from your
  Apple key. Paste the **Team ID**, **Key ID**, the **Services ID**, and the
  contents of the **`.p8`** file into the provider form (Supabase has fields
  for each, or it derives the JWT for you).
- Save.

> The redirect/callback URL Supabase expects is the same one you put in the
> Services ID return URLs:
> `https://eqbyvasteolqyktbqbem.supabase.co/auth/v1/callback`

---

## 3. Xcode — add the capability + signing

1. Open `ios/Runner.xcworkspace` in Xcode (the **workspace**, not the project,
   because of CocoaPods).
2. Select the **Runner** target → **Signing & Capabilities**:
   - Set your **Team** (the paid account). Bundle id stays
     `io.supabase.adventconnectzw.adventConnectZw`.
   - **+ Capability → Sign in with Apple.** (This reads the entitlement
     that's already in `ios/Runner/Runner.entitlements`.)
   - Confirm **Push Notifications** capability is present (for FCM).
3. While here, finish the still-open iOS wiring from the deployment notes:
   - Drag `Runner/PrivacyInfo.xcprivacy` and `Runner/Runner.entitlements`
     into the Runner target if they aren't already referenced (Build Phases →
     Copy Bundle Resources / `CODE_SIGN_ENTITLEMENTS` build setting).
4. For the App Store build, flip `aps-environment` in `Runner.entitlements`
   from `development` to `production`.

---

## 4. Verify

- `flutter run` on a real iOS device (Apple sign-in does **not** work on the
  simulator for the native sheet — use a device).
- Tap **Continue with Apple** → the native sheet appears → choose to share or
  hide email → you land in the app signed in.
- In Supabase → Authentication → Users, confirm a new user with provider
  `apple` was created.

---

## Notes / gotchas
- Apple returns the user's **name only on the very first authorization**.
  `signInWithApple()` already captures it into `user_metadata.full_name`
  on that first sign-in. If you re-test with the same Apple ID, revoke the
  app under **iPhone Settings → your name → Sign in with Apple →
  Advent Connect ZW → Stop Using** to get the name prompt again.
- "Hide my email" gives a private relay address
  (`...@privaterelay.appleid.com`). That's normal and works — just don't
  assume the email is the user's real one.
- Android is unaffected — it never shows the Apple button and keeps Google.
- App Store review: showing Sign in with Apple satisfies Guideline 4.8.
  Keep it at least as prominent as Google (it's placed above Google in the
  UI already).
