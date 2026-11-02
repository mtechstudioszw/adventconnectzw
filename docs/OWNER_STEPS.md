# Your steps — what only you can do

Last updated 2 Nov 2026. In order of importance. Tick them off as you go.

---

## 0. Android builds to Play internal testing — SET UP (2 Nov 2026)

GitHub → Actions → **Build AAB (Play Store)** → Run workflow → Run.
It builds, tests and uploads to Internal testing by itself (~30 min).

## 1. Database patches — DONE (2 Nov 2026)

297, 292, 299 and the VACUUM lines are applied and verified. The
database went from 396 MB to 333 MB and now prunes itself nightly. Only
patch 295 is left (step 4).

## 2. Check the iPhone build (iPhone, after App Store approval)

The iPhone build now runs only when you start it, because Mac minutes cost
10× on GitHub.

1. GitHub → **Actions** → **iOS build and release validation**.
2. Click **Run workflow**, leave both boxes unticked, then **Run**.
3. If it goes red, tell Claude.

The Android build is already checked: it passed on 2 Nov with every change.

## 3. Make calls work

- [ ] **TURN relay** (without it, calls on mobile data mostly fail):
  1. Cloudflare dashboard → **Realtime → TURN → Create key**.
  2. Supabase → **Edge Functions → Secrets**. Add:
     - `CLOUDFLARE_TURN_KEY_ID`
     - `CLOUDFLARE_TURN_API_TOKEN`
- [ ] **Play Console → App content → Full-screen intent**: declare
  "calling". Also declare the **phone-call foreground service** if Play
  asks.
- [ ] **iPhone calls: APNs VoIP key.** iPhone only: after App Store approval.
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

- [ ] **App Store resubmission** (iPhone): checklist and review message in
  `docs/APP_REVIEW_NOTES.md`. Age Rating → None.
- [ ] **Rotate App Store Connect API key `5DP8YVY728`** if the repo was ever
  public (it is in old commits).

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
