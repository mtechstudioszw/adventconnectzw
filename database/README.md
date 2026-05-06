# Advent Connect ZW — Database

Production-ready SQL for the **Advent Connect ZW** Supabase project.

| File | Purpose |
| --- | --- |
| `schema.sql` | All 11 tables, indexes, triggers, and Row-Level-Security policies. **Required.** |
| `seed_data.sql` | Sample data for development / staging. **Optional.** |

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

## What is intentionally **not** in this schema

The full V4 reference defines 31 tables. The following are deferred:

- `church_admins`, `church_edit_suggestions`, `announcements`, `church_suggestions`
- `sellers`, `seller_ratings`, `saved_listings`
- `contact_requests`, `member_connections`
- `member_directory`, `notification_preferences`, `notifications`
- `urgent_banners`, `reports`, `blocked_users`, `notices`
- `image_uploads`, `rate_limits`, `conference_admins`, `admin_audit_log`

They will land in a future schema migration once their corresponding UI surfaces are built out.
