# NEXT SESSION — Advent Connect ZW

Paste this whole file as the first message of the next session.

---

## Where things stand (3 Aug 2026)

All work is pushed. `main` head: **"Search screen: lift the field and its
content up under the status bar"**. `flutter analyze` is clean apart from
the same **4 pre-existing infos**; **237/237 tests pass** (was 135).

**Shipped this session:** the whole premium subscription (Part 1), the
live-stream thumbnail carry-over (Part 3), the feature-usage analytics
foundation, and a search-screen spacing fix.

Applied to production and verified — **do NOT re-apply**:
`20260803120000_premium_subscriptions.sql`,
`20260803130000_payment_receipt_essential.sql`,
`20260803140000_usage_analytics.sql`.
Deployed: `verify-purchase` v1, `play-rtdn` v1, `notify-fcm` **v17**.

## Read first, before any code

1. `CLAUDE.md` — headers are **FLAT on `palette.scaffoldBg`, never navy**.
2. Memory: `premium-subscription-task`, `admin-console-analytics-findings`,
   `founder-quality-bar`, `motion-must-not-cost-time`,
   `repo-and-environment`, `brief03-open-bugs`.
3. `git -C adventconnectzw log --oneline -12`

## The lesson that keeps paying — please repeat it

**Verify the premise before building.** This session that turned Part 3
from "build a fix" into "already fixed, add a safety net", and it caught
four bugs that would each have failed **silently**:
- a column-level `REVOKE` is **silently ignored** against a table-level
  grant (it returns success and changes nothing);
- `premium_until` was unreadable by clients because SELECT on `profiles`
  is granted **per column** — every user would have read as non-premium;
- search lives at `/home/search`, so matching `/home` first ate it;
- `/library` has **no sub-routes** — its five sections are tabs.

---

# PART A — Web admin console: FULL REBUILD (the big one)

The founder's brief: **replace**, do not upgrade. Enterprise-grade,
mobile-first, comparable to Supabase / Linear / Stripe / Vercel. Used by
**non-technical staff** — no SQL, no jargon, no raw table names.

### Decided already — don't re-ask

- **Web admin only.** The in-app Flutter admin is explicitly out of scope
  ("don't worry abt it").
- **`admin-web/` is the live one**, not the Next.js `admin/`. Git proves
  it: `admin-web/` last touched 7 Jul 2026, `admin/` stale since 22 Jun.
  The old handoff recommended the opposite — it was wrong.

### STILL UNANSWERED — ask on turn one

