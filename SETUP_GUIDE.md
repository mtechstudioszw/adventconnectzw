# Advent Connect ZW — External setup guide

Everything that has to happen outside the codebase before the app is
shippable. Do the steps in the order below — later steps depend on
artefacts from earlier ones.

**Identifiers you'll need (use verbatim):**

| Platform | Bundle / package id |
| --- | --- |
| Android | `io.supabase.adventconnectzw.advent_connect_zw` |
| iOS     | `io.supabase.adventconnectzw.adventConnectZw` *(camelCase — differs from Android!)* |

---

## Phase 1 — Supabase SQL patches

Open Supabase Dashboard → **Database → SQL Editor → + New query**. For
each file below, paste the contents and click **Run**. All patches
are idempotent — safe to re-run if you're not sure whether one applied.

- [ ] `database/patch_007_job_filled_notify.sql`
- [ ] `database/patch_008_pgcron_scheduled_notifications.sql`
- [ ] `database/patch_009_feedback.sql`
- [ ] `database/patch_010_church_admin_application_fields.sql`

**If patch_008 errors with "extension pg_cron does not exist":**
Sidebar → **Database → Extensions** → search `pg_cron` → toggle on → re-run.

### Verify

```sql
-- Cron jobs registered?
SELECT jobid, jobname, schedule, active FROM cron.job ORDER BY jobid;
-- Expect: enqueue_event_reminders + enqueue_job_expiry_warnings, both active=t.

-- New tables present?
SELECT table_name FROM information_schema.tables
 WHERE table_schema='public' AND table_name IN ('feedback','church_admins');

-- Church_admins has the new columns?
SELECT column_name FROM information_schema.columns
 WHERE table_schema='public' AND table_name='church_admins'
   AND column_name IN ('applicant_name','applicant_phone');
```

---

## Phase 2 — Firebase project (replaces placeholder `google-services.json`)

The committed `android/app/google-services.json` is a **placeholder**
with empty `oauth_client` and a fake API key. Google sign-in and push
notifications cannot work until you replace it with a real one.

### F-1. Create the Firebase project
- [ ] <https://console.firebase.google.com/> → **Add project**
- [ ] Name: `advent-connect-zw`
- [ ] (Optional) Disable Google Analytics if you don't need it
- [ ] Create

### F-2. Register the Android app
- [ ] Project home → Android icon → **Add app**
- [ ] Android package name: `io.supabase.adventconnectzw.advent_connect_zw`
- [ ] Get debug SHA-1:
  ```powershell
  keytool -list -v -keystore $env:USERPROFILE\.android\debug.keystore `
          -alias androiddebugkey -storepass android -keypass android `
          | Select-String "SHA1:"
  ```
- [ ] Paste SHA-1 into Firebase → continue
- [ ] **Download `google-services.json`** → **replace** `android/app/google-services.json`
- [ ] Skip the "Add the Firebase SDK" steps — Flutter has them already

### F-3. Register the iOS app
- [ ] Same project → iOS icon → **Add app**
- [ ] iOS bundle ID: `io.supabase.adventconnectzw.adventConnectZw`
- [ ] **Download `GoogleService-Info.plist`** → save to `ios/Runner/` (drag into Xcode so it joins the target)
- [ ] **Send me the `REVERSED_CLIENT_ID` from that plist** so I can wire it into `ios/Runner/Info.plist` as a URL scheme

### F-4. Add the release SHA-1 (after you generate the upload keystore)

Once you've run `keytool -genkey -v -keystore upload.jks ...` (see
`android/key.properties.example`):

- [ ] Get release SHA-1:
  ```powershell
  keytool -list -v -keystore path\to\upload.jks -alias upload | Select-String "SHA1:"
  ```
- [ ] Firebase → ⚙️ → Project settings → Your apps → Android app → **Add fingerprint** → paste
- [ ] Re-download `google-services.json` → replace local copy

---

## Phase 3 — Web OAuth client (Supabase needs it)

Firebase auto-creates Android + iOS OAuth clients. Supabase needs a
separate **Web** client to validate Google ID tokens server-side.

