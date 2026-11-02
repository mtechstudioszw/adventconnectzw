# Your steps — what only you can do

Last updated 2 Nov 2026. In order of importance. Tick them off as you go.

---

## 1. Free database space (do this week) — patch 292

The database is at **396 MB of the free plan's 500 MB** and grew 4 MB in
a day. When it fills, the app stops saving posts and messages.

1. Open https://claude.ai/artifact/LFRgJx7bKVqR4aqksgJsHr
2. Supabase → your project → **SQL Editor → New query**.
3. Copy each patch, paste it, press **Run**, one at a time, in this order:
   - [ ] **Patch 297**: churches count home-church members only
   - [ ] **Patch 292**: frees space and keeps it free every night
   - [ ] **Patch 299**: nightly clean-up of re-send tables (needs 292 first)
   - [ ] **VACUUM lines**: run each line on its own, last. They hand the
     space back.
4. Then tell Claude **"check patches"**. It confirms each one and reports
   the new size.

## 2. Check the iPhone build — Codemagic (free)

GitHub Actions minutes are used up, and iPhone apps only build on a Mac.

1. Go to **codemagic.io**, then **Sign up with GitHub**.
2. Click **Add application**, pick `adventconnectzw`, choose **Flutter App**,
   then **codemagic.yaml**.
3. Click **Start new build**, then **"iOS build check (unsigned)"**.
4. Wait about 15–20 minutes. If it fails, send Claude the error or a
   screenshot.

There are 500 free minutes a month, enough for about 25 builds. Start one
only after a batch of changes.

## 3. Make calls work

- [ ] **TURN relay** (without it, calls on mobile data mostly fail):
  1. Cloudflare dashboard → **Realtime → TURN → Create key**.
  2. Supabase → **Edge Functions → Secrets**. Add:
     - `CLOUDFLARE_TURN_KEY_ID`
     - `CLOUDFLARE_TURN_API_TOKEN`
- [ ] **Play Console → App content → Full-screen intent**: declare
  "calling". Also declare the **phone-call foreground service** if Play
  asks.
- [ ] **iPhone calls: APNs VoIP key.**
  1. Apple Developer → **Keys → +**, tick Apple Push Notifications.
  2. Put the key in the `call-push` secrets. See `docs/CALLING_SETUP.md`.
- [ ] **Two-phone test** (`docs/CALLING_SETUP.md` §8). Include calling a
  phone whose app is **fully closed**, one phone on Wi-Fi and one on
  mobile data.

## 4. Turn chat encryption on — patch 295 (only after step 3's test)

- [ ] On two phones, send messages, photos and voice notes both ways and
  make sure they all open.
- [ ] Then run **patch 295** from the same copy page.

## 5. Advent AI (switched off since 26 Sep)

Google blocked the old key.

1. Make a new **Gemini API key** in a Google Cloud project in good standing.
2. Supabase → **Edge Functions → Secrets** → `GEMINI_API_KEY` = the new key.
3. Tell Claude. It turns the service back on and checks it.

## 6. Stores

- [ ] **App Store resubmission**: checklist and review message in
  `docs/APP_REVIEW_NOTES.md`. Age Rating → None.
- [ ] **Rotate App Store Connect API key `5DP8YVY728`** if the repo was ever
  public (it is in old commits).
- [ ] **Deploy `verify-boost`**: Supabase dashboard, add `play.ts`
  beside `index.ts`, Verify JWT **on**.

## 7. Housekeeping

- [ ] Publish the website pages in `docs/` (index, privacy, terms,
  guidelines, download, about).
- [ ] Back up the signing files from your old PC somewhere safe, outside
  the repo.
- [ ] On an Android phone, test music:
  - the notification;
  - lock-screen controls;
  - Bluetooth buttons;
  - Bible audio downloads.

---

### Not on your list, on purpose
- **Video calls**: you said voice only.
- **Shona audio Bible**: no free recording exists that we are allowed to use.
- **Human voices for EGW books**: same reason. They use the phone's voice.
