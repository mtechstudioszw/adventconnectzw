-- =====================================================================
--  PATCH 002 — Round out V4 schema for the seller, profile, churches,
--              admin, notifications and moderation surfaces
--
--  WHY:  The original schema.sql shipped the 11 "core" tables (churches,
--        profiles, events, event_rsvps, church_followers, prayers,
--        prayer_responses, products, jobs, conversations, messages).
--        The seller flow, member directory, in-app notifications,
--        moderation, church-admin claim flow, community notices and
--        block list all reference tables that don't exist yet, so the
--        Flutter app would 404 against them.
--
--  WHAT: Adds 14 tables (sellers, saved_listings, announcements,
--        church_admins, church_edit_suggestions, church_suggestions,
--        notices, member_directory, notification_preferences,
--        blocked_users, reports, notifications, seller_ratings,
--        urgent_banners), their indexes, RLS, and policies.
--
--  IDEMPOTENT: yes — uses IF NOT EXISTS and re-creatable policies. Run
--              as many times as you need; existing rows are untouched.
-- =====================================================================


-- =====================================================================
--  SECTION 1 — TABLES
-- =====================================================================

-- ----- sellers (Table 10) -------------------------------------------
-- One row per user who applied to sell on the marketplace. status moves
-- pending → approved → rejected. Admins approve via web dashboard.
CREATE TABLE IF NOT EXISTS public.sellers (
  id                      BIGSERIAL PRIMARY KEY,
  auth_user_id            UUID NOT NULL UNIQUE REFERENCES public.profiles(id) ON DELETE CASCADE,
  business_name           TEXT NOT NULL,
  category                TEXT NOT NULL,
  description             TEXT,
  province                TEXT,
  city                    TEXT,
  suburb                  TEXT,
  address                 TEXT,
  phone                   TEXT NOT NULL,
  whatsapp                TEXT,
  contact_name            TEXT,
  profile_photo_url       TEXT,
  payment_methods         TEXT,
  offers_delivery         BOOLEAN NOT NULL DEFAULT FALSE,
  delivery_area           TEXT,
  delivery_fee            TEXT,
  status                  TEXT NOT NULL DEFAULT 'pending'
                            CHECK (status IN ('pending','approved','rejected')),
  rejection_reason        TEXT,
  verified                BOOLEAN NOT NULL DEFAULT FALSE,
  sda_verified            BOOLEAN NOT NULL DEFAULT FALSE,
  featured                BOOLEAN NOT NULL DEFAULT FALSE,
  rating                  DECIMAL(3,2) NOT NULL DEFAULT 0 CHECK (rating BETWEEN 0 AND 5),
  rating_count            INTEGER NOT NULL DEFAULT 0 CHECK (rating_count >= 0),
  is_active               BOOLEAN NOT NULL DEFAULT TRUE,
  approved_at             TIMESTAMPTZ,
  observes_sabbath        BOOLEAN NOT NULL DEFAULT FALSE,
  sabbath_notice_text     TEXT,
  created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_sellers_auth_user_id   ON public.sellers (auth_user_id);
CREATE INDEX IF NOT EXISTS idx_sellers_status         ON public.sellers (status);
CREATE INDEX IF NOT EXISTS idx_sellers_category       ON public.sellers (category);
CREATE INDEX IF NOT EXISTS idx_sellers_featured       ON public.sellers (featured) WHERE featured = TRUE;


-- ----- saved_listings (Table 13) ------------------------------------
-- Heart-icon save list. (user_id, product_id) is unique so a user can
-- only save the same product once.
CREATE TABLE IF NOT EXISTS public.saved_listings (
  id                      BIGSERIAL PRIMARY KEY,
  user_id                 UUID   NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  product_id              BIGINT NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT saved_listings_unique UNIQUE (user_id, product_id)
);

CREATE INDEX IF NOT EXISTS idx_saved_listings_user_id ON public.saved_listings (user_id);


-- ----- church_admins (Table 4) --------------------------------------
-- A user's role at a church. Primary admin = full control, one per
-- church. Standard admin = can post content. status moves pending →
-- approved → rejected.
CREATE TABLE IF NOT EXISTS public.church_admins (
  id                      BIGSERIAL PRIMARY KEY,
  church_id               BIGINT NOT NULL REFERENCES public.churches(id) ON DELETE CASCADE,
  user_id                 UUID   NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  role                    TEXT NOT NULL DEFAULT 'standard'
                            CHECK (role IN ('primary','standard')),
  appointment_letter_url  TEXT,
  status                  TEXT NOT NULL DEFAULT 'pending'
                            CHECK (status IN ('pending','approved','rejected')),
  rejection_reason        TEXT,
  approved_at             TIMESTAMPTZ,
  created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT church_admins_unique UNIQUE (church_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_church_admins_church_id ON public.church_admins (church_id);
CREATE INDEX IF NOT EXISTS idx_church_admins_user_id   ON public.church_admins (user_id);
CREATE INDEX IF NOT EXISTS idx_church_admins_status    ON public.church_admins (status);

-- Enforce "one primary admin per church" at write time. Pending and
-- rejected rows don't block — only approved primaries.
CREATE UNIQUE INDEX IF NOT EXISTS idx_church_admins_one_primary_per_church
  ON public.church_admins (church_id)
  WHERE role = 'primary' AND status = 'approved';


-- ----- church_edit_suggestions (Table 5) ----------------------------
-- Crowd-sourced corrections. Status moves pending → approved/rejected
-- by an admin. Approved → applied to the church via service_role.
CREATE TABLE IF NOT EXISTS public.church_edit_suggestions (
  id                      BIGSERIAL PRIMARY KEY,
  church_id               BIGINT NOT NULL REFERENCES public.churches(id) ON DELETE CASCADE,
  suggested_by            UUID   NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  field_name              TEXT NOT NULL,
  current_value           TEXT,
  suggested_value         TEXT NOT NULL,
  status                  TEXT NOT NULL DEFAULT 'pending'
                            CHECK (status IN ('pending','approved','rejected')),
  reviewed_by             UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  reviewed_at             TIMESTAMPTZ,
  created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ces_church_id ON public.church_edit_suggestions (church_id);
CREATE INDEX IF NOT EXISTS idx_ces_status    ON public.church_edit_suggestions (status);


-- ----- church_suggestions (Table 7) ---------------------------------
-- Propose a brand-new church to the directory.
CREATE TABLE IF NOT EXISTS public.church_suggestions (
  id                      BIGSERIAL PRIMARY KEY,
  suggested_by            UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  church_name             TEXT NOT NULL,
  province                TEXT,
  city                    TEXT,
  suburb                  TEXT,
  pastor_name             TEXT,
  contact_phone           TEXT,
  status                  TEXT NOT NULL DEFAULT 'pending'
                            CHECK (status IN ('pending','approved','rejected')),
  reviewed_by             UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  reviewed_at             TIMESTAMPTZ,
  created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_church_suggestions_status ON public.church_suggestions (status);


-- ----- announcements (Table 6) --------------------------------------
-- Per-church feed posted by approved admins.
CREATE TABLE IF NOT EXISTS public.announcements (
  id                      BIGSERIAL PRIMARY KEY,
  church_id               BIGINT NOT NULL REFERENCES public.churches(id) ON DELETE CASCADE,
  posted_by               UUID   NOT NULL REFERENCES public.profiles(id) ON DELETE SET NULL,
  title                   TEXT NOT NULL,
  body                    TEXT NOT NULL,
  category                TEXT NOT NULL DEFAULT 'general'
                            CHECK (category IN ('general','urgent','obituary','event','program')),
  is_pinned               BOOLEAN NOT NULL DEFAULT FALSE,
  is_broadcast            BOOLEAN NOT NULL DEFAULT FALSE,
  publish_at              TIMESTAMPTZ,
  expires_at              TIMESTAMPTZ,
  view_count              INTEGER NOT NULL DEFAULT 0 CHECK (view_count >= 0),
  created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_announcements_church_id  ON public.announcements (church_id);
CREATE INDEX IF NOT EXISTS idx_announcements_created_at ON public.announcements (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_announcements_pinned     ON public.announcements (is_pinned) WHERE is_pinned = TRUE;
CREATE INDEX IF NOT EXISTS idx_announcements_expires    ON public.announcements (expires_at) WHERE expires_at IS NOT NULL;


-- ----- notices (Table 27) -------------------------------------------
-- Cross-community board posted from the Home tab.
CREATE TABLE IF NOT EXISTS public.notices (
  id                      BIGSERIAL PRIMARY KEY,
  posted_by               UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  title                   TEXT NOT NULL,
  body                    TEXT NOT NULL,
  category                TEXT NOT NULL DEFAULT 'general'
                            CHECK (category IN (
                              'general','lost_and_found','accommodation',
                              'transport','congratulations','other'
                            )),
  is_resolved             BOOLEAN NOT NULL DEFAULT FALSE,
  created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_notices_created_at ON public.notices (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notices_category   ON public.notices (category);


-- ----- member_directory (Table 21) ----------------------------------
-- Opt-in profession/skills listing. Unique on user_id so each member
-- has at most one row.
CREATE TABLE IF NOT EXISTS public.member_directory (
  id                      BIGSERIAL PRIMARY KEY,
  user_id                 UUID NOT NULL UNIQUE REFERENCES public.profiles(id) ON DELETE CASCADE,
  profession              TEXT,
  skills                  TEXT,
  church_id               BIGINT REFERENCES public.churches(id) ON DELETE SET NULL,
  province                TEXT,
  city                    TEXT,
  bio                     TEXT,
  is_visible              BOOLEAN NOT NULL DEFAULT TRUE,
  created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_member_directory_visible    ON public.member_directory (is_visible) WHERE is_visible = TRUE;
CREATE INDEX IF NOT EXISTS idx_member_directory_province   ON public.member_directory (province);
CREATE INDEX IF NOT EXISTS idx_member_directory_profession ON public.member_directory (profession);


-- ----- notification_preferences (Table 22) --------------------------
-- Per-church notification level. (user_id, church_id) is unique.
CREATE TABLE IF NOT EXISTS public.notification_preferences (
  id                      BIGSERIAL PRIMARY KEY,
  user_id                 UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  church_id               BIGINT NOT NULL REFERENCES public.churches(id) ON DELETE CASCADE,
  all_notifications       BOOLEAN NOT NULL DEFAULT TRUE,
  urgent_only             BOOLEAN NOT NULL DEFAULT FALSE,
  none                    BOOLEAN NOT NULL DEFAULT FALSE,
  created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT notification_preferences_unique UNIQUE (user_id, church_id)
);

CREATE INDEX IF NOT EXISTS idx_notif_prefs_user_id ON public.notification_preferences (user_id);


-- ----- blocked_users (Table 26) -------------------------------------
CREATE TABLE IF NOT EXISTS public.blocked_users (
  id                      BIGSERIAL PRIMARY KEY,
  blocker_id              UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  blocked_id              UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT blocked_users_unique  UNIQUE (blocker_id, blocked_id),
  CONSTRAINT blocked_users_not_self CHECK (blocker_id <> blocked_id)
);

CREATE INDEX IF NOT EXISTS idx_blocked_users_blocker ON public.blocked_users (blocker_id);
CREATE INDEX IF NOT EXISTS idx_blocked_users_blocked ON public.blocked_users (blocked_id);


-- ----- reports (Table 25) -------------------------------------------
CREATE TABLE IF NOT EXISTS public.reports (
  id                      BIGSERIAL PRIMARY KEY,
  reported_by             UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  content_type            TEXT NOT NULL,
  content_id              TEXT NOT NULL,
  reason                  TEXT NOT NULL,
  details                 TEXT,
  status                  TEXT NOT NULL DEFAULT 'pending'
                            CHECK (status IN ('pending','reviewing','actioned','dismissed')),
  reviewed_by             UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  reviewed_at             TIMESTAMPTZ,
  action_taken            TEXT,
  created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_reports_status       ON public.reports (status);
CREATE INDEX IF NOT EXISTS idx_reports_content      ON public.reports (content_type, content_id);


-- ----- notifications (Table 23) -------------------------------------
-- In-app notification feed. FCM push uses the same rows (one feed,
-- many channels) so the user sees a consistent inbox.
CREATE TABLE IF NOT EXISTS public.notifications (
  id                      BIGSERIAL PRIMARY KEY,
  user_id                 UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  title                   TEXT NOT NULL,
  body                    TEXT NOT NULL,
  type                    TEXT NOT NULL DEFAULT 'general',
  reference_id            TEXT,
  reference_type          TEXT,
  is_read                 BOOLEAN NOT NULL DEFAULT FALSE,
  read_at                 TIMESTAMPTZ,
  created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_notifications_user_unread
  ON public.notifications (user_id, created_at DESC) WHERE is_read = FALSE;
CREATE INDEX IF NOT EXISTS idx_notifications_user
  ON public.notifications (user_id, created_at DESC);


-- ----- seller_ratings (Table 12) ------------------------------------
-- One rating per (seller, rater). Trigger keeps sellers.rating and
-- rating_count in sync.
CREATE TABLE IF NOT EXISTS public.seller_ratings (
  id                      BIGSERIAL PRIMARY KEY,
  seller_id               BIGINT NOT NULL REFERENCES public.sellers(id) ON DELETE CASCADE,
  rated_by                UUID   NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  rating                  INTEGER NOT NULL CHECK (rating BETWEEN 1 AND 5),
  review                  TEXT,
  created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT seller_ratings_unique UNIQUE (seller_id, rated_by)
);

CREATE INDEX IF NOT EXISTS idx_seller_ratings_seller_id ON public.seller_ratings (seller_id);


-- ----- urgent_banners (Table 24) ------------------------------------
-- Conference- or nationwide-level alerts shown on the home screen.
-- Only super_admin / conference_admin posts; everyone reads.
CREATE TABLE IF NOT EXISTS public.urgent_banners (
  id                      BIGSERIAL PRIMARY KEY,
  posted_by               UUID NOT NULL REFERENCES public.profiles(id) ON DELETE SET NULL,
  conference              TEXT,
  title                   TEXT NOT NULL CHECK (char_length(title) <= 60),
  body                    TEXT NOT NULL CHECK (char_length(body) <= 200),
  is_active               BOOLEAN NOT NULL DEFAULT TRUE,
  expires_at              TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '48 hours'),
  deactivated_at          TIMESTAMPTZ,
  deactivated_by          UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_urgent_banners_active
  ON public.urgent_banners (created_at DESC) WHERE is_active = TRUE;


-- =====================================================================
--  SECTION 2 — UPDATED_AT TRIGGERS
-- =====================================================================

DROP TRIGGER IF EXISTS trg_sellers_updated_at ON public.sellers;
CREATE TRIGGER trg_sellers_updated_at BEFORE UPDATE ON public.sellers
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_announcements_updated_at ON public.announcements;
CREATE TRIGGER trg_announcements_updated_at BEFORE UPDATE ON public.announcements
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_notices_updated_at ON public.notices;
CREATE TRIGGER trg_notices_updated_at BEFORE UPDATE ON public.notices
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_member_directory_updated_at ON public.member_directory;
CREATE TRIGGER trg_member_directory_updated_at BEFORE UPDATE ON public.member_directory
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_notification_preferences_updated_at ON public.notification_preferences;
CREATE TRIGGER trg_notification_preferences_updated_at BEFORE UPDATE ON public.notification_preferences
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_church_admins_updated_at ON public.church_admins;
CREATE TRIGGER trg_church_admins_updated_at BEFORE UPDATE ON public.church_admins
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


-- =====================================================================
--  SECTION 3 — HELPER: is the caller an approved admin of <church>?
--  Used by the announcements + church_edit_suggestions UPDATE policies.
-- =====================================================================
CREATE OR REPLACE FUNCTION public.is_approved_church_admin(p_church_id BIGINT)
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.church_admins
    WHERE church_id = p_church_id
      AND user_id = auth.uid()
      AND status = 'approved'
  );
$$ LANGUAGE SQL STABLE SECURITY DEFINER SET search_path = public;


-- =====================================================================
--  SECTION 4 — SELLER RATING ROLLUP
-- =====================================================================
CREATE OR REPLACE FUNCTION public.recompute_seller_rating()
RETURNS TRIGGER AS $$
DECLARE
  s_id BIGINT := COALESCE(NEW.seller_id, OLD.seller_id);
BEGIN
  UPDATE public.sellers
     SET rating_count = (
           SELECT COUNT(*) FROM public.seller_ratings WHERE seller_id = s_id
         ),
         rating = COALESCE((
           SELECT AVG(rating)::DECIMAL(3,2)
           FROM public.seller_ratings WHERE seller_id = s_id
         ), 0)
   WHERE id = s_id;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_seller_ratings_rollup ON public.seller_ratings;
CREATE TRIGGER trg_seller_ratings_rollup
  AFTER INSERT OR UPDATE OR DELETE ON public.seller_ratings
  FOR EACH ROW EXECUTE FUNCTION public.recompute_seller_rating();


-- =====================================================================
--  SECTION 5 — ENABLE ROW LEVEL SECURITY
-- =====================================================================
ALTER TABLE public.sellers                   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.saved_listings            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.church_admins             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.church_edit_suggestions   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.church_suggestions        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.announcements             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notices                   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.member_directory          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_preferences  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.blocked_users             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reports                   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.seller_ratings            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.urgent_banners            ENABLE ROW LEVEL SECURITY;


-- =====================================================================
--  SECTION 6 — POLICIES
--
--  Use DROP-then-CREATE so re-running the patch refreshes policies.
-- =====================================================================

-- ----- sellers -------------------------------------------------------
-- Anyone authenticated can browse approved sellers. Owners always see
-- their own row (pending / rejected included).
DROP POLICY IF EXISTS "sellers_select_visible"  ON public.sellers;
DROP POLICY IF EXISTS "sellers_insert_self"     ON public.sellers;
DROP POLICY IF EXISTS "sellers_update_self"     ON public.sellers;
DROP POLICY IF EXISTS "sellers_delete_self"     ON public.sellers;

CREATE POLICY "sellers_select_visible" ON public.sellers
  FOR SELECT USING (
    status = 'approved' OR auth_user_id = auth.uid()
  );

CREATE POLICY "sellers_insert_self" ON public.sellers
  FOR INSERT WITH CHECK (
    auth.uid() = auth_user_id AND public.user_is_active()
  );

CREATE POLICY "sellers_update_self" ON public.sellers
  FOR UPDATE USING (auth.uid() = auth_user_id AND public.user_is_active())
              WITH CHECK (auth.uid() = auth_user_id AND public.user_is_active());

CREATE POLICY "sellers_delete_self" ON public.sellers
  FOR DELETE USING (auth.uid() = auth_user_id);


-- ----- saved_listings (private to the saver) -------------------------
DROP POLICY IF EXISTS "saved_listings_select_self" ON public.saved_listings;
DROP POLICY IF EXISTS "saved_listings_insert_self" ON public.saved_listings;
DROP POLICY IF EXISTS "saved_listings_delete_self" ON public.saved_listings;

CREATE POLICY "saved_listings_select_self" ON public.saved_listings
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "saved_listings_insert_self" ON public.saved_listings
  FOR INSERT WITH CHECK (auth.uid() = user_id AND public.user_is_active());

CREATE POLICY "saved_listings_delete_self" ON public.saved_listings
  FOR DELETE USING (auth.uid() = user_id);


-- ----- church_admins -------------------------------------------------
-- Approved admins are public knowledge (you can see who runs a church).
-- Pending / rejected rows are visible only to the applicant.
DROP POLICY IF EXISTS "church_admins_select_visible" ON public.church_admins;
DROP POLICY IF EXISTS "church_admins_insert_self"    ON public.church_admins;
DROP POLICY IF EXISTS "church_admins_update_self"    ON public.church_admins;
DROP POLICY IF EXISTS "church_admins_delete_self"    ON public.church_admins;

CREATE POLICY "church_admins_select_visible" ON public.church_admins
  FOR SELECT USING (
    status = 'approved' OR user_id = auth.uid()
  );

CREATE POLICY "church_admins_insert_self" ON public.church_admins
  FOR INSERT WITH CHECK (
    auth.uid() = user_id AND public.user_is_active()
  );

-- An applicant can update fields like the appointment letter URL while
-- still pending. status changes only via service_role.
CREATE POLICY "church_admins_update_self" ON public.church_admins
  FOR UPDATE USING (auth.uid() = user_id AND status = 'pending'
                    AND public.user_is_active())
              WITH CHECK (auth.uid() = user_id AND status = 'pending'
                          AND public.user_is_active());

CREATE POLICY "church_admins_delete_self" ON public.church_admins
  FOR DELETE USING (auth.uid() = user_id);


-- ----- church_edit_suggestions ---------------------------------------
-- Anyone can write a suggestion. Reading is restricted to admin of the
-- church plus the original suggester (so they can see their pending
-- queue). status changes happen via admin update.
DROP POLICY IF EXISTS "ces_select_admin_or_self"     ON public.church_edit_suggestions;
DROP POLICY IF EXISTS "ces_insert_self"              ON public.church_edit_suggestions;
DROP POLICY IF EXISTS "ces_update_admin"             ON public.church_edit_suggestions;

CREATE POLICY "ces_select_admin_or_self" ON public.church_edit_suggestions
  FOR SELECT USING (
    suggested_by = auth.uid()
    OR public.is_approved_church_admin(church_id)
  );

CREATE POLICY "ces_insert_self" ON public.church_edit_suggestions
  FOR INSERT WITH CHECK (
    auth.uid() = suggested_by AND public.user_is_active()
  );

CREATE POLICY "ces_update_admin" ON public.church_edit_suggestions
  FOR UPDATE USING (public.is_approved_church_admin(church_id))
              WITH CHECK (public.is_approved_church_admin(church_id));


-- ----- church_suggestions --------------------------------------------
DROP POLICY IF EXISTS "church_sugg_select_self_or_service" ON public.church_suggestions;
DROP POLICY IF EXISTS "church_sugg_insert_self"            ON public.church_suggestions;

CREATE POLICY "church_sugg_select_self_or_service" ON public.church_suggestions
  FOR SELECT USING (auth.uid() = suggested_by);

CREATE POLICY "church_sugg_insert_self" ON public.church_suggestions
  FOR INSERT WITH CHECK (
    auth.uid() = suggested_by AND public.user_is_active()
  );


-- ----- announcements -------------------------------------------------
-- Read: anyone authenticated. Write: only approved admins for THAT church.
DROP POLICY IF EXISTS "announcements_select_all"   ON public.announcements;
DROP POLICY IF EXISTS "announcements_insert_admin" ON public.announcements;
DROP POLICY IF EXISTS "announcements_update_admin" ON public.announcements;
DROP POLICY IF EXISTS "announcements_delete_admin" ON public.announcements;

CREATE POLICY "announcements_select_all" ON public.announcements
  FOR SELECT USING (auth.role() = 'authenticated');

CREATE POLICY "announcements_insert_admin" ON public.announcements
  FOR INSERT WITH CHECK (
    auth.uid() = posted_by
    AND public.is_approved_church_admin(church_id)
    AND public.user_is_active()
  );

CREATE POLICY "announcements_update_admin" ON public.announcements
  FOR UPDATE USING (public.is_approved_church_admin(church_id))
              WITH CHECK (public.is_approved_church_admin(church_id));

CREATE POLICY "announcements_delete_admin" ON public.announcements
  FOR DELETE USING (public.is_approved_church_admin(church_id));


-- ----- notices -------------------------------------------------------
DROP POLICY IF EXISTS "notices_select_all"     ON public.notices;
DROP POLICY IF EXISTS "notices_insert_self"    ON public.notices;
DROP POLICY IF EXISTS "notices_update_self"    ON public.notices;
DROP POLICY IF EXISTS "notices_delete_self"    ON public.notices;

CREATE POLICY "notices_select_all" ON public.notices
  FOR SELECT USING (auth.role() = 'authenticated');

CREATE POLICY "notices_insert_self" ON public.notices
  FOR INSERT WITH CHECK (
    auth.uid() = posted_by AND public.user_is_active()
  );

CREATE POLICY "notices_update_self" ON public.notices
  FOR UPDATE USING (auth.uid() = posted_by AND public.user_is_active())
              WITH CHECK (auth.uid() = posted_by AND public.user_is_active());

CREATE POLICY "notices_delete_self" ON public.notices
  FOR DELETE USING (auth.uid() = posted_by);


-- ----- member_directory ----------------------------------------------
-- Public read of visible rows + always-self. Owners write their own.
DROP POLICY IF EXISTS "md_select_visible_or_self" ON public.member_directory;
DROP POLICY IF EXISTS "md_upsert_self"            ON public.member_directory;
DROP POLICY IF EXISTS "md_update_self"            ON public.member_directory;
DROP POLICY IF EXISTS "md_delete_self"            ON public.member_directory;

CREATE POLICY "md_select_visible_or_self" ON public.member_directory
  FOR SELECT USING (is_visible = TRUE OR user_id = auth.uid());

CREATE POLICY "md_upsert_self" ON public.member_directory
  FOR INSERT WITH CHECK (
    auth.uid() = user_id AND public.user_is_active()
  );

CREATE POLICY "md_update_self" ON public.member_directory
  FOR UPDATE USING (auth.uid() = user_id AND public.user_is_active())
              WITH CHECK (auth.uid() = user_id AND public.user_is_active());

CREATE POLICY "md_delete_self" ON public.member_directory
  FOR DELETE USING (auth.uid() = user_id);


-- ----- notification_preferences (private to the user) ----------------
DROP POLICY IF EXISTS "np_select_self"  ON public.notification_preferences;
DROP POLICY IF EXISTS "np_upsert_self"  ON public.notification_preferences;
DROP POLICY IF EXISTS "np_update_self"  ON public.notification_preferences;
DROP POLICY IF EXISTS "np_delete_self"  ON public.notification_preferences;

CREATE POLICY "np_select_self" ON public.notification_preferences
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "np_upsert_self" ON public.notification_preferences
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "np_update_self" ON public.notification_preferences
  FOR UPDATE USING (auth.uid() = user_id)
              WITH CHECK (auth.uid() = user_id);

CREATE POLICY "np_delete_self" ON public.notification_preferences
  FOR DELETE USING (auth.uid() = user_id);


-- ----- blocked_users (private to the blocker) ------------------------
DROP POLICY IF EXISTS "blocked_users_select_self" ON public.blocked_users;
DROP POLICY IF EXISTS "blocked_users_insert_self" ON public.blocked_users;
DROP POLICY IF EXISTS "blocked_users_delete_self" ON public.blocked_users;

CREATE POLICY "blocked_users_select_self" ON public.blocked_users
  FOR SELECT USING (auth.uid() = blocker_id);

CREATE POLICY "blocked_users_insert_self" ON public.blocked_users
  FOR INSERT WITH CHECK (auth.uid() = blocker_id);

CREATE POLICY "blocked_users_delete_self" ON public.blocked_users
  FOR DELETE USING (auth.uid() = blocker_id);


-- ----- reports (write-only for users, read for admins on web) --------
DROP POLICY IF EXISTS "reports_select_self" ON public.reports;
DROP POLICY IF EXISTS "reports_insert_self" ON public.reports;

CREATE POLICY "reports_select_self" ON public.reports
  FOR SELECT USING (auth.uid() = reported_by);

CREATE POLICY "reports_insert_self" ON public.reports
  FOR INSERT WITH CHECK (
    auth.uid() = reported_by AND public.user_is_active()
  );


-- ----- notifications (private to recipient) --------------------------
-- service_role + DB triggers write rows; the recipient reads + marks
-- read. No INSERT policy means user-side inserts are rejected.
DROP POLICY IF EXISTS "notifications_select_self" ON public.notifications;
DROP POLICY IF EXISTS "notifications_update_self" ON public.notifications;
DROP POLICY IF EXISTS "notifications_delete_self" ON public.notifications;

CREATE POLICY "notifications_select_self" ON public.notifications
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "notifications_update_self" ON public.notifications
  FOR UPDATE USING (auth.uid() = user_id)
              WITH CHECK (auth.uid() = user_id);

CREATE POLICY "notifications_delete_self" ON public.notifications
  FOR DELETE USING (auth.uid() = user_id);


-- ----- seller_ratings ------------------------------------------------
-- Public read (so the storefront can show reviews). Rater writes own.
DROP POLICY IF EXISTS "seller_ratings_select_all"   ON public.seller_ratings;
DROP POLICY IF EXISTS "seller_ratings_insert_self"  ON public.seller_ratings;
DROP POLICY IF EXISTS "seller_ratings_update_self"  ON public.seller_ratings;
DROP POLICY IF EXISTS "seller_ratings_delete_self"  ON public.seller_ratings;

CREATE POLICY "seller_ratings_select_all" ON public.seller_ratings
  FOR SELECT USING (auth.role() = 'authenticated');

CREATE POLICY "seller_ratings_insert_self" ON public.seller_ratings
  FOR INSERT WITH CHECK (
    auth.uid() = rated_by AND public.user_is_active()
  );

CREATE POLICY "seller_ratings_update_self" ON public.seller_ratings
  FOR UPDATE USING (auth.uid() = rated_by AND public.user_is_active())
              WITH CHECK (auth.uid() = rated_by AND public.user_is_active());

CREATE POLICY "seller_ratings_delete_self" ON public.seller_ratings
  FOR DELETE USING (auth.uid() = rated_by);


-- ----- urgent_banners (read-only for users; writes via service_role) -
DROP POLICY IF EXISTS "urgent_banners_select_active" ON public.urgent_banners;

CREATE POLICY "urgent_banners_select_active" ON public.urgent_banners
  FOR SELECT USING (
    is_active = TRUE AND (expires_at IS NULL OR expires_at > NOW())
  );


-- =====================================================================
--  SECTION 7 — STORAGE BUCKETS + POLICIES
--
--  Run this from the SQL editor so the buckets and their RLS policies
--  exist before the app tries to upload. ON CONFLICT lets you re-run.
-- =====================================================================

INSERT INTO storage.buckets (id, name, public)
VALUES
  ('profile_photos', 'profile_photos', TRUE),
  ('product_photos', 'product_photos', TRUE),
  ('event_flyers',   'event_flyers',   TRUE),
  ('church_photos',  'church_photos',  TRUE)
ON CONFLICT (id) DO NOTHING;

-- Each upload path is "<user_uid>/<filename>" (see lib/services/storage_service.dart).
-- We enforce that here so users can only write into their own folder.
DROP POLICY IF EXISTS "storage_public_read"      ON storage.objects;
DROP POLICY IF EXISTS "storage_own_folder_write" ON storage.objects;
DROP POLICY IF EXISTS "storage_own_folder_update" ON storage.objects;
DROP POLICY IF EXISTS "storage_own_folder_delete" ON storage.objects;

CREATE POLICY "storage_public_read" ON storage.objects
  FOR SELECT USING (
    bucket_id IN ('profile_photos','product_photos','event_flyers','church_photos')
  );

CREATE POLICY "storage_own_folder_write" ON storage.objects
  FOR INSERT WITH CHECK (
    bucket_id IN ('profile_photos','product_photos','event_flyers','church_photos')
    AND auth.uid()::text = (storage.foldername(name))[1]
  );

CREATE POLICY "storage_own_folder_update" ON storage.objects
  FOR UPDATE USING (
    bucket_id IN ('profile_photos','product_photos','event_flyers','church_photos')
    AND auth.uid()::text = (storage.foldername(name))[1]
  );

CREATE POLICY "storage_own_folder_delete" ON storage.objects
  FOR DELETE USING (
    bucket_id IN ('profile_photos','product_photos','event_flyers','church_photos')
    AND auth.uid()::text = (storage.foldername(name))[1]
  );


-- =====================================================================
--  SECTION 8 — DB-DRIVEN IN-APP NOTIFICATIONS
--
--  Whenever something happens to a user's content, drop a row in
--  public.notifications. The recipient's notification centre + (later)
--  FCM both read from the same table.
--
--  Triggers are SECURITY DEFINER so they bypass RLS on the insert.
-- =====================================================================

-- New RSVP → tell the event organiser.
CREATE OR REPLACE FUNCTION public.notify_event_rsvp()
RETURNS TRIGGER AS $$
DECLARE
  organiser UUID;
  evt_title TEXT;
BEGIN
  IF NEW.status <> 'going' THEN RETURN NEW; END IF;

  SELECT organizer_id, title INTO organiser, evt_title
  FROM public.events WHERE id = NEW.event_id;

  -- Don't notify someone about their own RSVP.
  IF organiser IS NULL OR organiser = NEW.user_id THEN RETURN NEW; END IF;

  INSERT INTO public.notifications (user_id, title, body, type, reference_id, reference_type)
  VALUES (
    organiser,
    'New RSVP',
    'Someone is going to "' || COALESCE(evt_title, 'your event') || '".',
    'event_rsvp',
    NEW.event_id::text,
    'event'
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS trg_notify_event_rsvp ON public.event_rsvps;
CREATE TRIGGER trg_notify_event_rsvp
  AFTER INSERT ON public.event_rsvps
  FOR EACH ROW EXECUTE FUNCTION public.notify_event_rsvp();


-- New prayer response → tell the prayer's author (unless they responded
-- themselves or the prayer is anonymous and the comment is on themself).
CREATE OR REPLACE FUNCTION public.notify_prayer_response()
RETURNS TRIGGER AS $$
DECLARE
  author UUID;
BEGIN
  SELECT author_id INTO author FROM public.prayers WHERE id = NEW.prayer_id;
  IF author IS NULL OR author = NEW.user_id THEN RETURN NEW; END IF;

  INSERT INTO public.notifications (user_id, title, body, type, reference_id, reference_type)
  VALUES (
    author,
    CASE WHEN NEW.response_type = 'praying'
         THEN 'Someone is praying for you'
         ELSE 'New comment on your prayer' END,
    CASE WHEN NEW.response_type = 'message' AND NEW.message IS NOT NULL
         THEN substr(NEW.message, 1, 140)
         ELSE 'A member of the community is praying with you.' END,
    'prayer_response',
    NEW.prayer_id::text,
    'prayer'
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS trg_notify_prayer_response ON public.prayer_responses;
CREATE TRIGGER trg_notify_prayer_response
  AFTER INSERT ON public.prayer_responses
  FOR EACH ROW EXECUTE FUNCTION public.notify_prayer_response();


-- New message → tell the other conversation participant.
CREATE OR REPLACE FUNCTION public.notify_new_message()
RETURNS TRIGGER AS $$
DECLARE
  parts   UUID[];
  other   UUID;
BEGIN
  SELECT participant_ids INTO parts
  FROM public.conversations WHERE id = NEW.conversation_id;
  IF parts IS NULL THEN RETURN NEW; END IF;

  -- Pick the participant who isn't the sender.
  SELECT p INTO other
  FROM unnest(parts) AS p WHERE p <> NEW.sender_id LIMIT 1;
  IF other IS NULL THEN RETURN NEW; END IF;

  INSERT INTO public.notifications (user_id, title, body, type, reference_id, reference_type)
  VALUES (
    other,
    'New message',
    COALESCE(substr(NEW.content, 1, 140), 'You have a new message.'),
    'message',
    NEW.conversation_id::text,
    'conversation'
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS trg_notify_new_message ON public.messages;
CREATE TRIGGER trg_notify_new_message
  AFTER INSERT ON public.messages
  FOR EACH ROW EXECUTE FUNCTION public.notify_new_message();


-- Seller status change → tell the applicant.
CREATE OR REPLACE FUNCTION public.notify_seller_status()
RETURNS TRIGGER AS $$
BEGIN
  IF OLD.status IS NOT DISTINCT FROM NEW.status THEN RETURN NEW; END IF;
  INSERT INTO public.notifications (user_id, title, body, type, reference_id, reference_type)
  VALUES (
    NEW.auth_user_id,
    CASE NEW.status
      WHEN 'approved' THEN 'Your store is approved'
      WHEN 'rejected' THEN 'Store application update'
      ELSE 'Store status updated' END,
    CASE NEW.status
      WHEN 'approved' THEN 'You can now list products on the marketplace.'
      WHEN 'rejected' THEN COALESCE(NEW.rejection_reason, 'See the dashboard for details.')
      ELSE 'Your application status has changed.' END,
    'seller_status',
    NEW.id::text,
    'seller'
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS trg_notify_seller_status ON public.sellers;
CREATE TRIGGER trg_notify_seller_status
  AFTER UPDATE OF status ON public.sellers
  FOR EACH ROW EXECUTE FUNCTION public.notify_seller_status();


-- Church-admin application status → tell the applicant.
CREATE OR REPLACE FUNCTION public.notify_church_admin_status()
RETURNS TRIGGER AS $$
DECLARE
  cname TEXT;
BEGIN
  IF OLD.status IS NOT DISTINCT FROM NEW.status THEN RETURN NEW; END IF;
  SELECT name INTO cname FROM public.churches WHERE id = NEW.church_id;
  INSERT INTO public.notifications (user_id, title, body, type, reference_id, reference_type)
  VALUES (
    NEW.user_id,
    CASE NEW.status
      WHEN 'approved' THEN 'You''re a church admin'
      WHEN 'rejected' THEN 'Church admin update'
      ELSE 'Church admin status updated' END,
    CASE NEW.status
      WHEN 'approved' THEN 'Your role at ' || COALESCE(cname, 'your church') || ' is approved.'
      WHEN 'rejected' THEN COALESCE(NEW.rejection_reason, 'See the admin screen for details.')
      ELSE 'Your application status has changed.' END,
    'church_admin_status',
    NEW.id::text,
    'church_admin'
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS trg_notify_church_admin_status ON public.church_admins;
CREATE TRIGGER trg_notify_church_admin_status
  AFTER UPDATE OF status ON public.church_admins
  FOR EACH ROW EXECUTE FUNCTION public.notify_church_admin_status();


-- =====================================================================
--  END OF PATCH 002
-- =====================================================================
