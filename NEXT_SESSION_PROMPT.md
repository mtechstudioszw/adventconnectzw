# NEXT SESSION — Advent Connect ZW

Paste this whole file as the first message of the next session.

---

## Where things stand (3 Aug 2026)

All work is pushed. `main` head: **"Founder bug round, announcement
reactions UI, chat settings, offline audit"** (`af93966`).
`flutter analyze` is clean apart from **4 pre-existing infos** in files
nobody touched; **135/135 tests pass** (was 67). `flutter build bundle`
succeeds.

**The whole 2 Aug founder bug round is closed**, including #7 — the watch
notification thumbnails, which turned out to be a deployment gap, not a
code bug. `notify-fcm` is now **v16** and the thumbnail logic is verified
in the live bundle.

Applied to production and verified — **do NOT re-apply**:
`20260802140000_who_can_message.sql`,
`20260802150000_channel_avatar_backfill.sql`.

## Read first, before any code

1. `CLAUDE.md` — headers are **FLAT on `palette.scaffoldBg`, never navy**.
2. Memory: `premium-subscription-task`, `ios-readiness-task`,
   `quiz-arena-decisions`, `chat-settings-decisions`,
   `motion-must-not-cost-time`, `repo-and-environment`.
3. `git -C adventconnectzw log --oneline -12`

## Hard-won lesson from the last session — please repeat it

**Five of thirteen briefs had wrong premises.** The profile avatar was
already fixed, the Bible reader already produced a share image, offline
chat was already fully built, the YouTube avatar bug was not a quota
problem, and #7's code was correct but a month stale in production.
**Verify the premise before building.** It turned several "build this"
tasks into one-line fixes and found a month-old deployment gap nobody
knew about.

---

# PART 1 — Premium subscription (Google Play ONLY)

**iOS is explicitly out of scope this session.** The founder will do iOS
once they have a MacBook and an Apple Developer account. **But abstract
the billing layer anyway** — write it so StoreKit slots in later without
a refactor. Do NOT hardcode Play-specific logic into the UI or the
Supabase schema. See memory `ios-readiness-task`.

$3.00/month auto-renewing subscription that removes **all** ads: banner,
interstitial, app-open, native. Plus a Premium badge, a "Go Premium"
screen of Spotify/Notion quality, and a promo shown at most once per 14
days that never fires during login, typing or checkout.

### Build in this order

1. **`PremiumService` + ad gating.** A `ValueNotifier<bool>`, backed by
   `profiles.premium_until`. Gate every ad surface so it never even
   *requests* an ad (that is the battery win, not just hiding widgets).
   **This ships alone, needs none of the blockers below, and is fully
   testable — start here even if the founder has not finished step A.**
2. **Supabase schema + RLS.** A `subscriptions` table and
   `profiles.premium_until`. Premium must be grantable **only** by the
   server. A client that can write its own premium flag is not a
   subscription, it is a suggestion.
3. **Billing layer** — `in_app_purchase` (not in pubspec yet). Purchase
   stream, pending / cancelled / expired, restore, error handling.
4. **Edge function** — Play Developer API verification + RTDN webhook.
   *Blocked on step B below.*
5. **Premium screen + Profile ⋮ menu entry + badge.**
6. **The 14-day promo** and its suppression rules.

### Ad surfaces to gate (audited 2 Aug)

`lib/widgets/ads/ad_banner.dart`, `lib/widgets/ads/native_ad_card.dart`,
`lib/services/ads/app_open_ad_manager.dart`, the rewarded-ad manager used
by the quiz arena, and interstitials in `post_event_screen`,
`post_job_screen`, `add_product_screen`, `post_advent_news_screen`,
`video_player_screen`.

### STEPS THE FOUNDER MUST TAKE — ask for these at the START

Nothing past step 1 can be finished without these. **Ask on the first
turn so the session is not blocked at the end.**

**A. Create the subscription in Play Console.**
   Monetise → Products → Subscriptions → Create.
   - Product ID: suggest `premium_monthly` (**cannot be changed later**)
   - Base plan: monthly, auto-renewing, **USD $3.00**
   - Add at least one region price, activate the base plan
   - → give the agent the **exact product ID**

**B. Service account for server-side verification.**
   Google Cloud Console → create a service account → grant it Play
   Developer API access → Play Console → Users & permissions → invite it
   with "View financial data" + "Manage orders and subscriptions" →
   download the JSON key → store as a Supabase secret
   (`GOOGLE_PLAY_SA_JSON`). **Never paste it into chat.**

**C. Real-time Developer Notifications.**
   Play Console → Monetisation setup → paste a Pub/Sub topic name. Needed
   so a cancellation or refund reaches the app without polling.

