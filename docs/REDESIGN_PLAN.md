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
| 4 | Organization Pages (create/manage/follow), church associations | **patch_275** pages, page_admins, page_follows, posts.page_id | code done (directory, Page view, create/edit, admins, follow, post as Page, moderation/verify for super admin); waits on patch_275 |
| 5 | Marketplace discovery: sections, server-side search/filters/pagination, deterministic ranking + exploration, labelled sponsorship | **patch_276** (security: seller privilege guard) | code done |
| 6 | Product detail, storefront, seller tools, product form, cart/checkout review | **patch_277** (view counts, server medical-claims rule) | code done |
| 7 | Jobs: landing, detail, stepped posting form, saved jobs, company profiles (via Pages) | **patch_278** jobs guard, apply fields, page_id, saved_jobs, pay, applications, alerts | code done (v2: every kind of work, Quick apply, alerts) |
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

## Stage 4 notes

- **Churches were not migrated into Pages, on purpose.** They keep
  `churches` / `church_admins` (appointment-letter verification) /
  `church_followers`. The brief forbids silent migration and says not to
  remove existing verification before a replacement is ready. The Pages
  directory links to the church directory; `pages.category` refuses
  'church' so nobody can make an unofficial church Page.
- Pages: ministry, school, community, business. Up to 3 per member. Owners
  and editors (`page_admins`); admins are added by @username.
- Verification and hiding are super-admin only (`admin_set_page_state`,
  guard trigger). Paying never verifies.
- Posting as a Page uses `posts.page_id` (validated like church posts).
  `FeedService._readPosts` adds the Page embed and falls back for the
  session if patch_275 isn't there yet, so feeds never break.
- No in-app "Message the Page": Contact uses the Page's public phone /
  WhatsApp / email / website, so an admin's personal account isn't exposed.
- Not done: Page events, Page insights (premium, stage 8), a web share
  preview for Pages (share uses the store link until one exists).
- Churches tab on personal profiles is unchanged: it already shows only
  the member's own church, and following a Page never implies membership.

## Stage 5 notes

- **Security finding (patch_276):** sellers could self-approve, self-verify,
  feature themselves and invent ratings through the API; products could
  self-feature. Live data showed no sign of abuse. "Featured" labels are
  only trustworthy once patch_276 runs — until then there are 0 featured
  rows, so nothing shows.
- Ranking: `MarketRanking` (lib/services/market_ranking.dart). Recency,
  listing quality, new-seller boost (first 21 days), seller rating only
  with 3+ reviews, the viewer's recent categories, and a per-day seeded
  jitter. Same order all day, moves daily. Never follower counts, sales or
  views. Featured is a separate labelled shelf, never mixed in.
- Filters (price, condition, town/province, shop) and search (title,
  description, shop name) run in the query. Sort: best / newest / price.
- Shelves show only with distinct, real content: Featured stores,
  Shops in the community, Featured, Recently viewed (2+, still for sale),
  New arrivals (only when the catalogue has 12+ listings and 3+ are new).
  With 9 live listings today, most shelves correctly stay hidden.
- "Pagination": the query caps at 200 listings and the grid reveals 24 at a
  time. True server pagination needs the ranking in the database (a view
  or RPC) — worth doing once the catalogue passes ~200.

## Stage 6 notes

