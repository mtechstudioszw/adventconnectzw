# NEXT SESSION — start here

**Last session: 18 Aug 2026 (second sitting).** Both blockers from the
previous handoff are **done**, plus eleven issues the founder reported off
the last debug build.

`dart analyze lib test` → **4 pre-existing infos, exit 0** (the documented
baseline; nothing new).

---

## Pre-production round (19 Aug 2026) — v1.4.0

Founder's "small things before production" list, plus what looking into it
turned up. **The biggest find was not on the list.**

### 🔴 YouTube notifications were spamming every member (patch_222)

Reported as "I can't see YouTube notifications being sent". They were being
sent — 23 per member per day.

```
110,366  youtube_live notifications ever   |  107,191 still unread
  4,872  in the last 24h, to all 213 members
    844  for ONE video (213 members x 4 rounds)
  1,481  for one channel (2CBN TV) in 24h
     51 MB  notifications table
```

Nobody "saw" them because at that rate Android collapses and throttles them.
`youtube_fanout_notification` had **no de-duplication at all** — every call
inserted a row per profile. The only guard was in the edge function
(`videoId !== channel.live_notified_video_id`), which remembers just the LAST
video per channel, so a channel flapping between two live ids ping-pongs past
it forever — and the live cron runs **every minute**.

patch_222 adds `youtube_live_notified` (video_id PRIMARY KEY) and makes the
RPC claim the id with `ON CONFLICT DO NOTHING` *before* sending. Whoever wins
the claim notifies; everyone else returns 0. Verified: re-notifying an
already-sent video now returns 0. Seeded with the last 30 days so it did not
fire one final round on deploy.

**Still to do:** ~107k unread junk notifications are still in members'
notification centres. Deleting them is a data change nobody has authorised
yet — ask before running it.

### 🔴 Two flows leaked the founder's phone number

Both "reported" by opening WhatsApp to `263778092494` with a pre-filled
message. Both are now proper in-app flows:

- **Report a seller** (`seller_profile_screen`) → `ReportService.submit(...)`,
  which already existed and already listed `'seller'` as a content type.
- **Request to post announcements** (`group_info_screen`) → the real
  `claim_church` flow → `church_admins` → the approvals dashboard.

Why this mattered beyond the phone number: WhatsApp lets the sender **edit
the pre-filled text before sending**, so the seller id, reason and reporter
id were all attacker-controlled by the time they arrived — the reports could
not be trusted. And if the member never pressed send, nothing was recorded
anywhere while the app behaved as though it had been.

The founder's number REMAINS in About, Settings and the banned-account
screen. That is deliberate — it is the published support channel, and a
banned member has no in-app route left.

### Cooldown bug I introduced in patch_215 (fixed by patch_221)

Both cooldown triggers stamped the clock on the FIRST set, so onboarding
spent it: pick a country at signup, spot a typo a minute later, locked out
for 14 days. Now only a change *from an existing value* starts the clock, so
everyone keeps one free correction. The repair released a wrongly-locked
member (church locks 25 → 24).

### The rest of the list

- **`updateProfile` swallowed every database error** into "Could not update
  profile." It now surfaces the real message (`PostgrestException.message`),
  which is what every guard on `profiles` writes for members to read. This is
  why the reported edit-profile failure could not be diagnosed from the
  report — the app knew and threw the answer away.
- **Edit profile no longer needs a church to save anything else.** It used to
  refuse the whole save with no church selected, locking anyone who skipped
  that step out of their own name, bio, photo and country. Only *clearing* an
  existing church is blocked now.
- **Onboarding**: country moved to the TOP of step 1 and labelled "WHERE ARE
  YOU?" with "we guessed from your phone" — being pre-filled was making it
  invisible, and everything downstream hangs off it. "Skip for now" removed
  from step 1 only (**it must stay on step 2 — it is the only way past the
  church step without picking one**).
- **The church step no longer lies.** It promised "you can still follow other
  churches anytime"; `church_details_screen` refuses to follow anything that
  is not your home church, by design. It now states the truth and the 2-week
  cooldown.
