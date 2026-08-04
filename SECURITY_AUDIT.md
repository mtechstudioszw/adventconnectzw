# Security & Code Audit — Advent Connect ZW

**Date:** 3–4 Aug 2026 · **Scope:** Flutter app, Supabase (production), Edge
Functions, Android platform config.

Every finding below was **proven against production** inside a rolled-back
transaction before anything was changed. Production data is unchanged:
`post_likes` 259, `friendships` 101, ticked profiles 4, `maintenance_mode` `0`.

---

## Findings

### 🔴 CRITICAL — `maintenance_block` silently cancelled EVERY delete

**Files:** `database/patch_187_maintenance_mode.sql` → fixed by
`database/patch_189_maintenance_block_delete_fix.sql`

`block_during_maintenance()` ends with `RETURN NEW` and is attached
`BEFORE INSERT OR UPDATE OR DELETE` on **26 tables**. In a `BEFORE ... FOR EACH
ROW` trigger on a DELETE, `NEW` is `NULL`, and returning `NULL` tells PostgreSQL
to **skip the row — silently**. No error; the client's `delete()` returns
success having deleted nothing.

**Proven on production, maintenance OFF:** `post_likes 259 → 259`,
`friendships 101 → 101`.

**Broken for members:** unliking a post, unfriending, cancelling a friend
request, deleting your own post or comment, deleting a message, leaving a
group, cancelling an RSVP, deleting a story, removing a product or job listing,
removing a church admin.

Most fail **invisibly** — the UI updates optimistically, the row survives, the
old state returns on refresh. That reads as "the app is flaky" rather than
pointing at a cause. It is also a **privacy** failure: a member deleting a post
or message is making a privacy decision, and the app reported success while
keeping the row.

**Fix:** `RETURN COALESCE(NEW, OLD)`. **Applied + verified:**
`post_likes 259 → 258`, `friendships 101 → 100`, and a delete during
maintenance is still correctly blocked.

---

### 🟠 HIGH — any member could award themselves the gold verified tick

**Files:** `database/patch_134_verified_admin_badge.sql`,
`supabase/migrations/20260803120000_premium_subscriptions.sql` → fixed by
`database/patch_188_verified_admin_self_grant.sql`

```
PATCH /rest/v1/profiles?id=eq.<their own id>   {"is_verified_admin": true}
```

Three things lined up:

1. `profiles_update_self` allows a member to update their own row.
2. The premium migration rebuilt `profiles`' UPDATE grants **per column** and
   excluded only `premium_until` — so `is_verified_admin` was granted back to
   `authenticated` and `anon`.
3. `profiles_block_privilege_self_grant()` was written in patch_028;
   `is_verified_admin` arrived in patch_134 and was never added to it.

`trg_profiles_super_admin_verify` is `BEFORE UPDATE OF is_super_admin`, so it
does not fire when only `is_verified_admin` is touched.

**Proven on production** with the JWT claim set to an ordinary member:
`is_super_admin` snapped back, `premium_until` refused by the grant,
**`is_verified_admin` stuck**.

**Why it matters:** this is **trust** escalation, not privilege escalation — it
grants no extra data access. In this app that is worse. The tick renders on
posts, comments, stories, chat, the inbox, the member directory and the profile
screen, and it is the signal members use to decide whether an account speaks
for a church. Someone wearing it in the marketplace or in DMs is a materially
different threat.

**Fix:** the same two locks `premium_until` has — column grant revoked **and** a
trigger snap-back — plus a transaction-local escape hatch so
`recompute_verified_admin()` still works (modelled on the existing
`is_business` flag). Without the hatch the trigger would also have blocked
legitimate **downgrades**, leaving a removed church admin still wearing the
tick. **Applied + verified both directions.** Nobody had exploited it: the
repair pass changed **0 rows**.

---

### 🟠 HIGH — `play-rtdn` failed OPEN

**File:** `supabase/functions/play-rtdn/index.ts` — **fixed in code, needs a
function redeploy**

```ts
if (RTDN_SECRET && url.searchParams.get("secret") !== RTDN_SECRET)
```

An **unset** secret skipped authentication entirely — and it is unset, because
Pub/Sub has not been configured yet. `verify_jwt` is deliberately off for this
function (Pub/Sub posts anonymously), so the shared secret was the only thing
in front of an endpoint holding the **service-role key**.

