# Major redesign — audit and stage plan

Owner brief: "MASTER PROJECT BRIEF — ADVENTIST SUPER APP MAJOR REDESIGN"
(28 Oct 2026). It supersedes the Batch 2 scope of the 13-batch prompt for
Home, Profile, Marketplace, storefronts, product detail and Jobs. The
13-batch prompt still governs everything else (Library, Bible, Sabbath
School, Hymnal, EGW, Music, Search, Watch, Settings, onboarding, QA).

## Stage 1 — audit (done 28 Oct 2026)

**Stack.** Flutter 3.41.9 / Dart 3.11.5; go_router 14.8.1 with a
`StatefulShellRoute` for the five tabs (Home, Watch, Chat, Marketplace,
Profile — `lib/screens/widgets/tab_shell.dart`); state = static
`ValueNotifier`s in services + StatefulWidgets (no Provider/Bloc — do not
introduce one); Supabase (Postgres + RLS + triggers + storage + edge
functions); Hive cache via `CacheService`; FCM push.

**Design system.** `lib/theme/`: `AppColors` (CLAUDE.md palette),
`AppTextStyles` (Poppins, brightness-aware), `AppSpace`, `AppRadius`,
`AppShadows`, `context.palette` (light/dark surfaces). Ambient field behind
every screen (`AmbientBackground`).

**What exists in the live DB (checked read-only):**

| Brief needs | Exists? | Where |
|---|---|---|
| Posts, likes, comments, views | yes | `posts`, `post_likes`, `post_comments`, `post_views` |
| Friends (mutual) | yes | `friendships` (requester/addressee/status) |
| Followers (one-way, users) | **no** | — |
| Saved posts | **no** | — (`saved_listings` is products only) |
| Hide post / see less | **no** | — |
| Reports with reasons | yes | `reports` + `ReportService` + `showReportSheet` |
| Moderation hide + appeal | drafted | patch_272 (not yet run) |
| Profile: username, bio, cover | yes | `profiles` |
| Profile: website/links, location consent | **no** | — |
| Church association on profile | partial | `profiles.church_id` (one home church); `church_followers` |
| Organization Pages (generic) | **no** | churches only: `churches` + `church_admins` (verified via appointment letter) |
| Sellers / storefronts | yes | `sellers` (cover, logo, delivery, Sabbath notice, verified, featured) |
| Seller ratings/reviews | yes | `seller_ratings` |
| Product reviews | **no** | — |
| Stock quantity | **no** | `products.status` only (available/sold/reserved/removed) |
| Cart | yes (device) | `CartService` (Hive, `pref:cart_v1`) |
| Orders | yes | `orders`, `order_items`, `place_order` RPC (server-priced) — WhatsApp handoff, no payments |
| Jobs | yes | `jobs` (salary_range text, flags, contact) |
| Job applications / saved jobs | **no** | apply = WhatsApp / call / email / in-app chat |
| Company profiles | **no** | `jobs.company` is free text |
| Premium | yes (ad-free) | `subscriptions`, `profiles.premium_tier/_until`, Play billing |
| Entitlements / promotion | **no** | `sellers.featured`, `products.is_featured` flags only |
| Verification | partial | `profiles.is_verified`, `is_verified_admin` (church admins), `sellers.verified/sda_verified` |

**Root cause — own post missing from own Home feed.** Not a data bug:
`HomeScreen._loadCritical` and `_loadMore` filter out
`p.authorId == viewerId` on purpose ("they already see them in Profile →
Posts"), and `_openPostComposer` shows "see it on your profile" instead of
inserting the new post. One canonical `posts` row already backs both
surfaces.

**Database constraint.** Structure changes (DDL) need the owner's approval
in the Supabase connector, and that prompt has timed out four times. Every
stage that needs schema ships a `database/patch_NNN_*.sql` for the owner
to run in the SQL editor; app features depending on it say so until it runs
(never fake success). Plain data writes do work from the session.

## Stages

| # | Stage | Needs DB patch | Status |
|---|---|---|---|
| 1 | Audit + design foundation (tokens, remove dots/outlines/glow noise) | no | done (quiet field); tokens continue per stage |
| 2 | Shared post card + menu: own posts in Home, Save (+ Saved screen), Hide, Copy link, Report; feed/profile consistency; comment reply-to-reply | **patch_273** saved_posts, hidden_posts | code done (Unfollow added in stage 3) |
| 3 | Profile redesign + followers (one-way) alongside friends; privacy | **patch_274** follows, profile links/privacy | code done (shared `ProfileHeader`, follow lists + requests, Edit profile link + private toggle, post-menu Follow/Unfollow, notification routing); waits on patch_274 |
| 4 | Organization Pages (create/manage/follow), church associations | **patch_275** pages, page_admins, page_follows; migrate churches carefully (no auto-migration) | |
| 5 | Marketplace discovery: sections, server-side search/filters/pagination, deterministic ranking + exploration, labelled sponsorship | maybe (indexes, ranking view) | |
| 6 | Product detail, storefront, seller tools, product form, cart/checkout review | maybe (stock, product reviews) | |
| 7 | Jobs: landing, detail, stepped posting form, saved jobs, applications, company profiles | **patch_27x** saved_jobs, job_applications, companies | |
| 8 | Premium foundations: entitlements table, promotion records — **no prices** | **patch_27x** entitlements, promotions | |
| 9 | QA: tests, analyze, renders of every redesigned screen | no | |

## Rules carried from the owner

- No sixth tab. Watch and Chat stay as they are.
- No fabricated data, buttons that do nothing, or local-only Save.
- Paid ≠ verified. Promotion never bypasses moderation; prices unset.
- Don't delete or silently migrate existing relationships/verification.
- Existing ad-free Premium (Play billing) keeps working untouched.

## Stage 3 notes

- Friends and followers are separate. Friends stay mutual (`friendships`,
  untouched). Following is one-way; a private account (`profiles.is_private`)
  approves each follower. `is_discoverable` is unchanged and still means
  "hide my whole profile from strangers".
- Before patch_274 runs, the app keeps working: profiles load without the
  new columns (`UserProfileService.fetch` falls back), Follow buttons and
  follower counts are left out, and Edit profile hides Website / Private
  account. Nothing pretends to work.
- postgrest 2.7 loses the Postgres error code on `.maybeSingle()` failures
  (it reports the HTTP status). `UserProfileService._isMissingColumn`
  checks the message too — copy that if you write another fallback.