**Which stack for the rebuild?** This gates everything and a wrong guess
wastes the session. The founder's brief says "Senior Flutter Web
Engineer" and "Material 3", but every app it names as a benchmark
(Supabase, Linear, Stripe, Vercel, Notion, GitHub) is a web app, and the
thing being replaced is a static HTML file.
Recommend **Next.js** (reuse `admin/`'s auth middleware + Tailwind):
Flutter Web has slow first paint, poor text selection and weak
accessibility — all bad for a data console checked on a phone.
Also ask **where it deploys** (no `vercel.json` exists anywhere, and the
Vercel connector is not authorised).

### What the console CAN chart today — and what it cannot

The analytics foundation now exists (`app_events`, `app_sessions`,
`app_features`, + 4 super-admin RPCs), but **it starts empty and fills as
users run the new build.** Expect near-zero data until the next release
is live. Say so rather than shipping charts that look broken.

**Has a real source:** DAU/WAU/MAU + new signups (`admin_active_users_series`),
feature ranking incl. zero-use features (`admin_feature_usage`),
platform + app-version spread (`admin_platform_breakdown`), subscriptions
and conversion (`admin_premium_stats`), content health and the moderation
queue (`admin_overview_stats`, `admin_usage_stats`, existing admin RPCs).

**Has NO source — do not promise these without building them first:**
crash reporting of any kind (Crashlytics data lives in Firebase and is
not queryable from Supabase without a BigQuery export), ad
impressions/clicks/CTR/eCPM/fill rate (AdMob-side only;
`AdImpressionCounter` is device-local and never uploaded), country/city,
session duration and screen time (sessions are recorded but duration is
not yet derived), retention cohorts, bounce rate, and every
infrastructure metric (API requests, DB reads/writes, storage,
bandwidth, edge invocations) — those are Supabase platform metrics, not
application data.
**Tell the founder which of these they actually want built**, because
each is its own piece of work.

### Scale reality

**170 users** (DAU 73 / WAU 104 / MAU 140). Design for legibility at this
size. Pagination and virtualisation still belong in the architecture, but
do not let them shape the UI.

---

# PART B — Events tab redesign + new features

Asked at the very end of the 3 Aug session; **not started, nothing
designed.** `lib/screens/events/events_screen.dart`.

The founder said only "redesign the events tab, add new features", so
**get specifics before building**: which new features, and what is wrong
with the current tab. Apply the same bar as the other redesigns — see
`founder-quality-bar` and `motion-must-not-cost-time`.

Existing surface worth auditing first: `/events` with post/details
screens, `event_rsvps`, `admin_approve_event` / `admin_reject_event`,
and an interstitial ad in `post_event_screen`.

---

# PART C — Finish premium (founder actions, then one short session)

Nothing in the app is blocked; these are Play Console / secrets tasks.

1. **Create the subscription** — Monetise → Products → Subscriptions.
   Suggested ID `premium_monthly`, monthly auto-renewing, **USD $3.00**,
   at least one regional price, **and activate the base plan** (an
   inactive base plan makes the product invisible, which looks exactly
   like a bug). The ID **can never be changed** — if it differs, change
   `BillingConfig.monthlyProductId` (one line).
2. **`GOOGLE_PLAY_SA_JSON`** Supabase secret. Until it is set,
   `verify-purchase` returns 503 `verification_unavailable` **by design**.
3. **Pub/Sub topic + `RTDN_SECRET`** so cancellations and refunds reach
   the app. Push endpoint:
   `https://<ref>.functions.supabase.co/play-rtdn?secret=<RTDN_SECRET>`
4. **Licence tester + a real device.** **Money has never been tested** —
   full APK builds are blocked on this machine. Never call it
   production-ready on tests that never moved money.

---

# Traps already paid for — don't rediscover them

- **A column-level `REVOKE` is SILENTLY IGNORED when the grant is
  table-level.** It returns success. The fix is revoke-at-table then
  re-grant every other column. **UPDATE on `profiles` is now per-column:
  a new profile column is NOT client-writable until granted**, and the
  failure is a swallowed 42501.
- **`suppress_sabbath_notifications()` DROPS** non-essential
  notifications outright during a Sabbath quiet window. Anything that
  must survive belongs in `is_essential_notification`.
- **`CrossAxisAlignment.stretch` on a `Row` inside any scrollable** →
  infinite-height; in release it paints **nothing**, no red box.
- **`Container(alignment:)` gives LOOSE constraints; `CachedImage` gives
  its errorBuilder TIGHT ones.** Use the shared **`UserAvatar`**.
- **A supabase-dart `.upsert()` needs SELECT *and* UPDATE policies.**
  Missing either → 42501, usually swallowed. Prefer an RPC.
- **Fixed height + wrappable text** is the recurring overflow, and it can
  fail **silently** when no Flex is involved.
- **Curves ending in `…Back` overshoot past 1.0** — assert inside `Opacity`.
- **`notifications` has no client INSERT policy, by design.**
- **Publishing into a shared pool as you build it races with disposal.**

# Testing rules

- Screens whose `initState` touches Supabase/Hive/the router need a
  constructor seam: `autoLoad` / `autoNavigate` / `autoPrompt` /
  `autoStart`. Seven exist now (`PremiumScreen` added).
- **A field initializer runs before the seam is consulted** — use a getter.
- **Test at 1.0x / 1.6x / 2.5x system text on a 360dp phone.**
- Screens using `StaggeredReveal` need `pumpAndSettle`, not `pump`, or
  the entrance timers outlive the test.
- **Reproduce before fixing, and let the test correct you.**
- The quiz round screen still has **no test** for the timeout path.

# Environment

- Working dir is the **PARENT** of the repo — use `-C adventconnectzw`;
  **the Bash tool resets cwd between calls.**
- **`python` is NOT installed; `node` v24 is.** **`/tmp` does not exist** —
  use the session scratchpad.
- **CRLF line endings.**
- The Management API `/database/query` returns only the **first** result
  set. Put mutations in a `DO $$ … $$` block.
- **To test against production safely:** do the work in a `DO $$ … $$`
  block that `RAISE`s at the end — everything rolls back and the result
  travels out in the error message. Used five times on 3 Aug.
- **Edge functions: deploy via**
  `POST /v1/projects/{ref}/functions/deploy?slug={slug}` as
  **multipart/form-data**, a `metadata` JSON part plus one `file` part
  per file, paths **relative to the repo root**
  (`supabase/functions/<slug>/index.ts`), so `_shared/*.ts` ships
  alongside. Preserve `verify_jwt` — `notify-fcm` and `play-rtdn` are
  `false` on purpose.
- **Full APK builds are blocked.** Only `flutter analyze`,
  `flutter test`, `flutter build bundle` verify anything.
- **The Supabase PAT is not stored anywhere. Ask for it, never write it
  to a file.** The 3 Aug PAT went through chat and was used for three
  migrations and three function deploys — **it should be rotated; ask
  whether it was.** (The 2 Aug one should have been too.)

---

Start by asking the two open questions — **the admin console stack + where
it deploys**, and **what "new features" the Events tab needs** — then
build Part A.
