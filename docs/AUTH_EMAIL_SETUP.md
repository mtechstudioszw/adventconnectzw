# Auth email delivery — Resend SMTP setup

## Symptom
Sign up shows **"Error sending confirmation email — unexpected
failure"**, or the 6-digit verification code never arrives in the
inbox.

## Root cause
Supabase ships a built-in SMTP relay for free projects that is **rate
limited to ~4 emails per hour** and is intended for development only.
Once that quota is hit (or Supabase's shared sender lands on a spam
blocklist), confirmation emails fail entirely — sometimes silently,
sometimes with the "Error sending confirmation email" you're seeing.

The Flutter client is wired correctly — `_client.auth.signUp()` and
`_client.auth.resend(type: OtpType.signup)` both work. The bottleneck
is the SMTP provider on the Supabase side.

The in-app UI now detects this specific failure and surfaces a
friendlier message so users know it's an infrastructure issue, not
something they did wrong. The real fix is to point Supabase at a real
SMTP provider — Resend is the cheapest reliable option.

---

## One-time setup (≈10 minutes)

### 1. Create a Resend account
1. Go to https://resend.com → sign up (free, 3,000 emails/month).
2. **Domains** → **Add Domain** → enter the domain you want emails to
   come from (e.g. `adventconnect.zw`).
3. Resend lists DNS records you need to add to your domain registrar:
   - 1 SPF (TXT) record
   - 3 DKIM (TXT) records
   - 1 DMARC (TXT) record (recommended, optional)
   Add them at your registrar, wait 5–15 min, click **Verify**.
4. Once the domain is **Verified** in Resend, go to **API Keys** →
   **Create API Key** → name it `supabase-prod` → permission **Sending
   access** → copy the key (starts with `re_…`). **You won't see it
   again** — store it somewhere safe.

### 2. Wire Resend into Supabase
1. Open the Supabase project for Advent Connect ZW.
2. **Project Settings → Authentication → SMTP Settings**.
3. Toggle **Enable Custom SMTP**.
4. Fill in:
   - **Sender email**: `noreply@adventconnect.zw`  *(must be on the
     domain you verified in step 1)*
   - **Sender name**: `Advent Connect ZW`
   - **Host**: `smtp.resend.com`
   - **Port number**: `465`
   - **Username**: `resend`
   - **Password**: the `re_…` API key from step 1
   - **Minimum interval between emails per address**: `60` seconds is
     fine.
5. **Save**.

### 3. Verify it works
1. Open the app on a real device (or emulator with internet).
2. Sign up with a brand-new email address.
3. Within 10 seconds you should see the 6-digit code arrive.
4. If it lands in spam: in Resend, set up the DMARC TXT record from
   step 1.3 to fix that. After 24 h, deliverability tightens up.
5. In Resend's **Logs** tab you'll see every outbound email with
   delivery status — useful for debugging future user reports.

---

## What the app does on its side

If Supabase returns the "Error sending confirmation email" string, the
app now:

1. Maps it to a friendly message: *"We couldn't send the confirmation
   email. Please try again in a moment, or contact support if this
   keeps happening."*
2. Keeps the email entered so the user can retry without re-typing.
3. On the verification screen, the **Resend** button has a 30-second
   cooldown to avoid spamming Resend.

## Related code
- `lib/services/auth_service.dart` — `signUp`, `verifySignupOtp`,
  `_friendlyAuthError` mapping.
- `lib/screens/auth/auth_screen.dart` — unified login / signup
  surface.
- `lib/screens/auth/email_verification_screen.dart` — OTP entry UI.
- `admin/src/lib/notify/email.ts` — separate transactional email
  path used by the admin panel (already Resend-based — use the same
  domain).
