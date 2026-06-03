-- =====================================================================
--  PRE-LAUNCH CONTENT WIPE
--
--  Purpose: clear every piece of user-authored content + the social
--  derivatives that depend on it, so the app launches with a clean
--  slate. KEEPS:
--    - auth.users (so testers/founders don't have to re-create accounts)
--    - public.profiles (preserves names, photos, biometric state, etc.)
--    - public.churches (curated directory — not user content)
--    - public.church_followers (preserves the user's home-church pick)
--    - public.friendships (preserves social graph from internal testing)
--    - public.notification_preferences (preserves per-user toggles)
--    - public.blocked_users (preserves block lists)
--    - public.rate_limits (housekeeping, will auto-expire)
--    - public.feedback (internal testing feedback worth keeping)
--    - public.reports (admin moderation history — keep)
--    - public.admin_announcements / urgent_banners (admin-authored, keep)
--
--  WIPES the actual user-facing content tables. TRUNCATE … CASCADE is
--  used so FK dependents (likes / comments / reactions / RSVPs /
--  views / responses) clear in a single shot without explicit DELETEs.
--
--  Order matters only when CASCADE isn't used. With CASCADE, postgres
--  walks the FK graph itself, but listing dependents explicitly first
--  makes the operation deterministic if a future migration drops
--  ON DELETE CASCADE somewhere.
--
--  HOW TO RUN
--  ----------
--    1. Take a backup. (Supabase dashboard → Database → Backups.)
--    2. Open the SQL editor in the Supabase dashboard.
--    3. Paste this file and Run.
--    4. Verify with the counts query at the bottom.
--
--  REVERSIBILITY: none. Restore from backup if you need the data.
--  IDEMPOTENT: yes — re-running is a no-op against an already-wiped
--              database.
-- =====================================================================

BEGIN;

-- ----- Derivative tables (likes / reactions / views / RSVPs / replies)
-- Listed FIRST so a TRUNCATE on the parent doesn't have to cascade.
TRUNCATE TABLE
  public.post_likes,
  public.post_comment_reactions,
  public.post_comments,
  public.prayer_responses,
  public.event_rsvps,
  public.story_views,
  public.seller_ratings,
  public.saved_listings
RESTART IDENTITY CASCADE;

-- ----- Primary user content -----------------------------------------
TRUNCATE TABLE
  public.posts,
  public.stories,
  public.events,
  public.advent_news,
  public.prayers,
  public.products,
  public.jobs,
  public.notices,
  public.announcements
RESTART IDENTITY CASCADE;

-- ----- Messaging (conversations + their messages) -------------------
-- conversations → messages via FK. Truncating conversations CASCADE
-- clears messages too, but listing both keeps the operation explicit.
TRUNCATE TABLE
  public.messages,
  public.conversations
RESTART IDENTITY CASCADE;

-- ----- Notifications (all stale references would be broken now) -----
TRUNCATE TABLE public.notifications RESTART IDENTITY CASCADE;

-- ----- Curated suggestions that piled up during testing -------------
-- These are user-submitted edits / claims that have no audience
-- post-launch — better to start fresh than ship pre-launch noise.
TRUNCATE TABLE
  public.church_suggestions,
  public.church_edit_suggestions,
  public.business_applications
RESTART IDENTITY CASCADE;

COMMIT;

-- ----- Verification -------------------------------------------------
-- Expected: every row below is 0. Anything non-zero either means a
-- table got added between drafting + running this file, or CASCADE
-- skipped it because the FK didn't have ON DELETE CASCADE.
SELECT 'posts'                AS table, COUNT(*) FROM public.posts
UNION ALL SELECT 'stories',                    COUNT(*) FROM public.stories
UNION ALL SELECT 'events',                     COUNT(*) FROM public.events
UNION ALL SELECT 'advent_news',                COUNT(*) FROM public.advent_news
UNION ALL SELECT 'prayers',                    COUNT(*) FROM public.prayers
UNION ALL SELECT 'prayer_responses',           COUNT(*) FROM public.prayer_responses
UNION ALL SELECT 'products',                   COUNT(*) FROM public.products
UNION ALL SELECT 'jobs',                       COUNT(*) FROM public.jobs
UNION ALL SELECT 'post_comments',              COUNT(*) FROM public.post_comments
UNION ALL SELECT 'post_likes',                 COUNT(*) FROM public.post_likes
UNION ALL SELECT 'post_comment_reactions',     COUNT(*) FROM public.post_comment_reactions
UNION ALL SELECT 'conversations',              COUNT(*) FROM public.conversations
UNION ALL SELECT 'messages',                   COUNT(*) FROM public.messages
UNION ALL SELECT 'notifications',              COUNT(*) FROM public.notifications
UNION ALL SELECT 'event_rsvps',                COUNT(*) FROM public.event_rsvps
UNION ALL SELECT 'story_views',                COUNT(*) FROM public.story_views
UNION ALL SELECT 'seller_ratings',             COUNT(*) FROM public.seller_ratings
UNION ALL SELECT 'saved_listings',             COUNT(*) FROM public.saved_listings
UNION ALL SELECT 'notices',                    COUNT(*) FROM public.notices
UNION ALL SELECT 'announcements',              COUNT(*) FROM public.announcements
UNION ALL SELECT 'church_suggestions',         COUNT(*) FROM public.church_suggestions
UNION ALL SELECT 'church_edit_suggestions',    COUNT(*) FROM public.church_edit_suggestions
UNION ALL SELECT 'business_applications',      COUNT(*) FROM public.business_applications
-- Tables we INTENTIONALLY KEPT — these should NOT be zero.
UNION ALL SELECT 'profiles (kept)',            COUNT(*) FROM public.profiles
UNION ALL SELECT 'churches (kept)',            COUNT(*) FROM public.churches
UNION ALL SELECT 'church_followers (kept)',    COUNT(*) FROM public.church_followers
UNION ALL SELECT 'friendships (kept)',         COUNT(*) FROM public.friendships
UNION ALL SELECT 'sellers (kept)',             COUNT(*) FROM public.sellers
ORDER BY table;
