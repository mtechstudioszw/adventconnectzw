# Auth email delivery — production setup checklist

## Symptom
Sign up requests the 6-digit verification code, but the email never
arrives.

## Root cause
Supabase ships a built-in SMTP relay for free projects that is **rate
limited to a handful of emails per hour** and is intended for
development only. Once that quota is hit (or if Supabase deems the
sender suspect), confirmation emails are silently dropped — the API
call still returns 200, but no email goes out.

The Flutter client is wired correctly — `_client.auth.signUp()` and
`_client.auth.resend(type: OtpType.signup)` both work. The bottleneck
is the SMTP provider.

## Fix (Supabase dashboard, ~10 minutes)

1. Sign in to your Supabase project.
2. **Project Settings → Authentication → SMTP Settings → "Enable custom
   SMTP"**.
3. Fill in credentials from a real provider:
   - **Resend** (https://resend.com — recommended, free tier 3k/mo):
     - Host: `smtp.resend.com`
     - Port: `465`
     - Username: `resend`
     - Password: your Resend API key (starts with `re_`)
   - **Mailgun**, **SendGrid**, **Postmark**, **Amazon SES** all work
     too — any standard SMTP provider.
4. Set the **Sender email** to an address on a domain you've verified
   with the provider (e.g. `hello@adventconnect.zw`).
5. Set the **Sender name** to `Advent Connect ZW`.
6. Save. Resend a confirmation email from the app to verify delivery.

## Why we don't fix this in code
SMTP credentials are infrastructure config; the client can't set them.
The retry / resend UI in `EmailVerificationScreen` already prompts the
user to check spam and resend, which is the right surface for the
client side.

## Related
- `lib/services/auth_service.dart` — `signUp` + `verifySignupOtp`
- `lib/screens/auth/email_verification_screen.dart` — OTP entry UI
- `admin/src/lib/notify/email.ts` — separate transactional email path
  used by the admin panel (already Resend-based)