- **Intro film**: opener is now "Connect with Adventists all over the world"
  (matches the splash), and "2,600+ congregations" — the Zimbabwe-only count,
  and the one line telling a Kenyan the app was not for them — became "Find
  your church, wherever you worship".
- **Chat privacy notice** now tells the truth in BOTH states. The off-state
  used to say "church admins cannot read private chats", which invites the
  reader to conclude nobody can, while the backend runs on a privileged
  credential. Both states end in a real "Learn more" into the policy, and the
  mini-profile block is no longer hidden when encryption is off.
- **Version 1.4.0** (feature release — the app now works outside Zimbabwe).
  `feedback_service` had hardcoded `'1.0.0+1'`, so **every feedback report
  ever filed was stamped with a version that stopped existing before 1.1** —
  it reads the shared constant now.

### Security audit

Clean, with one finding that was mine. Checked: RLS coverage, policies with
`USING (true)`, SECURITY DEFINER functions without `search_path`, per-column
grants on `profiles`, committed secrets, storage policies.

- **Fixed:** `youtube_live_notified` (created earlier the same day) had no
  RLS. Enabled, and revoked from `anon`/`authenticated`.
- **Not findings:** the 9 tables with RLS-but-no-policies are internal
  (audit log, sessions, throttle, quiz internals, staff) — deny-all to
  clients with service_role bypassing is the correct pattern.
  `churches_select_all USING (true)` is a public directory. The committed
  anon key and `google-services.json` API key are public by design.
  `fcm_token` has **no SELECT** for clients, as CLAUDE.md requires.
  `reports` are readable only by their author; `messages` only by
  conversation participants; `chat_media` is participant-scoped in a private
  bucket. Admin gating is server-side RLS, with the client flag only hiding
  menu items.

### Answered, not built

- **Google signup cannot supply date of birth.** Google's OAuth returns name,
  email and picture; birthday needs `user.birthday.read`, a sensitive scope
  requiring app review, and is usually not public even then. The age prompt
  has to stay — the ≥16 rule depends on it. The **profile picture** IS
  available (`avatar_url`) and is worth prefilling.
- **Ad placements** — deliberately not added without a decision. See the
  founder conversation; more inventory is a retention cost, not free revenue.

---

## Database patches applied THIS session

All applied to project `adventconnectzw` (ref `eqbyvasteolqyktbqbem`) via the
Supabase Management API and verified by reading the output, not by assuming
"it ran".

| Patch | What |
|---|---|
| **213** (existing, never run) | country on profiles/churches/events/jobs/products/sellers |
| **214** (new) | country on `church_suggestions` — 213 missed it |
| **215** (new) | church cooldown 90d → **14d**; same 14d gate on `country` |
| **216** (new) | birthday notifications: once per day, from 08:00 local |
| **217** (new) | `products.price_currency`: ISO 4217 **shape** check, not a 3-value list |
| **218** (new) | `posts.country`, backfilled from the author, stamped by trigger |
| **219** (new) | pg_trgm + GIN indexes so church search survives 185k rows |
| **220** (new) | `churches.astr_id` — the import must ADOPT, not duplicate |
| **221** (new) | cooldown fix: the FIRST choice no longer spends the 14 days |
| **222** (new) | YouTube live fan-out de-duplication (was 23 pushes/member/day) |

### patch_213 was the cause of three "app bugs"

It had never been run, and three separate bug reports were all this one
missing column:

| Reported as | Actually |
|---|---|
| Onboarding country step: "Could not update profile" | `updateProfile` upserted `country`; its retry only strips `cover_photo_url`, so it threw again into the generic catch |
| Profiles don't load | `user_profile_service.dart` selects an explicit column list including `country` — PostgREST 400s the **whole** query on a missing column |
| Seller profiles don't load | Same query inside a `Future.wait` in `seller_profile_screen.dart`; one rejection took the whole page down |

No Dart changes were needed for any of them. **When several unrelated
screens break at once, query `information_schema.columns` before reading
Dart.**

