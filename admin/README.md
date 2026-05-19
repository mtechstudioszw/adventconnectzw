# Advent Connect ZW — Admin panel

External operations panel for Advent Connect ZW. Built as a Next.js
14 (App Router) app so it can run locally or on Vercel without
touching the mobile codebase.

## What you can do here

- **Dashboard** — total users, new in 7 days, pending applications,
  active stories, posts, banned users.
- **Business applications** — approve or decline pending business
  account requests. Approving flips `profiles.is_business = true`
  so the user instantly unlocks selling + church claiming inside
  the mobile app.
- **Users** — search by name / username, filter by business / banned,
  ban or unban any account, revoke business privilege.
- **Announcements** — broadcast a message to everyone (or only
  business / personal accounts) at one of two severities. The mobile
  app reads the `admin_announcements` table on launch and pull-to-
  refresh.

## Security model

- Auth is Supabase magic links — passwords are never stored on the
  admin panel.
- Only emails in `ADMIN_EMAILS` (env var, comma-separated) can sign
  in. Anyone else is signed out immediately on the auth callback.
- Every protected page calls `requireAdmin()` server-side. The check
  runs on the server, so a hacked client cannot forge access.
- All database writes happen in **server actions** using the Supabase
  **service role key**. The key never reaches the browser; the
  client sees only the anon key (which can't write past RLS).

## Local setup

```bash
cd admin
cp .env.example .env.local      # fill in real keys
npm install                     # ~150 MB on first run
npm run dev                     # http://localhost:3000
```

Visit `http://localhost:3000`. The first time you go there you'll
be redirected to `/login` — paste your email, click the magic link
in your inbox.

## Hosting on Vercel (recommended)

1. Push this repo to GitHub (already done).
2. In Vercel: New Project → import the repo → **set the Root
   Directory to `admin/`** (Vercel needs to know to ignore the
   Flutter project at the repo root).
3. Add the three environment variables from `.env.example` in the
   Vercel project settings → Environment Variables.
4. Deploy. The dashboard lives at `https://<your-vercel-domain>/`.
5. In Supabase Dashboard → Authentication → URL Configuration, add
   your Vercel domain to the allowed redirect URLs so magic links
   work in production.

## Database migrations this panel needs

Run these in Supabase SQL Editor in order (idempotent — safe to
re-run):

- `database/patch_013_business_accounts.sql` — adds
  `profiles.is_business` and `business_applications`.
- `database/patch_014_admin_announcements.sql` — adds the
  `admin_announcements` table.

## What's not here yet

- **Push notifications** for announcements — the table is the
  source of truth, but FCM delivery to all FCM tokens is a follow-
  up (Supabase Edge function fired by an INSERT trigger).
- **Per-user warnings** — for now, target an announcement at a
  single user-by-audience-tag is not available. Use a direct
  message (Advent Chat) from your own admin account if you need
  to warn one person.
- **Activity / audit log** — currently the only audit trail is
  Supabase's built-in postgres logs.
- **Reports / content moderation queue** — flag-handling for posts
  / stories / messages.

Open an issue / commit a feature when you need any of the above.
