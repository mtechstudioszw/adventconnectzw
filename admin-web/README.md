# Advent Connect ZW — Admin Console (web)

A single-file static admin dashboard for managing the app. Separate from
the consumer Flutter app on purpose: admin code never ships in the APK,
and the heavy desk work (replying to feedback, moderation, broadcasts)
is far nicer on a big screen.

## What it does

| Section | Backed by |
|---|---|
| **Overview** | `admin_overview_stats()` — attention counts |
| **Sellers** | `admin_pending_sellers` / `admin_approve_seller` / `admin_reject_seller` (patch_031/037) |
| **Reports** | `admin_list_reports` / `admin_resolve_report` (patch_040) |
| **Feedback** | `admin_list_feedback` / `admin_reply_feedback` (patch_040) |
| **Church claims** | `admin_list_pending_church_admins` / `admin_approve_church_admin` / `admin_reject_church_admin` (patch_112) |
| **Church admins** | `admin_list_church_admins` / `admin_warn_church_admin` / `admin_revoke_church_admin` (patch_153) |
| **Users** | `admin_search_users` / `admin_set_banned` (patch_040) |
| **Broadcast** | `admin_broadcast` (patch_040) |

> **Church admins** manages *already-approved* admins (vs **Church claims**,
> the pending queue). Removing one sets `church_admins.status='revoked'` —
> a terminal, sticky state: they instantly lose every posting right and the
> in-app re-claim is hard-blocked server-side, so the removal can't be
> bypassed. Only a super admin can re-instate (Re-instate button).

> Seller approve/reject also stays available **in-app** (Settings → Super
> admin → Seller approvals) per the founder's request. Both surfaces call
> the same RPCs.

## Security model

- The page holds only the **public anon key** (same one in the Flutter
  app). It grants nothing on its own.
- Login is email/password via Supabase Auth. After login the page checks
  `profiles.is_super_admin`; if false it signs out immediately.
- **Every** admin RPC is `SECURITY DEFINER` and calls `assert_super_admin()`
  server-side. A normal user (or anon) calling any RPC gets
  `Not authorized` regardless of what the client does. The server is the
  only gate — the UI gating is just UX.
- A super admin cannot ban themselves or another super admin.

## Deploy (Netlify — recommended)

This is one static file. No build step.

**Option A — drag & drop:**
1. Netlify → Add new site → Deploy manually.
2. Drag the `admin-web/` folder onto the drop zone.
3. Done. Bookmark the URL. (Optionally set a custom subdomain like
   `admin.adventconnectzw.netlify.app`.)

**Option B — connect the repo:**
1. New site from Git → pick this repo.
2. Build command: *(none)*. Publish directory: `admin-web`.

### Lock it down further (optional but recommended)
- Netlify → Site settings → **Password protection** (or Netlify Identity)
  so the login page itself isn't publicly reachable. Even without it the
  RPC guard protects all data — this just hides the door.
- The page sets `noindex,nofollow` so search engines skip it.

## Local use
Just open `index.html` in a browser — it talks to the live Supabase
project directly. (Supabase Auth allows the `file://` / localhost origin
for password sign-in.)