---

## Country / global readiness

**Country pickers on five listing forms** — the four named in the last
handoff plus **Edit store**, which is the only way an existing seller can
correct the `'ZW'` the backfill gave them: `add_product_screen`,
`post_job_screen`, `setup_store_screen`, `edit_store_screen`,
`suggest_church_screen`.

New `CountryFormField` (in `lib/widgets/country_picker_sheet.dart`) renders
the picker inside **the caller's own `InputDecoration`**, because each post
form builds inputs from a different local decoration helper and the existing
`CountryField` paints its own box.

Pattern in all five: country defaults from `AuthService.currentCountry()` (or
the row being edited); the **Zimbabwean province dropdown appears only when
country is `ZW`**, otherwise the same `province` column takes free-text
"State or region". Province stays mandatory in ZW only.

**Watch the asymmetry in the update paths:** `'country': ?country` but
`if (country != null) 'province': province`. Province is written *even when
null*, so switching a listing to Kenya clears the stale Zimbabwean province —
`?province` would skip the null and strand it.

**WhatsApp handoff no longer assumes Zimbabwe.** Every handoff did
`raw.replaceAll(RegExp(r'\D'), '')` and handed that to `wa.me`, so a seller
who typed `0778 092 494` produced `wa.me/0778092494` — an error page. Never a
ZW-only bug, but unfixable without a country. Now
`Countries.toWhatsAppDigits(raw, countryCode:)` normalises against the
**seller's** country (`+`/`00` respected, trunk `0` swapped for the dial
code, no guessing when the country is unknown). `MarketOrder` gained
`sellerCountry` so the order handoff has it too. Phone-field hints come from
`Countries.phoneHint(country)` instead of a hard-coded `+263`.

**Language switcher removed from Settings.** It offered English / Shona /
Ndebele and changed nothing — no translations exist, so it persisted a
preference no screen read, and it promised something the app cannot do now
that non-Zimbabweans are signing up. The Bible-translation, Sabbath-School
(~90 languages) and Hymnal pickers are separate and untouched. This also
sidesteps the `profiles.language_preference` CHECK constraint that was
flagged as a global blocker.

---

## Other fixes this session

1. **App icon** — `flutter_launcher_icons` had never been run after the
   rebrand: `colors.xml` still carried the old `#0D1B3E` adaptive background
   against pubspec's `#022171`. Regenerated. Separately, the native
   `launch_background` (the frame *before* the Flutter splash) was dark navy
   while the splash paints light grey, so every cold start flashed navy then
   snapped light — now `#F5F7FA`, with a new `values-night/colors.xml` at
   `#0B1124`.
2. **Splash line** — "TANATSWA MICHAEL MIKUWA" → "Connecting Adventists all
   over the world". ⚠️ Differs from the tagline recorded last session
   ("Connecting SDA people around the globe"); founder dictated the new
   wording. Make `docs/` agree with whichever wins.
3. **Shared links opened "Route not found".** The Android manifest had no
   `flutter_deeplinking_enabled`, so the engine handed go_router the raw
   `io.supabase.adventconnect://seller/<id>` *while* `app_links` handed the
   same link to `DeepLinkService`. go_router cannot match a URI whose type is
   in the HOST, so its error page won the race. Manifest now sets it
   `false` (verified safe: `supabase_flutter` catches `login-callback`
   through app_links, not the Router), plus `_shareLinkRedirect` in
   `router_config.dart` as a belt-and-braces net for iOS.
4. **Encryption notice was overclaiming.** It said "your messages are
   end-to-end encrypted, nobody outside this chat can read them" while
   `sendMessage` encrypts **only the body of a text message** — photos and
   voice notes are storage paths the server can read. Reworded in
   `chat_screen.dart` and `chat_contact_sheet.dart`.
5. **Chat privacy is GLOBAL, not per-chat** — all four settings are
   `profiles` columns. Opening it from inside a conversation made it read as
   per-person; the screen now says so.