- [ ] Open Google Cloud Console: <https://console.cloud.google.com/apis/credentials>
- [ ] Project dropdown (top bar) → confirm `advent-connect-zw`
- [ ] **+ Create credentials → OAuth client ID → Application type: Web application**
- [ ] Name: "Supabase auth"
- [ ] **Authorized redirect URIs:** `https://<your-supabase-ref>.supabase.co/auth/v1/callback`
- [ ] Create → **save the Client ID + Client secret** (you'll paste them next)

---

## Phase 4 — Wire Google into Supabase Auth

- [ ] Supabase Dashboard → **Authentication → Providers → Google** → toggle **Enable**
- [ ] Paste the **Web** Client ID + secret from Phase 3
- [ ] Save

**At this point Google sign-in should work** on both login and signup.
Test it before moving to Phase 5.

---

## Phase 5 — Push notifications (FCM)

The Edge Function `supabase/functions/notify-fcm` sends FCM pushes
when rows land in `public.notifications`. Wire it up:

### F-5. Generate the FCM service account
- [ ] Firebase Console → ⚙️ → **Project settings → Service accounts**
- [ ] **Generate new private key** → downloads a JSON file
- [ ] Copy the **entire** JSON contents (you'll paste in F-7)
- [ ] **Delete the downloaded file** once pasted — never commit it

### F-6. Enable the FCM API
- [ ] Google Cloud Console → **APIs & Services → Library**
- [ ] Search "Firebase Cloud Messaging API" → **Enable**

### F-7. Deploy the Edge Function + secret
```powershell
npm install -g supabase
supabase login
supabase link --project-ref <your-supabase-ref>
supabase functions deploy notify-fcm
```
- [ ] Run the commands above
- [ ] Supabase Dashboard → **Project Settings → Edge Functions → Manage secrets**
- [ ] Add `FCM_SERVICE_ACCOUNT_JSON` → paste the JSON from F-5

### F-8. Wire the database webhook
- [ ] Supabase Dashboard → **Database → Webhooks → Create a new hook**
- [ ] Name: `notify-fcm-on-notification-insert`
- [ ] Table: `notifications`
- [ ] Events: ✅ Insert only
- [ ] Type: HTTP Request, POST
- [ ] URL: the URL the `functions deploy` command printed
- [ ] Headers: `Authorization: Bearer <your-service-role-key>`
- [ ] Create

---

## Phase 6 — Release plumbing (for the .aab build)

These don't affect Google sign-in or push, but block the Play Store
release. See `RESUME_NEXT_SESSION.md` for context.

- [ ] **Upload keystore:**
  ```powershell
  keytool -genkey -v -keystore upload.jks -keyalg RSA -keysize 2048 `
          -validity 10000 -alias upload
  ```
  Then: `cp android/key.properties.example android/key.properties` →
  fill in keystore path + password + alias + `admobAndroidAppId`.
- [ ] **AdMob app + 5 banner units** (Home, Churches, Events, Marketplace, Jobs) on the AdMob console. App id → `key.properties`; banner ids → env vars for `scripts/build_release.ps1`.
- [ ] **iOS AdMob app id** — `cp ios/Flutter/AdMob.xcconfig.example ios/Flutter/AdMob.xcconfig` → paste real id.
- [ ] **Launcher icon** — drop a 1024×1024 PNG at `assets/icon/app_icon.png` (+ `app_icon_foreground.png`). Then `dart run flutter_launcher_icons`.
- [ ] **Crashlytics buildtools jar** — first Android release build downloads `firebase-crashlytics-buildtools-3.0.2.jar` from `dl.google.com`. Needs one trip to a fast connection.
- [ ] **Privacy Policy + Terms** hosted publicly — Play Store listing requires URLs.

---

## Verification checklist

After Phases 1–4 are complete, run the app and tap-test:

- [ ] **Google sign-in** on the login screen — Google picker opens, signs in, lands on home
- [ ] **Google sign-up** on the signup screen — same flow, also routes to home
- [ ] **Send feedback** in Settings → submit → green snackbar → row appears in `feedback` table
- [ ] **Sabbath countdown** toggle in Settings → enable → gold chip appears in home greeting
- [ ] **Unclaimed church** — open one → gold info banner above follow button + "Claim it" link below
- [ ] **People to meet** row on home — visible if there's at least one *other* directory member opted in
- [ ] **Change password** in Settings → opens dialog → save → success snackbar
- [ ] **Mark a job as filled** (as the poster) → button works, status changes

After Phase 5 is complete, test push:

```sql
-- Replace UUID with your own auth.users.id (find in Authentication → Users)
INSERT INTO public.notifications (user_id, title, body, type)
VALUES ('YOUR-AUTH-USER-UUID',
        'Test push',
        'If your phone buzzes, FCM works.',
        'general');
```

If your phone buzzes within ~2 seconds, the whole pipeline is wired.

---

## Order recap (the short version)

1. **Phase 1** — Run 4 SQL patches in Supabase
2. **Phase 2** — Create Firebase project + register Android & iOS → replaces placeholder `google-services.json`
3. **Phase 3** — Create Web OAuth client in Google Cloud Console
4. **Phase 4** — Paste Web client into Supabase Auth → Google provider → **sign-in now works**
5. **Phase 5** — Deploy Edge Function + add FCM service account secret → **push now works**
6. **Phase 6** — Release plumbing for the signed `.aab` (keystore, AdMob, icon, privacy/terms)

Each phase is independently testable — finish and verify each before
moving on.
