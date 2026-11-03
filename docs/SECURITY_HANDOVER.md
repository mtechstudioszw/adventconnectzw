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

## YOU: step 3 — phone verification (costs money, do it when ready)

Honest note: every SMS costs about **US$0.20–0.40 to Zimbabwe**, paid by you. Bots can also try "SMS pumping" (making you send thousands of texts). So:

1. **Create a Twilio account** and buy a number or Messaging Service.
2. Twilio → **Messaging → Geo permissions**: allow **only** the countries your members are in (Zimbabwe, South Africa, Zambia, Botswana…). This is the main defence against SMS pumping.
3. Supabase → **Authentication → Sign In / Providers → Phone**: enable it, choose Twilio, and paste the Account SID, Auth Token and Messaging Service SID.
4. Turn the requirement on in the SQL Editor:
   ```sql
   update app_config set value = 'true' where key = 'require_phone_verification';
   ```
   - Only accounts created **after you ran patch 311** must verify.
   - Existing members, staff and the Apple review account are exempt.
   - To turn it off again, set it to `'false'`.

## Support: a member lost their authenticator phone

1. Confirm it's really them (ask them to email from their account address, or video-call).
2. Then, signed in to the app as super admin, ask me to wire a button, or run this in the SQL Editor:
   ```sql
   delete from auth.mfa_factors where user_id = '<their user id>';
   ```

## Still on your list from before

- Rotate the leaked Google service-account key: create a new key → put it in the GitHub secret `PLAY_SERVICE_ACCOUNT_JSON` → delete the old key.
- Do the two-phone call test on the newest internal build.
- Advent AI needs a new Gemini key.
