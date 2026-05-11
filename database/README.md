# Advent Connect ZW — Database

Production-ready SQL for the **Advent Connect ZW** Supabase project.

| File | Purpose |
| --- | --- |
| `schema.sql` | The 11 core tables, indexes, triggers, RLS policies. **Required.** Run first. |
| `patch_001_auth_profile_trigger.sql` | Auto-creates a `public.profiles` row on signup. **Required.** |
| `patch_002_v4_completion.sql` | Adds 14 more V4 tables (sellers, saved_listings, announcements, church_admins, church_edit_suggestions, church_suggestions, notices, member_directory, notification_preferences, blocked_users, reports, notifications, seller_ratings, urgent_banners), their RLS, storage buckets + policies, and the DB-driven in-app notification triggers. **Required.** |
| `seed_data.sql` | Sample data for development / staging. **Optional.** |

Run in this order: `schema.sql` → `patch_001_…` → `patch_002_…` → `seed_data.sql`.

## Tables created (11)

| # | Table | Purpose |
|---|---|---|
| 1 | `churches` | SDA churches across Zimbabwe (≈2,600 records expected after import) |
| 2 | `profiles` | User profiles, 1-to-1 with `auth.users` |
| 3 | `events` | Camp meetings, youth rallies, conferences, etc. |
| 4 | `event_rsvps` | Junction — who is going to what |
| 5 | `church_followers` | Junction — which user follows which church |
| 6 | `prayers` | Prayer request feed (V4 calls this `prayer_requests`) |
| 7 | `prayer_responses` | "I'm praying" reactions and supportive comments |
| 8 | `products` | Marketplace listings |
| 9 | `jobs` | Job board (V4 calls this `job_posts`) |
| 10 | `conversations` | 1:1 direct message threads |
| 11 | `messages` | Individual messages inside a conversation |

The schema reflects **Part 11** of `ADVENT_CONNECT_ZW_MASTER_REFERENCE_V4.md`. A handful of the most exotic V4 fields are deferred until the full 31-table schema is rolled out.

## Region

Project **must** live in the Africa (Cape Town / `af-south-1`) region. This is non-negotiable per the master reference.

---

## Running the SQL

### Option A — Supabase Studio (recommended for first run)

1. Open your project in <https://supabase.com/dashboard>.
2. Sidebar → **SQL Editor** → **+ New query**.
3. Paste the contents of `database/schema.sql`.
4. Click **Run**. You should see *Success. No rows returned.*
5. *(Optional)* Sidebar → **Database → Tables** to verify the 11 tables are present.

### Option B — Supabase CLI

```bash
# From the project root
supabase db push --file database/schema.sql

# Once you have edited the seed UUIDs (see below):
supabase db push --file database/seed_data.sql
```

### Option C — psql

```bash
psql "$SUPABASE_DB_URL" -f database/schema.sql
psql "$SUPABASE_DB_URL" -f database/seed_data.sql
```

The connection string is at **Project Settings → Database → Connection string (URI)**.

---

## Enabling Realtime

Per Part 13 of the master reference, **only** these tables should be on the realtime publication:

- `messages` — chat delivery
- `conversations` — typing + unread counters

Either run the two `ALTER PUBLICATION` statements at the bottom of `schema.sql` (uncomment them), or use **Database → Replication** in Studio and toggle the two tables on.

> **Do not** enable realtime on every table — it will balloon egress and CPU.

---

## Storage buckets

Realtime aside, you also need these buckets (create via **Storage → New bucket**):

| Bucket | Public read? | Max size |
|---|:-:|---|
| `profile_photos` | ✅ | 500 KB |
| `church_photos` | ✅ | 800 KB |
| `product_photos` | ✅ | 600 KB |
| `event_flyers` | ✅ | 1 MB |
| `appointment_letters` | ❌ private | 2 MB |
| `voice_notes` | ❌ private | 10 MB |

Allowed mime types: `image/jpeg`, `image/png`, `image/webp`, `application/pdf`, `audio/m4a`, `audio/mp3`, `audio/aac`. Reject everything else server-side.

---

## Seed data — required UUID setup

`seed_data.sql` references three placeholder UUIDs:

```text
00000000-0000-0000-0000-000000000001  →  Tatenda  (member, Harare)
00000000-0000-0000-0000-000000000002  →  Rufaro   (member, Bulawayo)
00000000-0000-0000-0000-000000000003  →  Tinashe  (seller,  Mutare)
```

Before running it:

1. Sign up three test accounts (via the Flutter app or **Auth → Users → + Add user**).
2. Copy the three real `auth.users.id` values.
3. Open `database/seed_data.sql` and replace the placeholder UUIDs in the `DECLARE` block.
4. Run the script.

If the script can't find a profile for `user_a`, it logs a `NOTICE` and exits cleanly without inserting any of the auth-dependent rows — so churches will seed even if you forget step 1–3.

What gets seeded after step 4:

- 5 churches (always — no auth required)
- Bio / location for the three test profiles
- 5 events (camp meeting, youth rally, sacred concert, graduation, week of prayer)
- A handful of RSVPs and church follows
- 10 prayer requests + a few "praying" reactions
- 5 marketplace products
- 5 job posts
- A sample marketplace conversation with 4 messages

---

