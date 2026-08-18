# Adventist Super App — Web Admin Console

Next.js 14 (App Router) + Supabase. Replaces the single-file
`admin-web/index.html`, which stays live and untouched until this is signed
off.

## Run it

```bash
cd admin
cp .env.example .env.local     # then paste the anon key
npm install
npm run dev                    # http://localhost:3000
```

Deploy target is **Vercel**. Set the same two variables in the project
settings; there is nothing else to configure.

## Security model — read this before adding anything

- The bundle holds only the **public anon key**, the same one shipped inside
  the Flutter app. It grants nothing on its own.
- Every `admin_*` function is `SECURITY DEFINER` and calls `assert_staff(...)`
  or `assert_super_admin()`. **The database decides what you can do**, not
  this app. The role gating in the UI only hides controls that would fail
  anyway.
- There is **no service-role key**, and no server action wrapping one. The
  previous version of this console had one plus an `ADMIN_EMAILS` allowlist;
  both are gone. A service-role key bypasses RLS entirely and buys nothing
  here, because the RPCs already do the work.
- Every mutating action is written to the audit log with the actor's name.

## Roles

Set in `staff_members`, from `20260803150000_staff_roles_and_audit.sql`:

| Role | Can |
|---|---|
| `viewer` | Read everything, change nothing |
| `moderator` | Clear the queues. **Contact details are hidden** |
| `manager` | + contact details, audit log, join/leave insights |
| `owner` | + ban, broadcast, maintenance, staff roles |

`current_staff_role()` folds in the legacy `profiles.is_super_admin` flag, so
the founder's account works without a `staff_members` row.

`admin_set_staff_role` refuses to demote the **last owner** (23514). Without
that guard one click locks everyone out permanently — there is no way back in
from the app.

## Sections

| Route | Backed by |
|---|---|
| `/` | `admin_overview_stats`, `admin_usage_stats` |
| `/reports` | `admin_list_reports`, `admin_resolve_report`, `admin_reply_report` |
| `/feedback` | `admin_list_feedback`, `admin_reply_feedback` |
| `/sellers` | `admin_pending_sellers`, `admin_approve_seller`, `admin_reject_seller` |
| `/news` `/events` `/jobs` | `admin_list_pending_*`, `admin_approve_*`, `admin_reject_*` |
| `/church-claims` | `admin_list_pending_church_admins`, `admin_approve_church_admin`, `admin_reject_church_admin` |
| `/church-admins` | `admin_list_church_admins`, `admin_warn_church_admin`, `admin_revoke_church_admin` |
| `/users` | `admin_search_users`, `admin_set_banned`, `admin_notify_user` |
| `/watch` | `admin_list_youtube_*`, `admin_add_youtube_channel`, `admin_review_youtube_submission` |
| `/analytics` | `admin_usage_stats`, `admin_feature_usage`, `admin_active_users_series`, `admin_platform_breakdown`, `admin_premium_stats` |
| `/insights` | `admin_survey_summary`, `admin_deletion_reasons` |
| `/broadcast` | `admin_broadcast` |
| `/maintenance` | `maintenance_status`, `admin_set_maintenance` |
| `/staff` | `admin_list_staff`, `admin_set_staff_role` |
| `/audit` | `admin_list_audit_log` |

## Known state of the data

**`app_events` is empty.** The usage-analytics tables and RPCs
(`20260803140000_usage_analytics.sql`) are live in production, but the app is
not sending events to them yet, so "which features get used" has no data. The
Analytics page says so explicitly rather than drawing empty bars — a zero from
an instrument that is switched off is not the same claim as a zero from an
instrument that is working. Everything else on that page is counted from real
content tables and is accurate.

## Maintenance mode

`/maintenance` is the switch. Turning it **on** requires typing `OFFLINE`;
turning it **off** is one click, because recovery must always be easier than
the mistake. While it is on, a red banner follows you across every page.

The block itself is a **database trigger** on 26 content tables
(`patch_187`), not a screen — a modified client gets every write refused.
Super admins are exempt so the outage can be fixed. `patch_198` added a
`blocked` column to `maintenance_status()` so the app can tell "maintenance is
on" from "*I* am shut out"; without it the founder's own app gated them out.

## No Tailwind

Styling is one `globals.css` with design tokens taken from `CLAUDE.md`. About
twenty screens share a dozen shapes; a tokens file plus semantic class names
reads better a year from now than the same shapes rebuilt out of utility
classes on every page, and it keeps the build to `next` + `react`.
