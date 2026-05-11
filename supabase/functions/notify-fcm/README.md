# notify-fcm — Edge Function

Pushes a Firebase Cloud Messaging notification whenever a row lands in
`public.notifications`. Wires the DB triggers from
`database/patch_002_v4_completion.sql` to the user's phone.

```
DB trigger (RSVP, prayer, message, …)
  └─► INSERT into public.notifications
        └─► Supabase Database Webhook (configured in Studio)
              └─► POST → this Edge Function
                    └─► FCM v1 API → user's device
```

The in-app notification centre also reads from `public.notifications`,
so the inbox and the push notification stay in sync.

## Required secrets

| Secret | How to set | Notes |
| --- | --- | --- |
| `FCM_SERVICE_ACCOUNT_JSON` | Studio → Project Settings → Edge Functions → Manage secrets | Paste the entire Firebase service-account JSON. Never commit. |
| `SUPABASE_URL` | auto-injected | nothing to do |
| `SUPABASE_SERVICE_ROLE_KEY` | auto-injected | nothing to do |

## Deploy

```bash
# Install the Supabase CLI if you haven't already
npm i -g supabase

# Log in (opens a browser tab once)
supabase login

# Link this folder to the project (once per machine)
supabase link --project-ref <YOUR-PROJECT-REF>
# Find the project ref in Studio → Project Settings → General → Reference ID

# Deploy
supabase functions deploy notify-fcm
```

The deploy emits a URL like:

```
https://<project-ref>.supabase.co/functions/v1/notify-fcm
```

Copy that — you'll paste it into the webhook config next.

## Wire the webhook

1. Studio → **Database** → **Webhooks** → **Create a new hook**
2. **Name**: `notify-fcm-on-notification-insert`
3. **Table**: `notifications`
4. **Events**: ✅ Insert only
5. **Type**: `HTTP Request`
6. **HTTP Method**: `POST`
7. **URL**: paste the Edge Function URL from the deploy step
8. **HTTP Headers**: Add one header → key `Authorization` → value `Bearer <your-anon-key-or-service-role>`. The service role is fine — only Supabase calls this URL.
9. Click **Create webhook**

## Test

Run this in the SQL Editor to fake a notification (replace the UUID
with your own auth user id):

```sql
insert into public.notifications (user_id, title, body, type)
values (
  'YOUR-USER-UUID',
  'Test push',
  'If your phone buzzes you are wired up.',
  'general'
);
```

If your phone has the app installed, you should see a banner within ~2
seconds. The row also shows up in the in-app inbox immediately.

## Debugging

- **No push, no error in webhook logs**: the user's `profiles.fcm_token`
  is probably `NULL`. Open the app, sign in, kill it, sign in again —
  `PushService.initialize()` saves the token on every auth event.
- **"FCM service account misconfigured"**: the `FCM_SERVICE_ACCOUNT_JSON`
  secret is empty or malformed. Re-paste from the JSON file.
- **`401 INVALID_ARGUMENT`**: the device token expired or the app was
  uninstalled. Token will refresh automatically next launch.
- **HTTP 405 / 400 in webhook**: the Supabase webhook is hitting the
  wrong endpoint or the JSON body is being mangled. Open the webhook in
  Studio and check the **History** tab.