## RLS in plain English

| Table | Read | Write |
|---|---|---|
| `churches` | Anyone | Service role only (admin tools) |
| `profiles` | Self always; others only if `is_discoverable = TRUE AND is_banned = FALSE` | Owner only |
| `events` | Approved events visible to all; pending visible to organizer | Organizer only — but **status column is locked at the trigger level** (admin/service-role only) |
| `event_rsvps`, `church_followers` | Any signed-in user | Owner only |
| `prayers` | Public + anonymous → all auth; church_only → followers; private rows → author | Author only |
| `prayer_responses` | Any signed-in user | Owner only |
| `products` | Anyone (except `removed`, visible only to seller) | Seller only |
| `jobs` | Anyone (any non-private status) | Poster only |
| `conversations` | Participants only | Participants only |
| `messages` | Conversation participants only | Sender only |

> Service-role keys bypass RLS. Use them only on the server (Edge Functions, admin scripts) — never ship them in the Flutter bundle.

### Banned users — global write block

A helper function `public.user_is_active()` is called from every `INSERT`
**and `UPDATE`** policy (profiles, prayers, prayer_responses, events,
event_rsvps, products, jobs, conversations, messages). It returns `TRUE`
only when the caller has a profile row and `is_banned = FALSE`.

Setting `profiles.is_banned = TRUE` immediately blocks that user from:

- Creating any new content (posts, prayers, products, jobs, messages, RSVPs)
- Editing any existing content they own (including their own profile row,
  so they can't unban themselves)
- Bumping conversation state (typing, last-read markers)

Existing rows stay where they are — clean them up server-side as part of
your moderation workflow. Reads are still permitted (so they can see
their own data) but the discoverability filter on `profiles` hides them
from everyone else.

### Anonymous prayers — read via the view

Prayers stored with `visibility = 'anonymous'` still keep `author_id` on
the row (the author needs it to manage their own post). Clients must read
through the **`public.prayers_public`** view, which masks `author_id`
to `NULL` when `visibility = 'anonymous'`.

```dart
// Flutter — read anonymous-safe prayers
final rows = await supabase.from('prayers_public').select();

// Writes still target the underlying table:
await supabase.from('prayers').insert({...});
```

The view is defined `WITH (security_invoker = on)` so the underlying RLS
on `prayers` (visibility, church_only follower checks) still runs.

### Event approval

Event organizers can edit their own events (title, description, dates,
venue, etc.) but **cannot** change the `status` column themselves —
a `BEFORE UPDATE OF status` trigger raises if a non-service-role caller
tries to flip pending → approved. Admin approval needs to land via:

- a Supabase Edge Function using the service-role key, or
- a separate admin app authenticated as a service account

This is a deliberate placeholder — wire it up to the moderation queue
when that surface ships.

---

## Re-running on an existing database

`schema.sql` is idempotent for tables (`CREATE TABLE IF NOT EXISTS`) and indexes (`CREATE INDEX IF NOT EXISTS`), but **not** for policies and triggers — Postgres will error on duplicate names. Easiest path on a dirty database:

```sql
-- Drop policies / triggers / functions you want to reset, then re-run schema.sql.
-- For a hard reset:
DROP SCHEMA public CASCADE;
CREATE SCHEMA public;
GRANT ALL ON SCHEMA public TO postgres;
GRANT ALL ON SCHEMA public TO anon, authenticated, service_role;
```

For production, manage incremental changes via Supabase migrations (`supabase migration new ...`).

---

## What patch_002 adds

| # | Table | Used by |
|---|---|---|
| 12 | `sellers` | Seller flow (setup, dashboard, edit store, public storefront) |
| 13 | `saved_listings` | Heart-icon saves + `saved_listings_screen` |
| 14 | `church_admins` | `claim_church_screen`, `admin_login_screen`, admin gate |
| 15 | `church_edit_suggestions` | `suggest_edit_screen`, `pending_approvals_screen` |
| 16 | `church_suggestions` | `suggest_church_screen` |
| 17 | `announcements` | `church_announcements_screen`, `admin_dashboard_screen` |
| 18 | `notices` | `post_notice_screen` |
| 19 | `member_directory` | `member_directory_screen`, `my_directory_profile_screen` |
| 20 | `notification_preferences` | `notification_preferences_screen` |
| 21 | `blocked_users` | `blocked_users_screen` |
| 22 | `reports` | "Report this …" flows (seller, etc.) |
| 23 | `notifications` | `notification_centre_screen` + future FCM push |
| 24 | `seller_ratings` | Rating UI on the public seller profile (Stage 13) |
| 25 | `urgent_banners` | Conference / super-admin alerts on home (future) |

Patch 002 also:

- Creates **4 storage buckets** (`profile_photos`, `product_photos`, `event_flyers`, `church_photos`) with public read and per-folder write RLS (users can only upload into `<their uid>/`).
- Wires **DB triggers** that insert into `notifications` whenever someone RSVPs your event, prays for your request, sends you a message, or your seller/church-admin application status changes.

## Still deferred

- `contact_requests`, `member_connections` — connection requests between members (Stage 15 v2)
- `conference_admins`, `admin_audit_log` — super-admin / conference-admin web tooling
- `image_uploads`, `rate_limits` — moderation infra