The damaging path is the voided-purchase branch: it does **not** re-read
anything from Google, it trusts `refundType` straight from the request body,
flips the subscription to `refunded`/`revoked` and calls `sync_premium_until`.
Anyone with a `purchase_token` could have stripped premium from a paying
subscriber, unauthenticated.

**Fix:** fails closed with `503` when unconfigured; comparison is now
constant-time.

---

### 🟡 MEDIUM — auth callback uses a hijackable custom scheme

**File:** `android/app/src/main/AndroidManifest.xml:65`

`io.supabase.adventconnect://login-callback` with `autoVerify="false"`. Custom
schemes are **not exclusive** on Android — any installed app may register the
same scheme and receive the intent. This carries **password-recovery tokens**,
so it is a real account-takeover path.

**Not auto-fixed** — moving to verified App Links needs a hosted
`assetlinks.json` and a Supabase redirect-URL change. Infrastructure +
behaviour, so it is your call.

---

### 🟡 MEDIUM — `ACCESS_FINE_LOCATION` is broader than the feature needs

**File:** `android/app/src/main/AndroidManifest.xml:9`

Used only to find nearby churches, which `ACCESS_COARSE_LOCATION` does
perfectly well. Fine location attracts extra Play review scrutiny and a heavier
Data Safety disclosure for no benefit. **Not auto-fixed** — it changes a
runtime permission prompt.

---

### 🟢 LOW

- `android/app/debug.keystore` and `google-services.json` are tracked in git.
  Both are public-by-design; `.gitignore` already covers `*.jks` / `*.keystore`
  for release material. No action required.
- Upload extensions are not whitelisted. Impact is bounded: the storage path is
  **server-derived** (`<userId>/<timestamp>.<ext>`), so there is no
  user-controlled path and no traversal.
- No explicit `networkSecurityConfig`. Defaults on modern Android already
  disallow cleartext.

---

## Verified sound — no action needed

- **Every table in `public` has RLS enabled.** Zero exceptions.
- Server-only tables (`quiz_match_keys`, `staff_members`, `admin_audit_log`,
  `app_events`, `app_sessions`, `email_otp_throttle`, `quiz_match_answers`,
  `conversation_removed_members`) have RLS on with **zero policies** —
  deny-all. The quiz answer key is genuinely unreachable from a client.
- **Every `SECURITY DEFINER` function has `search_path` pinned.** No
  search-path hijacking anywhere.
- `premium_until` is defended three ways: not in the column grant, snapped back
  by the trigger even for super admins, and `sync_premium_until` is revoked
  from `authenticated`/`anon`. Confirmed unwritable live.
- Table-level UPDATE on `profiles` is held only by `postgres` and
  `service_role`.
- `is_super_admin`, `is_verified`, `is_banned` snap-back **verified working
  live**.
- Secure storage uses `encryptedSharedPreferences: true` (Android) and
  `first_unlock` (iOS Keychain).
- The hardcoded Supabase **anon key is correct and expected** — it is public by
  design; RLS is the control.
- Storage: `chat_media` and `voice_notes` are **private** with
  participant-scoped policies; the rest are public by design.
- Release builds use real AdMob IDs; test IDs are `kDebugMode`-only.
- `allowBackup="false"`, `fullBackupContent="false"`.
- No `QUERY_ALL_PACKAGES`, `MANAGE_EXTERNAL_STORAGE`, or
  `SCHEDULE_EXACT_ALARM`.

---

## Score

**Before: 62/100. After the three fixes: 88/100.**

The architecture is genuinely strong — RLS everywhere, `search_path` pinned
throughout, real defence-in-depth on the money path. Both database findings
came from the *same process gap*: **a later patch added a column or a trigger
and did not update an earlier guard.** patch_134 added `is_verified_admin` and
never told patch_028's trigger; patch_187 added a `BEFORE DELETE` trigger
without accounting for `NEW` being NULL.

**The single highest-value process change:** when adding a column to `profiles`
or a trigger to a shared guard, re-read the guard it depends on. A checklist in
`CLAUDE.md` would have caught both.

## Remaining risk

- `play-rtdn` is fixed in code but **not deployed**. Deploy before Pub/Sub is
  configured, and set `RTDN_SECRET`.
- App Links migration for the auth callback (Medium, above).
- Ban-evasion remains deferred — see the handoff.