**D. Licence testers.** Play Console → Setup → Licence testing → add the
   founder's Google account. **Money cannot be tested on this machine** —
   full APK builds are blocked and billing needs a real device. The agent
   unit-tests the state machine and widget-tests the screen; **the founder
   runs the purchase pass.**

### Three design questions to ask up front

1. Server-side verification now, or a clearly-labelled insecure v1?
2. **Premium per Google account or per Advent account?** They diverge the
   moment someone signs into the app with a different email than their
   Play account, and it changes the schema.
3. Does premium survive a refund/chargeback grace period, or cut off
   immediately?

**Never call this production-ready on the strength of tests that never
moved money.**

---

# PART 2 — Web admin dashboard: FULL REDESIGN

The founder's words: *"it looks generic"*, *"it doesn't fit on mobile"*,
*"I don't need an upgrade, I need a full redesign"*.

**Who it is for — this drives every decision:** *"it's going to be used
by non-technical people I will hire to manage my app, they don't know
Supabase."* So: no SQL, no jargon, no raw table names, nothing that
assumes the reader knows what RLS is. Every number needs a plain-English
label and a "so what". *"Put almost everything there."*

### FIRST: there are TWO admin apps. Ask which one survives.

- **`admin-web/`** — a single-file static console, `index.html`, 936
  lines / 53KB. Sections: Overview, feedback, moderation, broadcasts.
- **`admin/`** — a **Next.js 14 App Router** app with Tailwind and 7
  sections: dashboard, applications, church-claims, announcements,
  feedback, reports, users.

Maintaining both is why it feels generic — effort is split. **Do not
start until the founder picks one.** Recommend the Next.js app (`admin/`)
as the survivor: it already has routing, auth middleware, server actions
and Tailwind, and a 936-line single HTML file will not carry charts and a
mobile-first layout. Migrate anything `admin-web/` has that `admin/` does
not, then delete `admin-web/`.

### Required: mobile-first

It is currently unusable on a phone. The people being hired will check it
on a phone. **Design for 360dp first**, then scale up — not a desktop
layout squeezed down. Tables must become cards on small screens; nothing
may scroll horizontally.

### Required: analytics with real graphs

The founder wants it to *"feel like my Supabase account"* — charts, not
lists of numbers. It must answer, in plain language:

- **Are people using the app?** DAU / WAU / MAU, new signups, retention.
- **Which features are actually used?** Ranked, per feature: Home feed,
  Chat, Watch, Library (Bible / Sabbath School / Hymnal / EGW / Music),
  Marketplace, Prayer, Quiz, Events, Churches. **Which are most used and
  which are ignored** — that is the founder's literal ask, and it decides
  what gets built next.
- **Is the app crashing, and WHERE?** Crash-free rate over time, and
  crashes grouped **by feature** so a non-technical manager can say "the
  Quiz is broken this week". `firebase_crashlytics` is already a
  dependency — check whether a data source already exists before building
  one.
- Content health: posts, prayers, announcements, marketplace listings.
- Moderation queue: reports, pending claims, applications — with age, so
  nothing rots.

**Check what already exists first.** `admin_overview_stats()` and
`fetchAnnouncementReach` / `church_announcement_reactions` are already
built. There may be more analytics RPCs than expected — see memory
`brief03-open-bugs`, which documents **three** cron jobs nobody knew
about. Grep before writing new SQL.

**Feature-usage tracking may not exist yet.** `AnalyticsService` is in
the Flutter app — audit what it actually records. If per-feature usage is
not being captured, that is a **prerequisite**: instrument the app first,
or the dashboard charts nothing. Say so early rather than building an
empty dashboard.

### UI quality bar — this is the point of the whole task

**"It must look premium."** The founder's bar is the same one the app is
held to: beat the category leader, not match a template. An admin panel
that looks like Bootstrap with a sidebar is a FAILED task here, even if
every number on it is correct. Judge the result against Linear, Vercel,
Stripe and the Supabase dashboard itself — that last one by the founder's
own comparison.

Concretely: a real design system (spacing scale, type scale, one accent),
rounded cards with genuine depth, **motion that tracks the data** —
charts that draw in, numbers that count up, skeletons that match the
shape of what is loading. Dark mode. Accessible. Empty states that
explain themselves rather than showing a bare zero.

**"Cool features"** — the founder asked for these explicitly, so do not
ship a pure port of the old sections. Bring ideas and propose them early.
Worth considering:

- **Live activity feed** — Supabase Realtime, so a manager watches
  signups and posts land as they happen.
- **Compare two periods** — this week vs last, with the delta and
  direction on every tile.
- **Drill-down everywhere** — every number is a link to the rows behind
  it. This is what replaces "go look in Supabase" for people who cannot.
- **Saved views / filters** the hired staff can keep.
- **CSV export** on any table.
- **Global search + a command palette** (⌘K) across users, churches,
  reports, listings.