6. **Security code in the mini profile** — new `E2eeService.securityCode()`,
   Signal's 60-digit numeric fingerprint (`NumericFingerprintGenerator`,
   5200 iterations) over both identity keys, with the encryption note and a
   "Learn more" into the privacy policy. Pinned by
   `test/security_code_symmetry_test.dart`, which proves both handsets derive
   the same digits from swapped arguments.
7. **Tapping a chat photo exited the viewer** — `full_image_viewer.dart`
   wrapped its whole body in a dismissing `GestureDetector`. Tap is now
   inert; ✕ and system back dismiss.
8. **"Save to gallery" saved only the first photo** of an album and still
   reported success. Now saves every photo, asks for permission once, and
   reports partial results honestly ("3 of 5 saved"). Menu says "Save all N
   photos".
9. **Home + Profile show the home church NAME**, not a count. "1 Churches"
   was always 1 or 0 and told the member nothing.
10. **Devotion card slide order** now matches the Home pill row exactly:
    Bible, Quiz, EGW, Sabbath School, Hymn, Music. The pills were already in
    that order — only the slides were out of step. Note `LibraryTiles` pills
    carry their own tab indexes on purpose; do NOT "tidy" them to match the
    Library TabBar, whose order is deliberately different.
11. **Birthday notifications** — see patch_216. They fired at **midnight
    local** (the 22:00-UTC tick starts the Harare day) and then a **second
    time ~20h later**, which is the "5pm, birthday nearly over" copy the
    founder saw. Now day-scoped and held until 08:00 local.

---

## ⚠️ DO THIS FIRST next session

1. **E2EE is now staged to the founder's account — go and test it.**

   `app_config.e2ee_enabled` no longer takes only `0`/`1`. It also accepts a
   **list of user ids**, and encryption turns on for those accounts only.
   It currently holds `957a0caa-e784-4735-b690-b68fd2d658d0` (Tanatswa
   Michael Mikuwa).

   This existed to break a catch-22: the standing rule was "flip it only
   after a real send and receive on two handsets", but with the flag off
   encryption never runs, so that test was impossible to perform. The
   options were to flip it globally and hope, or to test on real devices
   with only one account exposed. This is the second.

   **Why it is not just a switch.** A failure here does not look like a
   broken screen — it writes ciphertext nobody holds a key for, and those
   messages are unreadable *forever*. No repair, no migration. The
   allowlist bounds that to the accounts you name.

   Old builds are unaffected: they compare the value to `'1'`/`'true'`, so
   a UUID reads as OFF. Nothing changes until an APK containing
   `_readFlag(userId)` is installed.

   **The test:** sign two handsets into two allowlisted accounts, send both
   ways, confirm the bubbles read correctly on BOTH devices, force-quit and
   reopen, confirm they still read. Then — and only then — set the value to
   `1`. Set it back to `0` at any sign of trouble; decryption is
   deliberately NOT gated on the flag, so anything already sent stays
   readable.

   Until it is on, the encryption notice and the security code stay
   invisible, since both are gated on `isEncryptionOn`.
2. **Sabbath timer already handles other countries** — `_coords()` resolves
   ZW province → the member's country centroid (`countries.dart`) → Harare.
   Nothing to do; it just needs a build newer than the founder's current APK.
3. **Nothing promotes a church suggestion into `churches`** — no SQL
   function, no admin-web code; it is done by hand. Whoever does it must copy
   `country` across or the `'ZW'` default silently wins and patch_214 buys
   nothing.

---

## Open, decided but not built

**Donations outside Zimbabwe** — the founder asked for options beyond
EcoCash. The blocker is not the app, it is that **Zimbabwe cannot receive on
PayPal or Stripe** (send-only), so the usual "add a PayPal link" answer does
not work. Realistic rails, cheapest first, all of which keep DonateScreen's
current design (show details, collect nothing in-app):
  - **Remittance to the existing EcoCash line** — Mukuru, WorldRemit,
    Western Union, Remitly all serve the ZW corridor. Zero integration; the
    receiving side already exists.
  - **A USD nostro bank account** (SWIFT) for larger gifts.
  - **Payoneer**, which does support ZW receiving in some cases.
  - **USDT (TRC-20)** — widely used by the Zimbabwean diaspora; check Play
    policy before shipping.
  - PayPal **only** via a trusted non-ZW account, which has its own risks.
  Suggested build: make DonateScreen country-aware off
  `AuthService.currentCountry()` — ZW sees EcoCash, everyone else sees the
  remittance instructions. Founder must first say which accounts exist.

