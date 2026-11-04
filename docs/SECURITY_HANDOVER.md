# Security work — what's done, what you need to do (3 Nov 2026)

## Built (in the app, committed)

| What | Where |
|---|---|
| **Two-step login** (authenticator app code after password / Google / Apple). Opt-in from Settings → Account → Two-step verification. It is enforced on every way in through one router guard. | `lib/services/two_step_service.dart`, `two_step_challenge_screen.dart`, `two_step_setup_screen.dart` |
| **Phone verification for new accounts.** One number per account. It stays **off** until you switch it on (below). | `phone_verification_service.dart`, `verify_phone_screen.dart`, `tab_shell.dart` |
| **Password reset limit** checked on the server: 3 per email per hour, 10 per network per hour. | `auth_service.dart` + patch 310 |
| **Onboarding country starts blank**; member must choose. | `onboarding_flow_screen.dart` |
| **SDA division** shown on profiles (derived from country). | `lib/config/sda_divisions.dart` |

## Checked — no problem found

- **Edge functions without a sign-in check** (notify-fcm, call-push, play-rtdn, youtube-websub, purge-storage, fetch-advent-news): each needs a secret and refuses when it is missing.
- **Storage:** members can only write to their own folders, and private buckets are readable only by chat participants or the owner.
- **`app_config`:** readable by the app, and holds no secrets.

## YOU: step 1 — run two SQL files (Supabase → SQL Editor)

Run these in order. Paste each whole file and click Run.

1. `database/patch_310_security_hardening.sql`
   - Locks 126 database functions away from signed-out callers.
   - Rate limits on 41 more tables (likes, follows, listings, jobs, quiz scores…).
   - Closes the loophole where anyone could lock another member out of messaging.
   - Limits email lookups per network.
2. `database/patch_311_two_step_and_phone.sql`
   - The database refuses chat data to a password-only session when two-step is on.
   - Support reset for a lost authenticator.
   - Phone-verification rules (off by default).
   - 50 MB / 20 MB caps on chat file uploads, which had no limit before.

After running them, open the app and check that chat, posting and sign-in work. If anything breaks, tell me what the error says.

## YOU: step 2 — Supabase dashboard (5 minutes, free)

Go to **Authentication → …**:

- **Sign In / Providers → Email → "Prevent use of leaked passwords"**: ON. This blocks passwords known from data breaches. *(Pro plan feature.)*
- **Rate Limits:**
  - Emails sent: 30/hour.
  - Token verifications: 30 per 5 min per IP.
  - Sign-ups and sign-ins: 30 per 5 min per IP.
  - SMS: 10/hour to start.
- **Multi-Factor:** make sure TOTP is **Enabled** (it is by default).
- **Bot protection (CAPTCHA):** not switched on yet, because the app would also need a CAPTCHA widget on the sign-up screen. Hold this for now. With rate limits plus phone verification, bots are already expensive.

## YOU: step 3 — phone verification for EVERY account (your decision, 4 Nov)

What happens when you switch it on:
- Every account without a verified phone sees only the "Verify your phone" screen.
- It gets no notifications and no incoming calls, and the database refuses its posts, messages, likes and so on, until it verifies.
- One number can verify only one account.
- Exempt: super admins and the Apple review account.

**Cost (checked 4 Nov):** 856 accounts, 248 active in the last 30 days, 0 verified.
- If everyone verifies: about 860 texts, roughly US$170–350.
- More likely, about the 250 active members: roughly US$50–100.
- After that, only new sign-ups and re-sends.

**Be honest with yourself about the risk:**
- Some real members will leave rather than verify.
- Members abroad, or on numbers that don't receive SMS reliably, can get stuck. They will call you.

**Do these in this order.** Switching the flag on before Twilio works locks EVERYONE out.

1. **Create a Twilio account.** Buy a number or a Messaging Service.
2. **Twilio → Messaging → Geo permissions:** allow ONLY the countries your members are in. This stops "SMS pumping" fraud.
3. **Supabase → Authentication → Sign In / Providers → Phone:** enable it, choose Twilio, and paste the SID, token and Messaging Service SID.
4. **Supabase → Authentication → Rate Limits:** set SMS to about 30/hour.
5. **Make sure patch 311 has been run** (step 1).
6. **Wait until the update with the verify screen is live on both stores.** Then raise `min_build_android` / `min_build_ios` in `app_config` to that build. Otherwise people on old versions have no screen to verify with.
7. **Test with your own non-admin account first.** Switch it on, verify your own phone, and check posting and notifications work.
8. **Switch it on:**
   ```sql
   update app_config set value = 'true' where key = 'require_phone_verification';
   ```

**To switch it off instantly:** set it to `'false'`. Every account works again on its next app open.

**Gentler option, if you change your mind:** exempt older accounts by setting `phone_verification_cutoff` to a date, e.g. `'2026-11-10T00:00:00Z'`. Then only accounts created after that date must verify.

## CAPTCHA (bot check) — Cloudflare Turnstile, free

The app is ready for it, but it stays off until you do these steps.
- When it's on, most people just see "Quick security check" for a second. Suspicious traffic gets a checkbox.

**Do these in this order:**

1. **Cloudflare → Turnstile → Add widget:**
   - Name: Adventist Super App.
   - Hostname: `adventconnectzw.com`.
   - Mode: **Managed**.
   - Copy the **Site key** and the **Secret key**.
2. **Wait until the new app version is live** (the one with this feature).
3. **Supabase → SQL Editor:**
   ```sql
   insert into app_config(key, value, updated_at)
   values ('captcha_site_key', '<SITE KEY>', now())
   on conflict (key) do update set value = excluded.value, updated_at = now();
   ```
   - The app now runs the check before sign-up, sign-in, Google/Apple sign-in, password reset and code re-send.
   - Nothing breaks yet: Supabase ignores the token until step 5.
4. **Test on your own phone.** Sign out, sign in, and check that "Quick security check" finishes by itself.
5. **Raise the minimum build** (`min_build_android` / `min_build_ios`) to this version.
6. **Supabase → Authentication → Bot and Abuse Protection** (some dashboards call it "Attack Protection") **→ Enable CAPTCHA protection:**
   - Provider: Turnstile.
   - Paste the **Secret key**, then save.

**Do not do step 6 early.** From that moment, Supabase rejects every sign-in that has no token. Anyone on an older app version can't sign in or sign up until they update.

**To turn it off:** switch the CAPTCHA off in Supabase first, then set `captcha_site_key` to `''`.

## Support: a member lost their authenticator phone

1. Confirm it's really them (ask them to email from their account address, or video-call).
2. Then, signed in to the app as super admin, ask me to wire a button, or run this in the SQL Editor:
   ```sql
   delete from auth.mfa_factors where user_id = '<their user id>';
   ```
   **Easier (after patch 311):** open their profile in the app (as super admin) → ⋯ → **Reset two-step login**.

## Still on your list from before

- Rotate the leaked Google service-account key: create a new key → put it in the GitHub secret `PLAY_SERVICE_ACCOUNT_JSON` → delete the old key.
- Do the two-phone call test on the newest internal build.
- Advent AI needs a new Gemini key.