- Product page: Availability row; seller card shows real rating (or "No
  reviews yet"); "Delivery & payment" card from what the store entered
  (delivery area/fee or collection, payment methods, Sabbath hours) plus
  a line that the app takes no payments; "More from <shop>"; the action
  bar is one row (Message · WhatsApp · Add to basket) without the
  repeated price.
- Storefront: shared flat header (square logo, rating, place, since,
  Products/Reviews counts). The navy slab shown when a shop had no cover
  is gone. Payment methods now shown; "Collection only" when no delivery.
- Basket: each shop's delivery/collection line; "Save for later" moves an
  item into Saved listings. The delivery fee is NOT added to the total —
  it's free text the shop confirms.
- Seller dashboard VIEWS was always 0 (nothing ever incremented
  view_count). patch_277 adds record_product_view (once per buyer per
  listing per day, never the seller); the tile is hidden until there's a
  real view.
- Medical-claims rule now also enforced on the server (patch_277 trigger),
  same word list as lib/utils/medical_claims.dart — keep them in step.
- WhatsApp green: retired from the product page (WhatsApp now lives in the
  Contact sheet in brand blue). The storefront's contact bar is blue too.
- Not done (needs backend that doesn't exist): stock quantities, product
  reviews (only store reviews exist), "Follow store", product variations,
  return policies, real payments. No fake versions were added.

### Product page — premium redesign (28 Oct 2026, owner request)

- Hierarchy instead of a stack of identical cards: gallery → shop line
  (name, tick, rating) → title (22/600, not shouting) → price (30/700) with
  an Available/Sold/Reserved status pill → key facts as quiet chips →
  hairline-separated sections (About this item with Read more, Delivery &
  pickup, Sold by) → More from this shop → Buy safely (tips in a sheet) →
  Report.
- Header: glass buttons over the photo, turning into a solid flat bar
  with the title once the photo scrolls away.
- Full-screen gallery: swipe across every photo, pinch-zoom each.
- One primary action. "Contact" opens a sheet with Message in the app and
  WhatsApp (when the shop has a number) — this also retires the solid green
  WhatsApp button from the page. "Add to basket" morphs to "In basket ·
  View" once added; your own listing shows "Manage in your shop".
- Adaptive colour: a faint wash of the product photo's colour across the
  top of the sheet (CLAUDE.md exception, same limits as the profile glow).

### Product page — adaptive marketplace (28 Oct 2026, owner's brief)

**Audit of what was there.** One template for every product: a 4:5 photo
cropped to cover (cutting heads off portrait shots and sides off landscape
ones), a navy fill when there was no photo, and a generic action bar (an
outlined "Contact" next to a blue gradient box) that looked like default
Material. Screenshots sent earlier also never showed a photo — the test
renderer can't download images — which exaggerated the emptiness.

**Approach** (lib/marketplace/):
- `ProductImageSource` — one provider for the hero and the analysis.
- `ProductTheme` — reads a 48×48 sample of the first photo:
  - outer ring plain → **seamless**: the stage takes that exact colour and
    the photo is shown contained, edge to edge (studio shots float on one
    surface); busy ring → **framed**: the photo sits at its natural aspect
    with soft corners and shadow on a category surface. No cropping.
  - centre (background pixels excluded) → saturation-weighted hue →
    **accent**, darkened/lightened to pass 4.5:1 for its label. Reds/pinks
    and colourless products use the category accent.
  - category looks: botanical, editorial, fashion, tech, home, food,
    general (from category, subcategory and title words).
  - first paint uses the category preset; the photo theme eases in
    (450 ms) — never blocks or flickers; results cached per photo.
- Purchase bar: a "Chat" button (opens the contact sheet) + one solid
  accent pill "Add to basket | $price", which becomes "In basket | View";
  duplicate taps guarded; Sold/Reserved and own-listing states.
- Price set with a small currency mark and small cents.
- Hero photos decoded at screen width, measured and painted from one decode.

**Tested on fixtures** (test_screens/fixtures — generated stand-ins; the
environment can't reach Supabase storage): herbal bottle on white, book on
a desk, dark suit on charcoal, red shoe, silver laptop on white, sofa in a
room, text-heavy flyer, no photo, broken photo, sold + very long title, dark
mode, 360 px width. Engine unit tests: seamless detection, framed busy
photos, backdrop not stolen as accent, red/pink fallback, 4.5:1 for every
preset and 18 hues in both themes, category mapping.

**Not possible with the current data:** variants, sizes, stock counts,
specifications (dimensions, ingredients, author/edition) and sale prices —
products have no such columns. The layout has room for them; adding them
needs a schema change (a later stage), not invented values.

### Storefront — matched to the product page (28 Oct 2026)

- Same language as the product page: a stage band coloured from the shop's
  own logo (or its cover photo, shown as a banner), a rounded sheet with the
  logo breaking its edge, name + tick, category · place, a rating badge only
  with real reviews, description with Read more, fact chips (delivery or
  collection, payment, Sabbath, since), Products grid, Reviews and "The
  person behind the shop" as hairline sections, Buy safely, Report.
- Action bar from the shared kit: Chat (sheet: message in app, WhatsApp,
  call — whichever exist) + one accent pill "WhatsApp the shop" / "Message
  the shop". None for the owner's preview or a closed shop.
- Shared kit: lib/marketplace/market_ui.dart (MarketPill, MarketChatButton,
  MarketActionBar, MarketSection, MarketContactOption, StageHeaderButton,
  PriceText) used by both screens.
- Fixed on both screens: the stage was painted over the sheet (an earlier
  sliver paints over a later one), hiding the logo and the sheet's rounded
  corners — stage and sheet now share one sliver.
- Tested with stand-in logos/covers: white-background leaf logo, black
  monogram, colourful logo, a cover photo, no logo; dark mode; 360 px;
  scrolled header.

## Stage 7 notes (Jobs, 28 Oct 2026)

- **Security first (patch_278).** `authenticated` could update every
  column of its own job: insert straight to 'open' (skipping review), flip
  'rejected' back to 'open', push expires_at years ahead. `jobs_guard()`
  now allows only the real paths: open ⇄ filled, open → closed, renew
  (expired → open with a fresh 30 days); editing the employer, contact,
  apply link, pay or linked Page of a live job sends it back to 'pending'.
- **Bug fixed:** the browse strip's category ids ('teaching', 'health'…)
  never matched what the post form saved ('teaching_education',
  'healthcare'…), so every category chip returned nothing. JobCategory now
  uses the database ids.
- **Landing:** search (role, employer, skill or town — title, company,
  description, requirements, location, province), Shop/Jobs switch,
  country scope, field chips, a Filters sheet (listing type, job type,
  experience, arrangement once patch_278 exists, Sabbath-friendly,
  Adventist institutions) applied in the query, a Saved rail, Latest list.
  Empty state offers "Post a vacancy" and "I'm looking for work".
- **No fake sections.** No "Recommended" or "Featured" — nothing here
  personalises and nothing is paid for. A test checks neither word shows.
- **Detail:** fact tiles, trust note ("written by the poster, not verified
  by the app team — never pay to apply"), About / Requirements / How to
  apply / About the employer. Verified only when the job is linked to a
  verified Page (patch_275); otherwise it reads as the poster's claim.
  Apply sheet lists only the routes the poster gave (link, email,
  WhatsApp, call) plus message in app. Poster identity stays hidden (earlier
  owner decision).
- **Posting:** six steps — listing kind, the role (optionally post as one of
  your Pages), type/experience/arrangement/location, details + pay +
  Sabbath, how to apply (vacancies need at least one route), review. Ends
  on "Waiting for review" with a link to My job posts. Local draft under a
  user-scoped key (`job_post_draft_v1`, no `pref:`, so sign-out clears it).
  Before patch_278 the new fields hide and posting retries without them.
- **My job posts** (/jobs/mine): every listing with its real status — Live,
  Waiting for review, Filled, Ended, Not approved.
- **Not built, on purpose:** in-app applications/CV upload and applicant
  tracking (needs storage for CVs, privacy rules and moderation — a
  separate decision); view/applicant counts (jobs don't record them, so
  showing any number would be invented); featured jobs and pricing.

### Jobs v2 — "accommodate everyone" (28 Oct 2026, owner request)

Owner: the board wasn't used because it was "not effective… generic", and
it should serve "garden boys, house girls … medical … professional".
Honest note given at the time: there are 0 live jobs; design helps trust
and posting, but supply still has to come from people posting.

- **Find work / Hire someone** switch. Hire mode lists members available
  for work (SeekerCard) and one-tap role templates to post a vacancy.
- **Three kinds of work** — Everyday (home & family, building & trades,
  driving, cleaning & security, shops & hospitality), Skilled & medical,
  Professional — narrowing to fields; counts are the jobs actually loaded.
- Quick chips: Start now, Day & casual work, Part-time, Sabbath-friendly,
  Adventist employers, No experience needed, Remote.
- **Structured pay** (amount or range, per hour/day/week/month/year/job,
  currency) — "$15 / day"; also written to salary_range for old builds.
  Pay leads every card; "Pay not stated" when absent (never "Negotiable").
- **Start now** (is_urgent) — the one red chip; its own rail.
- **Quick apply** (job_applications): message + phone; poster notified,
  Applicants screen (Call / WhatsApp / Message / Shortlist / Not selected);
  applicant notified on shortlist only; opening marks "Seen". Real
  applicant count on the job. Max 30 applications/day.
- **Job alerts** (job_alerts): per field + country (+ keyword); one push
  per job when a moderator approves a match. Max 10.
- **My jobs** hub: Applied / Saved / My posts (+ Applicants) / Alerts.
- Posting: role templates (Gardener, Nanny, Nurse, Accountant…) prefill the
  form; live card preview on Review.
- Bug fixed in passing: renew_job set status 'active' (not allowed) so
  renewing an expired job always failed.
- Palette: blue/navy marks, green only for status badges, red only for
  Start now, gold left for the verified tick.

### Reports you can act on (patch_279, 28 Oct 2026, owner request)

Report already existed on jobs, products and stores and reached the
dashboard, but showed only a type + id and offered Ban only for reports
about a person. patch_279: server fills who's behind every report; one
open report per member per item; the queue shows title, preview, current
state, owner and how many open reports; **Remove** (job → rejected,
product → hidden with appeal, store → closed with its listings, Page →
hidden, post → hidden) and **Remove & ban** (also bans and takes down
everything else they have live). Both dashboards (admin/ and admin-web/)
updated; they fall back to the old buttons until the patch runs.

### Product sizes, stock and specifications (patch_280, 28 Oct 2026)

- Seller form: "Count my stock" (optional), up to 2 option groups with
  presets (Size, Shoe size, Colour, or a custom one), a per-combination grid
  for stock and an optional own price, and specification rows with
  suggestions per category. Hidden until patch_280 runs.
- Product page: size/colour chips (sold-out choices struck through and not
  pickable), the chosen option's own price, "Only N left" / "In stock" /
  "Sold out", a Specifications table; the buy button says "Choose a size"
  until one is picked and "Sold out" when nothing is left.
- Basket: one line per product + option, capped at counted stock; the
  option label shows in the basket, orders, the seller's inbox and the
  WhatsApp handoff.
- Checkout (place_order): locks rows, refuses an order over stock or
  without an option, uses the option's price, deducts stock; cancelling an
  order restores it. Its reasons ("Only 2 left of …") reach the buyer.
- Found while rehearsing on the live DB: **checkout had never worked** —
  place_order called jsonb_array_length on a text[] column, so every order
  failed (0 orders existed). Fixed in patch_280.
- Security: members could INSERT orders/order_items directly (any price,
  any status). Revoked; place_order (SECURITY DEFINER) is the only way in.

### Search redesign (13-batch plan, Batch 9 — 28 Oct 2026)

- Three states: landing (Jump-to grid for People, Pages, Churches, Shop,
  Jobs, Events, Videos, Library; recent searches; a rail of people you may
  know; grouped discovery lists) → **suggestions while typing** → full
  results on submit, in underlined tabs with real counts (Top, People,
  Pages, Posts, Shop, Jobs, Churches, Events, Videos — empty ones hidden).
- Suggestions (SearchTypeaheadService): a few rows per type, only the
  columns shown, in parallel, stale answers dropped; church/people names
  ride the existing trigram indexes. Bible references ("John 3:16") open
  the Bible at that verse; hymn numbers/titles open the hymn. No new
  backend — a combined search function can replace its body later.
- Fixed: typing ran the full seven-way search on every pause, and the
  church part downloaded up to 5,000 churches to show 12 (now 20, and
  only on submit). The search field drew a white box around the text
  (theme fill) — fixed in the shared AppSearchField, which also fixes it
  in Chat's search. Pages are now searchable.
- Results are grouped cards with hairlines instead of one floating card
  per row; avatars are fetched at 3x their drawn size.