---

## Ambient background — BUILT this session

The splash's drifting particle field now sits behind the whole app.
`lib/widgets/ambient_background.dart` paints the opaque ground plus
`AmbientPainter`, and is installed once in `MaterialApp.builder` so it lives
under the router's Navigator — pages slide over a field that stays put.

**91 Scaffold backgrounds across 83 files became `Colors.transparent`.** Read
this before touching any of them:

- Only the **Scaffold** background changed. `palette.scaffoldBg` itself is
  untouched, because headers rely on it to occlude content scrolling under
  them (CLAUDE.md's flat-header rule). The two non-Scaffold uses — a modal
  sheet in `conversations_screen` and the `watch_screen` header — were
  deliberately left opaque.
- **Five screens keep an opaque Scaffold on purpose** because they already
  paint this same field themselves: `auth_shell`, `onboarding_flow_screen`,
  `onboarding_screen`, `maintenance_screen`, and `chat_screen` (via
  `ChatWallpaper`). Making those transparent stacks two fields.
- **It runs at ~15fps, not 60** (`AmbientBackground.frameInterval`), behind a
  `RepaintBoundary`, and freezes entirely under "reduce motion".
  `ChatWallpaper`'s own doc comment explains why: a full-screen animated
  CustomPaint under a flung list repaints the viewport every frame, and this
  one is under *every* screen for the whole session. The drift is a 14s loop
  of soft blobs, so 15fps is indistinguishable from 60 at a quarter the cost.
  **This is the one change that could not be verified without a real
  handset** — if scrolling feels worse on a mid-range phone, raise
  `frameInterval` or pin the field static like `ChatWallpaper` does.

---

## Country filtering — BUILT, and the feed is deliberately different

**Marketplace and Jobs are country-scoped by default**, with a
`CountryScopeToggle` ("🇿🇼 Zimbabwe | Worldwide") above the category chips.
Both empty states name the country and offer a "Browse worldwide" button,
because every listing in the database today is `ZW` — without that, the
first seller in a new country opens an empty screen and concludes the app
is broken. Scope counts as a filter for caching: a worldwide list is never
written to the offline cache, or it would greet the member with another
country's listings on next launch.

**The feed is NOT filtered, and this was a corrected mistake.** It was built
scoped like the others; the founder asked "so an American user can't see Zim
posts?" and was right. The difference:

> A sofa in Harare genuinely cannot be collected from Boston. A *post* from
> Harare reads perfectly well there.

Scoping the feed would cut a Zimbabwean in Texas off from the exact people
they installed the app to stay near — against the app's own tagline — and,
with all 41 posts currently from Zimbabwe, would show every new overseas
member an empty Home. So `posts.country` (patch_218) drives a **ranking
boost, not a filter**: `countryBoost = 0.30` in
`FeedService._personalisedScore`, below `churchBoost` (0.35) and
`friendBoost` (0.50), so someone you know abroad still outranks a stranger
next door. Home passes `viewerCountry:`; there is no toggle on Home.

`FeedService.fetchFeed` also takes `onlyCountry:` — a hard filter nothing
calls yet, kept because the query shape should be proven before it is
needed.

**patch_218** adds `posts.country`, backfills it from each author's profile,
and stamps it on insert with a BEFORE INSERT trigger rather than trusting
the client — a post's country is simply where its author is, so asking every
insert path to remember would re-create the silent-`ZW` bug. It is a
snapshot: moving abroad does not retro-move your old posts.

---

## Then, in rough priority order

**Country, remaining**
- **Member directory: LEAVE IT ALONE** (founder, 19 Aug 2026). It has no
  country filter and it does not need one, because it shows nothing at all.

  Measured: `member_directory` has **0 rows**, 0 visible — while 213
  profiles are `is_discoverable`. The screen lists only members who
  explicitly opted in via "My directory profile", and nobody ever has, so it
  renders an empty list every time. It is routed and reachable from Home.

  Two ways out, and the second has a catch worth knowing before anyone
  reaches for it: surface the opt-in (consent stays explicit, fills slowly),
  or point the screen at `DirectoryService.fetchAllDiscoverableProfiles()`
  which returns all 213 immediately. **Nothing in the app ever lets a member
  set `is_discoverable`** — it is read in five places and written in none,
  so it is a database default that happens to be true for everyone.
  Publishing 213 people's name, photo, bio and a message button on the
  strength of a flag they were never shown is a privacy change, not a bug
  fix. If that route is taken, ask people first.

  Founder's call for now: leave as is.
- Church directory and Events are DONE — both carry `CountryScopeToggle`
  with country-by-default, a "Browse worldwide" button in the empty state,
  and scope excluded from the offline cache (a cached worldwide list would
  otherwise greet the member with another country's rows on next launch).
  Events scoping had to reload BOTH tabs, or Past keeps the previous
  scope's results until someone happens to pull-to-refresh it.
- Every posting form now captures country — `post_event_screen` was the last
  one and got its picker this session, so nothing is defaulting to `'ZW'`
  silently any more.

**Currency — done, with one gap**

`products_price_currency_check` hard-coded `ARRAY['USD','ZWL','ZAR']`, so a
Kenyan seller could not price in KES: the insert failed on a constraint
violation the app could not explain. patch_217 replaces it with a *shape*
check (`~ '^[A-Z]{3}$'`), the same reasoning patch_213 used for country —
the database rejects junk, the app curates the list. `orders` and
`order_items` carry no currency CHECK at all, so they inherit this for free,
and `formatMoney` already renders any code (`USD → $`, else `KES 500`).

`Countries.currencyChoices(country)` now drives the dropdown: Zimbabwe keeps
USD/ZWL/ZAR, everyone else gets their own currency then USD. The map behind
it (`Countries.currencyOf`) covers Africa thoroughly and the main diaspora
destinations, and **returns null rather than guessing** — an unknown country
is offered USD alone, because a wrong currency on a real listing is acted on
by a buyer. Adding a country is a one-line fix.

- **The gap:** only `add_product_screen` offers the choice. Nothing converts
  between currencies and nothing filters by them, so a buyer browsing sees
  mixed currencies side by side in the grid. That is honest but not pretty,
  and is the next thing to look at once country *filtering* lands.

**Other global gaps**
- `notify_birthdays()` still uses `Africa/Harare` as everyone's clock; a real
  fix needs a per-member timezone, which `profiles.country` alone cannot give
  (the US spans six).
- Division/union grouping (`churches.conference` already exists).

## Global church directory — groundwork DONE, import still blocked on you

**You must still request Adventist OrgMast (ASTR) API access.** Nothing else
here can proceed without it. What is now ready for the day it arrives:

### The 2,600 Zimbabwean churches STAY. The import adopts, never duplicates.

Founder asked what happens to them. Measured against the live database:

| | |
|---|---|
| churches | 2,600 |
| members whose `profiles.church_id` points at one | 161 |
| distinct churches with members attached | 120 |
| approved `church_admins` rows | 9 |
| rows already sharing a name+city | **34** |

OrgMast covers Zimbabwe too, so a naive "import everything" makes a SECOND
Avondale SDA Church. That is not cosmetic: the congregation splits (existing
members on the old row, new joiners picking the new one), announcements
reach half of them, the 9 admins keep rights over a row nobody new can find,
and — because changing church is gated to once per 14 days (patch_215) —
anyone who picks the wrong twin is stuck for a fortnight. None of it is
fixable by deleting rows later, because by then real members are on both.

**patch_220** adds `churches.astr_id` with a partial UNIQUE index. The
import becomes: known `astr_id` → UPDATE; otherwise try to match an existing
row (country + name + city) and write the `astr_id` onto the row we already
have; only a church matching nothing gets INSERTed. UNIQUE makes a
185,000-row import restartable, which it will need to be.

**Do not auto-merge ambiguous matches.** 34 name+city collisions already
exist in the current 2,600, so the data is not clean enough to trust a fuzzy
match blind — ambiguous ones need a human queue. And never delete a church
with members, admins, events or announcements attached: a congregation using
this app is more authoritative about its own existence than a directory is.

### The picker is server-side now

- **patch_219**: `pg_trgm` + GIN trigram indexes on `churches(name)` and
  `churches(city)`, plus `(country, name)`. A plain B-tree cannot serve the
  `ILIKE '%term%'` these screens send; over 185,000 rows that was a
  sequential scan per keystroke.
- `ChurchService.searchChurches({query, country, limit: 40})` — one small
  indexed query per keystroke. The onboarding picker now debounces 300ms and
  queries the server, with a sequence guard so a slow reply for "ha" cannot
  land after "har". Changing country in step 1 reloads step 2's list.
- `ChurchService.fetchChurchesByIds()` — Profile downloaded the ENTIRE
  directory to find the 2–3 churches a member follows. It asks for those now.
- Home's church rail is `country`-scoped and capped at 60.

**Still client-side, and next to break:** `churches_screen` sorts
nearest-first in Dart, so it needs the rows. That wants a real geo query
(earthdistance/PostGIS) and is pointless until the rows exist.

**"📍 Near me" is Zimbabwe-only.** It calls `nearestZimbabweCity()`, which
snaps the device GPS to the closest *Zimbabwean* city — so for a member in
Nairobi it resolves to somewhere in Zimbabwe and filters to it. The country
scope toggle now bounds the damage (the list is their own country by
default), but the feature itself needs real coordinates on `churches` plus a
distance sort before it means anything abroad. Same geo work as above.

### ⚠️ The first member in a new country cannot set a home church

The onboarding picker's empty state now names the country and offers "Add my
church", which routes to `suggest_church`. But a suggestion lands in
`church_suggestions` **for admin review** — it does not appear in the picker,
so that member finishes onboarding with no home church and has to come back
via Edit profile once someone approves it.

That is survivable today (step 2 is optional, and the copy says "we'll
verify it") and it is deliberately not auto-created: letting any signup
write straight into `churches` is how a directory fills with duplicates and
junk. But note the review queue has **1 announcement and 9 admins, all
Zimbabwean** — nobody is watching it for Kenya. Before any real push into a
new country, either:

  * give the suggester a provisional church they can select immediately,
    flagged unverified and merged on approval; or
  * make sure someone actually works the queue.

Otherwise the first member in each new country hits a dead end that looks
like the app not supporting their country.

**Global church directory**
- **Do NOT scrape `adventistdirectory.org`** — robots.txt names
  `ClaudeBot: Disallow: /` and every `adventist.org` host 403s.
- Use the official **Adventist OrgMast Data API** (ASTR); the founder must
  request access.
- Scale: **106,936 churches + 78,061 companies** worldwide vs ~2,600 ZW rows
  today. `ChurchService.fetchChurches(limit: 5000)` truncates and the
  onboarding church picker filters **in memory** — both must go server-side
  and paginated *before* any import.

---

## Deployment — DONE 19 Aug 2026, except Play Console

Everything below was deployed and then verified by fetching it back, not by
trusting a 200.

1. **Supabase edge functions — all five redeployed.** `notify-fcm` (v24),
   `event-share` (v14), `job-share` (v10), `product-share` (v13),
   `seller-share` (v10). Every deployed bundle now contains
   "Adventist Super App" and zero occurrences of "Advent Connect ZW"; the
   four share pages return HTTP 200 with the new branding, and `notify-fcm`
   answers an unauthenticated POST with 401 (a handled auth rejection, so it
   boots).

   ⚠️ **Deploy them with the MULTIPART endpoint, not `PATCH`.** No CLI is
   installed on this machine, and the obvious
   `PATCH /v1/projects/{ref}/functions/{slug}` with `{"body": "<source>"}`
   returns 200, reports ACTIVE — and produces a function that 503s on every
   request, because it never sets an `entrypoint_path`. That is exactly what
   happened to `event-share` (v13) mid-session; v14 via multipart fixed it.
   Use:

   `POST /v1/projects/{ref}/functions/deploy?slug={slug}` as
   `multipart/form-data` with a `metadata` JSON part
   (`{"entrypoint_path":"index.ts","name":"<slug>","verify_jwt":false}`) and
   a `file` part. The five deployed here are self-contained — each imports
   only `esm.sh/@supabase/supabase-js@2` and nothing from `_shared` — which
   is why a single-file deploy is safe for them. **`play-rtdn`,
   `verify-purchase` and the `youtube-*` functions DO import `_shared`, so
   they need real bundling; do not deploy those this way.**

2. **Cloudflare `share-worker.js` — deployed.** All four route types return
   200 with the new branding. Note the slugs are `product-share`,
   `event-share`, `seller-share`, `u` — NOT `/product/<id>`; a wrong path
   404s and looks like a broken worker.

   ⚠️ Redeploy with `{"type":"inherit","name":"SUPABASE_ANON_KEY"}` in the
   metadata bindings. A plain PUT without it **wipes the secret** and the
   worker starts failing to reach Supabase.

3. **Email logo — replaced.** `library/branding/logo-240.png` is now the new
   mark (240×240, generated from `assets/icon/app_icon.png`, so it sits on
   brand blue and stays legible on any email background). The old file is
   only in this session's scratchpad, so re-upload from `app_icon.png` if it
   ever needs regenerating.

### Still yours — Play Console

**Not deployable from here.** Listing copy is in
`docs/PLAY_STORE_LISTING.md`. Rename the subscription's *display title*
only, never the product ID. **Countries/regions is probably still
Zimbabwe-only — that setting, not the rebrand and not any of this code, is
what actually makes the app installable worldwide.**

---

## NEVER rename these — the app's technical identity

| Identifier | Value |
|---|---|
| Android applicationId | `io.supabase.adventconnectzw.advent_connect_zw` |
| Dart package | `advent_connect_zw` |
| Deep-link scheme | `io.supabase.adventconnect://` |
| FCM default channel | `advent_connect_zw_default` |
| Share worker | `advent-share.adventconnectzw.workers.dev` |
| Legal URLs | `mtechstudioszw.github.io/adventconnect-legal/` |
| Support inbox | `adventconnectzw@gmail.com` |

---

## Working on this machine

- **`flutter analyze` deadlocks** against the VS Code Dart extension's
  analysis server here — it sat 25 minutes at "Analyzing…" on ~5s of CPU.
  Use **`dart analyze lib test`**. Baseline is **4 infos**
  (2× `event_details_screen`, `push_service`, `date_format`), exit 0.
- On a fresh clone the whole `lib/` folder shows red until `flutter pub get`
  finishes. That is not a code problem.
- Git on Windows rewrites line endings: `ic_launcher.xml`, the iOS
  `project.pbxproj` and the desktop `generated_plugin_registrant` files show
  as modified with **empty diffs**. `git checkout --` them before committing.
- Applying a patch without the dashboard: `POST
  https://api.supabase.com/v1/projects/{ref}/database/query` with a `sbp_`
  token. **Send the body as UTF-8 bytes** — PowerShell's default encoding
  mangles the em-dashes in these files and the API 400s with a JSON parse
  error at ~position 113.
- Every push to `main` builds a debug APK via
  `.github/workflows/build-apk.yml` → the `latest-debug` release →
  `adventist-super-app-debug.apk`. Settings → App version shows the commit
  SHA, so you can confirm you are not chasing bugs in a stale build.