- **A "needs attention" inbox** — one prioritised queue instead of five
  separate ones, with age so nothing rots.
- **Feature adoption funnel** — opened → used → returned, per feature.
- **Crash spike alert** on the dashboard when a feature's crash rate
  jumps, in plain English.
- **Audit log** — who on staff did what, which matters the moment more
  than one person has access.

Propose the shortlist, get the founder's pick, then build. Do not build
all of them silently.

---

# PART 3 — Small carry-over

**Live-stream pushes still have no thumbnail (20 video ids).**
`youtube-websub` notifies the instant a broadcast starts, *before* the
video row is ingested — so `notify-fcm`'s
`select thumbnail_url from youtube_videos where video_id = …` finds
nothing and the push goes out text-only. Everything else got its
thumbnail when `notify-fcm` was deployed to v16.
**Fix:** have the websub handler upsert the video row (or pass the
thumbnail through in the notification payload) *before* it notifies.
`supabase/functions/youtube-websub/index.ts`. Small, self-contained,
good warm-up task.

---

# Traps already paid for — don't rediscover them

- **`CrossAxisAlignment.stretch` on a `Row` inside any scrollable** →
  "BoxConstraints forces an infinite height"; in release it paints
  **nothing**, no red box.
- **`Container(alignment:)` gives its child LOOSE constraints** (unsized
  image floats, leaving a rim) while **`CachedImage` gives its
  errorBuilder TIGHT constraints** (a bare `Text` paints top-left). Size
  the image; `Center` the fallback. Use the shared **`UserAvatar`**.
- **A supabase-dart `.upsert()` needs SELECT *and* UPDATE policies**, not
  just INSERT. Missing either → 42501, usually swallowed by a `catch`.
  Bit three times. Prefer an RPC.
- **Fixed height + wrappable text** is the recurring overflow source. It
  can fail **silently** when no Flex is involved. Two more were caught
  this way on 2 Aug (144px and 25px).
- **Curves ending in `…Back` overshoot past 1.0** — fine for scale,
  asserts inside `Opacity`.
- **`notifications` has no client INSERT policy, by design.** Anything
  writing one must be SECURITY DEFINER.
- **A share card must render at a FIXED text scale.** It is an image; the
  recipient does not share the sender's font setting.
- **Publishing into a shared pool as you build it races with disposal.**
  That is what silenced the quiz. Stage locally, publish once, and guard
  with a generation counter.

# Testing rules

- Screens whose `initState` touches Supabase/Hive/the router need a
  constructor seam. The convention is `autoLoad` / `autoNavigate` /
  `autoPrompt` / `autoStart`. Six exist now.
- **A field initializer runs before the seam is consulted** —
  `final _client = Supabase.instance.client;` asserts in tests. Use a
  getter.
- **Test at 1.0x / 1.6x / 2.5x system text on a 360dp phone.** This found
  two real overflows on 2 Aug.
- **Reproduce before fixing, and let the test correct you.**
- The quiz round screen has **no test** for the new timeout path — it
  needs an `autoStart` seam. Worth adding.

# Environment

- Working dir is the **PARENT** of the repo — use `-C adventconnectzw` or
  absolute paths; **the Bash tool resets cwd between calls.**
- **`python` is NOT installed; `node` v24 is.** **`/tmp` does not exist**
  — use the session scratchpad.
- **CRLF line endings.** A multi-line find/replace with `\n` will not
  match; normalise to the file's own endings.
- The Management API `/database/query` returns only the **first** result
  set. Put mutations in a `DO $$ … $$` block.
- **To test a trigger against production safely:** do the work in a
  `DO $$ … $$` block that `RAISE`s at the end — everything rolls back and
  the result travels out in the error message. Used successfully on 2 Aug.
- **Edge functions: the raw-body PATCH endpoint is retired and the
  Supabase CLI is NOT installed.** Deploy via
  `POST /v1/projects/{ref}/functions/deploy?slug={slug}` as
  **multipart/form-data** with a `metadata` JSON part
  (`entrypoint_path: "index.ts"`) and a `file` part. Preserve
  `verify_jwt` — `notify-fcm` is `false` on purpose (called by a DB
  trigger).
- **Full APK builds are blocked.** Only `flutter analyze`,
  `flutter test`, `flutter build bundle` verify anything. **Add a render
  test for any screen you touch.**
- **The Supabase PAT is not stored anywhere. Ask for it, never write it
  to a file.** The 2 Aug PAT went through chat and was used for two
  migrations and a function deploy — **it should be rotated; ask whether
  it was.**

---

Start by asking for the Play Console product ID (Part 1 step A) and which
admin app survives (Part 2), so neither half is blocked later. Then build
`PremiumService` + ad gating, which needs no answers at all.
