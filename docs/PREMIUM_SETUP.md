# Premium — what you need to do (Android)

The code is done and hidden on iPhone. These steps turn it on for
Android. Do them in this order.

## 1. Database

1. Run `database/rehearsal_289.sql` in the Supabase SQL editor. It changes
   nothing: it runs the whole patch plus tests and then fails on purpose
   with `REHEARSAL_OK:...`. Send the message to Claude to check.
   Expected parts: `self_feature=false/null`, `nobiz=BOOST_NEEDS_BUSINESS`,
   `shop_featured=true/true`, `left_after1=3`, `fifth=BOOST_NO_CREDITS`,
   `grant_direct=42501`, `token_rows=1`, `after_lapse product=false
   shop=false`, `biz_daily_min=720`, `plus_daily_min=360`,
   `tiers=business,pro,plus`.
2. Run `database/patch_289_premium_features.sql`.
3. Run `database/patch_290_page_safety.sql`.

## 2. The verify-boost server function

Deploy `supabase/functions/verify-boost` (Supabase dashboard → Edge
Functions, or `supabase functions deploy verify-boost`). Keep "Verify
JWT" ON. It uses the same `GOOGLE_PLAY_SA_JSON` secret as
`verify-purchase` — nothing new to set.

## 3. Google Play Console

Monetize → Products.

**Subscriptions → `premium_monthly` → Add base plan**
- Base plan ID: `business-monthly` (exactly — it can never be changed)
- Auto-renewing, billing period 1 month, price **US$10**, then Activate.

**In-app products (one-time) → Create product**, twice:

| Product ID | Name | Price |
|---|---|---|
| `boost_listing_7d` | Boost a listing (7 days) | US$1 |
| `boost_job_14d` | Feature a job (14 days) | US$2 |

Activate both. IDs must match exactly; they can't be renamed later.

## 4. Levels and prices

| Level | Price | Includes |
|---|---|---|
| Free | – | Ads, 2 h calls/day, 10 AI questions/month |
| Plus | US$3/month | No ads, gold tick (after ID check), 6 h calls, 100 AI |
| Pro | US$5/month or US$30/year | Plus, with 12 h calls and 500 AI |
| Business | US$10/month | Pro + featured shop, 4 listing boosts + 2 featured jobs a month, Page gold tick |

One-off: listing boost US$1 (7 days), featured job US$2 (14 days).

## 5. Running it

- **Gold tick requests:** Settings → Admin → Gold tick requests. Check the
  selfie against the ID and the name against the profile, then approve or
  reject with a reason. The photos are deleted after either decision.
- **Paid placement is always labelled** ("Promoted" in Marketplace,
  "Featured" on jobs, up to 3 pinned).
- **Refunds of boosts** are not reversed automatically yet: if Google
  refunds a boost, it runs to its end date. At US$1–2 that is acceptable
  for now; tell Claude if you want it handled.
