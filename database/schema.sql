-- =====================================================================
--  ADVENT CONNECT ZW — DATABASE SCHEMA
--  Source of truth: ADVENT_CONNECT_ZW_MASTER_REFERENCE_V4.md (Part 11)
--  Region: Africa (Cape Town)  |  Auth: Supabase Auth (email + Google)
--
--  Run order:
--    1. schema.sql      (this file — tables, indexes, RLS, triggers)
--    2. seed_data.sql   (optional sample data for testing)
-- =====================================================================

-- Required extensions ---------------------------------------------------
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";   -- trigram search on church names

-- ---------------------------------------------------------------------
--  Reusable trigger: keep updated_at fresh on UPDATE
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at := NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- =====================================================================
--  TABLE 1 — churches
--  (Created first because profiles.home_church_id references it)
-- =====================================================================
CREATE TABLE IF NOT EXISTS public.churches (
  id                      BIGSERIAL PRIMARY KEY,
  name                    TEXT NOT NULL,
  description             TEXT,
  district                TEXT,
  conference              TEXT,
  conference_code         TEXT,
  province                TEXT,
  city                    TEXT,
  suburb                  TEXT,
  address                 TEXT,
  latitude                DECIMAL(9, 6),
  longitude               DECIMAL(9, 6),
  phone                   TEXT,
  email                   TEXT,
  website                 TEXT,
  pastor_name             TEXT,
  pastor_phone            TEXT,
  members_count           INTEGER DEFAULT 0 CHECK (members_count >= 0),
  founded_year            INTEGER CHECK (founded_year BETWEEN 1800 AND 2100),
  cover_photo_url         TEXT,
  profile_photo_url       TEXT,
  follower_count          INTEGER NOT NULL DEFAULT 0 CHECK (follower_count >= 0),
  verified                BOOLEAN NOT NULL DEFAULT FALSE,
  status                  TEXT NOT NULL DEFAULT 'active'
                            CHECK (status IN ('active','inactive','unconfirmed','merged','relocated')),
  created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_churches_province       ON public.churches (province);
CREATE INDEX IF NOT EXISTS idx_churches_city           ON public.churches (city);
CREATE INDEX IF NOT EXISTS idx_churches_conference     ON public.churches (conference_code);
CREATE INDEX IF NOT EXISTS idx_churches_verified       ON public.churches (verified) WHERE verified = TRUE;
CREATE INDEX IF NOT EXISTS idx_churches_status         ON public.churches (status);
CREATE INDEX IF NOT EXISTS idx_churches_name_trgm      ON public.churches USING gin (name gin_trgm_ops);

CREATE TRIGGER trg_churches_updated_at
  BEFORE UPDATE ON public.churches
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


-- =====================================================================
--  TABLE 2 — profiles  (extends auth.users)
-- =====================================================================
CREATE TABLE IF NOT EXISTS public.profiles (
  id                      UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name               TEXT,
  username                TEXT UNIQUE,
  date_of_birth           DATE,
  bio                     TEXT,
  province                TEXT,
  city                    TEXT,
  church_id               BIGINT REFERENCES public.churches(id) ON DELETE SET NULL,
  profile_photo_url       TEXT,
  cover_photo_url         TEXT,
  account_type            TEXT NOT NULL DEFAULT 'member'
                            CHECK (account_type IN ('member','seller','church_admin','super_admin')),
  language_preference     TEXT NOT NULL DEFAULT 'english'
                            CHECK (language_preference IN ('english','shona','ndebele')),
  is_verified             BOOLEAN NOT NULL DEFAULT FALSE,
  is_banned               BOOLEAN NOT NULL DEFAULT FALSE,
  is_discoverable         BOOLEAN NOT NULL DEFAULT TRUE,
  fcm_token               TEXT,
  last_active_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_profiles_church_id      ON public.profiles (church_id);
CREATE INDEX IF NOT EXISTS idx_profiles_account_type   ON public.profiles (account_type);
CREATE INDEX IF NOT EXISTS idx_profiles_username       ON public.profiles (username);

CREATE TRIGGER trg_profiles_updated_at
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


-- =====================================================================
--  TABLE 3 — events
-- =====================================================================
CREATE TABLE IF NOT EXISTS public.events (
  id                      BIGSERIAL PRIMARY KEY,
  title                   TEXT NOT NULL,
  description             TEXT,
  start_date              DATE NOT NULL,
  end_date                DATE,
  start_time              TEXT,                   -- HH:mm string per V4 spec
  end_time                TEXT,
  province                TEXT,
  city                    TEXT,
  venue                   TEXT,
  address                 TEXT,
  latitude                DECIMAL(9, 6),
  longitude               DECIMAL(9, 6),
  church_id               BIGINT REFERENCES public.churches(id) ON DELETE SET NULL,
  organizer_id            UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  category                TEXT
                            CHECK (category IN (
                              'camp_meeting','youth','concert','graduation',
                              'week_of_prayer','conference','community','other'
                            )),
  capacity                INTEGER CHECK (capacity IS NULL OR capacity > 0),
  rsvp_count              INTEGER NOT NULL DEFAULT 0 CHECK (rsvp_count >= 0),
  cover_photo_url         TEXT,
  contact_name            TEXT,
  contact_phone           TEXT,
  stream_link             TEXT,
  is_online               BOOLEAN NOT NULL DEFAULT FALSE,
  event_source            TEXT NOT NULL DEFAULT 'community'
                            CHECK (event_source IN ('church','community')),
  status                  TEXT NOT NULL DEFAULT 'approved'
                            CHECK (status IN ('pending','approved','rejected','cancelled')),
  created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT events_date_range_chk CHECK (end_date IS NULL OR end_date >= start_date)
);

CREATE INDEX IF NOT EXISTS idx_events_start_date       ON public.events (start_date);
CREATE INDEX IF NOT EXISTS idx_events_church_id        ON public.events (church_id);
CREATE INDEX IF NOT EXISTS idx_events_organizer_id     ON public.events (organizer_id);
CREATE INDEX IF NOT EXISTS idx_events_status           ON public.events (status);
CREATE INDEX IF NOT EXISTS idx_events_province_city    ON public.events (province, city);

CREATE TRIGGER trg_events_updated_at
  BEFORE UPDATE ON public.events
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


-- =====================================================================
--  TABLE 4 — event_rsvps
-- =====================================================================
CREATE TABLE IF NOT EXISTS public.event_rsvps (
  id                      BIGSERIAL PRIMARY KEY,
  event_id                BIGINT NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
  user_id                 UUID   NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  status                  TEXT   NOT NULL DEFAULT 'going'
                            CHECK (status IN ('going','interested','not_going')),
  created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT event_rsvps_unique UNIQUE (event_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_event_rsvps_event_id    ON public.event_rsvps (event_id);
CREATE INDEX IF NOT EXISTS idx_event_rsvps_user_id     ON public.event_rsvps (user_id);


-- =====================================================================
--  TABLE 5 — church_followers
-- =====================================================================
CREATE TABLE IF NOT EXISTS public.church_followers (
  id                      BIGSERIAL PRIMARY KEY,
  church_id               BIGINT NOT NULL REFERENCES public.churches(id) ON DELETE CASCADE,
  user_id                 UUID   NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT church_followers_unique UNIQUE (church_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_church_followers_church ON public.church_followers (church_id);
CREATE INDEX IF NOT EXISTS idx_church_followers_user   ON public.church_followers (user_id);


-- =====================================================================
--  TABLE 6 — prayers   (named per V4: prayer_requests)
-- =====================================================================
CREATE TABLE IF NOT EXISTS public.prayers (
  id                      BIGSERIAL PRIMARY KEY,
  author_id               UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  title                   TEXT,
  content                 TEXT NOT NULL CHECK (char_length(content) BETWEEN 1 AND 2000),
  visibility              TEXT NOT NULL DEFAULT 'public'
                            CHECK (visibility IN ('public','church_only','anonymous')),
  church_id               BIGINT REFERENCES public.churches(id) ON DELETE SET NULL,
  prayer_count            INTEGER NOT NULL DEFAULT 0 CHECK (prayer_count >= 0),
  comment_count           INTEGER NOT NULL DEFAULT 0 CHECK (comment_count >= 0),
  is_urgent               BOOLEAN NOT NULL DEFAULT FALSE,
  is_answered             BOOLEAN NOT NULL DEFAULT FALSE,
  expires_at              TIMESTAMPTZ,
  created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_prayers_author_id       ON public.prayers (author_id);
CREATE INDEX IF NOT EXISTS idx_prayers_church_id       ON public.prayers (church_id);
CREATE INDEX IF NOT EXISTS idx_prayers_created_at      ON public.prayers (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_prayers_visibility      ON public.prayers (visibility);

CREATE TRIGGER trg_prayers_updated_at
  BEFORE UPDATE ON public.prayers
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


-- =====================================================================
--  TABLE 7 — prayer_responses ("I'm Praying" reactions + comments)
-- =====================================================================
CREATE TABLE IF NOT EXISTS public.prayer_responses (
  id                      BIGSERIAL PRIMARY KEY,
  prayer_id               BIGINT NOT NULL REFERENCES public.prayers(id) ON DELETE CASCADE,
  user_id                 UUID   NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  response_type           TEXT   NOT NULL DEFAULT 'praying'
                            CHECK (response_type IN ('praying','message')),
  message                 TEXT CHECK (message IS NULL OR char_length(message) <= 1000),
  created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT prayer_responses_unique_praying UNIQUE (prayer_id, user_id, response_type)
);

CREATE INDEX IF NOT EXISTS idx_prayer_responses_prayer ON public.prayer_responses (prayer_id);
CREATE INDEX IF NOT EXISTS idx_prayer_responses_user   ON public.prayer_responses (user_id);


-- =====================================================================
--  TABLE 8 — products (marketplace)
-- =====================================================================
CREATE TABLE IF NOT EXISTS public.products (
  id                      BIGSERIAL PRIMARY KEY,
  seller_id               UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  title                   TEXT NOT NULL,
  description             TEXT,
  price                   DECIMAL(12, 2) NOT NULL CHECK (price > 0),
  price_currency          TEXT NOT NULL DEFAULT 'USD'
                            CHECK (price_currency IN ('USD','ZWL','ZAR')),
  category                TEXT NOT NULL,
  subcategory             TEXT,
  image_urls              TEXT[] NOT NULL DEFAULT '{}',
  condition               TEXT
                            CHECK (condition IN ('new','like_new','good','fair','for_parts')),
  province                TEXT,
  location                TEXT,
  status                  TEXT NOT NULL DEFAULT 'available'
                            CHECK (status IN ('available','sold','reserved','removed')),
  view_count              INTEGER NOT NULL DEFAULT 0 CHECK (view_count >= 0),
  is_featured             BOOLEAN NOT NULL DEFAULT FALSE,
  created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_products_seller_id      ON public.products (seller_id);
CREATE INDEX IF NOT EXISTS idx_products_category       ON public.products (category);
CREATE INDEX IF NOT EXISTS idx_products_status         ON public.products (status);
CREATE INDEX IF NOT EXISTS idx_products_created_at     ON public.products (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_products_featured       ON public.products (is_featured) WHERE is_featured = TRUE;

CREATE TRIGGER trg_products_updated_at
  BEFORE UPDATE ON public.products
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


-- =====================================================================
--  TABLE 9 — jobs   (named per V4: job_posts)
-- =====================================================================
CREATE TABLE IF NOT EXISTS public.jobs (
  id                      BIGSERIAL PRIMARY KEY,
  poster_id               UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  title                   TEXT NOT NULL,
  company                 TEXT,
  description             TEXT NOT NULL,
  requirements            TEXT,
  category                TEXT NOT NULL
                            CHECK (category IN (
                              'teaching_education','healthcare','construction_trades',
                              'farming_agriculture','driving_transport','domestic_caregiving',
                              'business_admin','it_technology','ministry_church','other'
                            )),
  job_type                TEXT NOT NULL DEFAULT 'full_time'
                            CHECK (job_type IN ('full_time','part_time','contract','internship','volunteer')),
  post_type               TEXT NOT NULL DEFAULT 'hiring'
                            CHECK (post_type IN ('hiring','seeking')),
  salary_range            TEXT,
  province                TEXT NOT NULL,
  location                TEXT NOT NULL,
  sabbath_friendly        BOOLEAN NOT NULL DEFAULT FALSE,
  is_sda_institution      BOOLEAN NOT NULL DEFAULT FALSE,
  contact_phone           TEXT,
  contact_email           TEXT,
  status                  TEXT NOT NULL DEFAULT 'open'
                            CHECK (status IN ('open','closed','filled','expired')),
  expires_at              TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '30 days'),
  created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_jobs_poster_id          ON public.jobs (poster_id);
CREATE INDEX IF NOT EXISTS idx_jobs_category           ON public.jobs (category);
CREATE INDEX IF NOT EXISTS idx_jobs_status             ON public.jobs (status);
CREATE INDEX IF NOT EXISTS idx_jobs_province           ON public.jobs (province);
CREATE INDEX IF NOT EXISTS idx_jobs_created_at         ON public.jobs (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_jobs_expires_at         ON public.jobs (expires_at);

CREATE TRIGGER trg_jobs_updated_at
  BEFORE UPDATE ON public.jobs
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


-- =====================================================================
--  TABLE 10 — conversations (1:1 direct messaging)
-- =====================================================================
CREATE TABLE IF NOT EXISTS public.conversations (
  id                      BIGSERIAL PRIMARY KEY,
  participant_ids         UUID[] NOT NULL,
  last_message            TEXT,
  last_message_at         TIMESTAMPTZ,
  last_message_by         UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  conversation_source     TEXT NOT NULL DEFAULT 'direct'
                            CHECK (conversation_source IN ('direct','marketplace','job','prayer_support')),
  related_product_id      BIGINT REFERENCES public.products(id) ON DELETE SET NULL,
  related_job_id          BIGINT REFERENCES public.jobs(id) ON DELETE SET NULL,
  created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT conversations_participants_chk
    CHECK (array_length(participant_ids, 1) BETWEEN 2 AND 2)
);

CREATE INDEX IF NOT EXISTS idx_conversations_participants
  ON public.conversations USING gin (participant_ids);
CREATE INDEX IF NOT EXISTS idx_conversations_last_message_at
  ON public.conversations (last_message_at DESC NULLS LAST);

CREATE TRIGGER trg_conversations_updated_at
  BEFORE UPDATE ON public.conversations
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


-- =====================================================================
--  TABLE 11 — messages
-- =====================================================================
CREATE TABLE IF NOT EXISTS public.messages (
  id                      BIGSERIAL PRIMARY KEY,
  conversation_id         BIGINT NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
  sender_id               UUID   NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  content                 TEXT CHECK (content IS NULL OR char_length(content) <= 2000),
  message_type            TEXT NOT NULL DEFAULT 'text'
                            CHECK (message_type IN ('text','image','voice','system')),
  media_url               TEXT,
  media_duration_seconds  INTEGER CHECK (media_duration_seconds IS NULL OR media_duration_seconds >= 0),
  read                    BOOLEAN NOT NULL DEFAULT FALSE,
  read_at                 TIMESTAMPTZ,
  is_deleted              BOOLEAN NOT NULL DEFAULT FALSE,
  created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_messages_conversation_id
  ON public.messages (conversation_id, created_at);
CREATE INDEX IF NOT EXISTS idx_messages_sender_id      ON public.messages (sender_id);
CREATE INDEX IF NOT EXISTS idx_messages_unread
  ON public.messages (conversation_id) WHERE read = FALSE;


-- =====================================================================
--  COUNTER TRIGGERS — keep denormalised counts in sync
-- =====================================================================

-- church.follower_count
CREATE OR REPLACE FUNCTION public.bump_church_follower_count()
RETURNS TRIGGER AS $$
BEGIN
  IF (TG_OP = 'INSERT') THEN
    UPDATE public.churches SET follower_count = follower_count + 1 WHERE id = NEW.church_id;
  ELSIF (TG_OP = 'DELETE') THEN
    UPDATE public.churches SET follower_count = GREATEST(follower_count - 1, 0) WHERE id = OLD.church_id;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_church_followers_count
  AFTER INSERT OR DELETE ON public.church_followers
  FOR EACH ROW EXECUTE FUNCTION public.bump_church_follower_count();

-- events.rsvp_count
CREATE OR REPLACE FUNCTION public.bump_event_rsvp_count()
RETURNS TRIGGER AS $$
BEGIN
  IF (TG_OP = 'INSERT' AND NEW.status = 'going') THEN
    UPDATE public.events SET rsvp_count = rsvp_count + 1 WHERE id = NEW.event_id;
  ELSIF (TG_OP = 'DELETE' AND OLD.status = 'going') THEN
    UPDATE public.events SET rsvp_count = GREATEST(rsvp_count - 1, 0) WHERE id = OLD.event_id;
  ELSIF (TG_OP = 'UPDATE' AND OLD.status <> NEW.status) THEN
    IF NEW.status = 'going' THEN
      UPDATE public.events SET rsvp_count = rsvp_count + 1 WHERE id = NEW.event_id;
    ELSIF OLD.status = 'going' THEN
      UPDATE public.events SET rsvp_count = GREATEST(rsvp_count - 1, 0) WHERE id = NEW.event_id;
    END IF;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_event_rsvps_count
  AFTER INSERT OR UPDATE OR DELETE ON public.event_rsvps
  FOR EACH ROW EXECUTE FUNCTION public.bump_event_rsvp_count();

-- prayers.prayer_count (only counts response_type = 'praying')
CREATE OR REPLACE FUNCTION public.bump_prayer_count()
RETURNS TRIGGER AS $$
BEGIN
  IF (TG_OP = 'INSERT' AND NEW.response_type = 'praying') THEN
    UPDATE public.prayers SET prayer_count = prayer_count + 1 WHERE id = NEW.prayer_id;
  ELSIF (TG_OP = 'INSERT' AND NEW.response_type = 'message') THEN
    UPDATE public.prayers SET comment_count = comment_count + 1 WHERE id = NEW.prayer_id;
  ELSIF (TG_OP = 'DELETE' AND OLD.response_type = 'praying') THEN
    UPDATE public.prayers SET prayer_count = GREATEST(prayer_count - 1, 0) WHERE id = OLD.prayer_id;
  ELSIF (TG_OP = 'DELETE' AND OLD.response_type = 'message') THEN
    UPDATE public.prayers SET comment_count = GREATEST(comment_count - 1, 0) WHERE id = OLD.prayer_id;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_prayer_responses_count
  AFTER INSERT OR DELETE ON public.prayer_responses
  FOR EACH ROW EXECUTE FUNCTION public.bump_prayer_count();

-- conversations.last_message / last_message_at when a message is sent
CREATE OR REPLACE FUNCTION public.update_conversation_on_message()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE public.conversations
     SET last_message    = NEW.content,
         last_message_at = NEW.created_at,
         last_message_by = NEW.sender_id,
         updated_at      = NOW()
   WHERE id = NEW.conversation_id;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_messages_update_conversation
  AFTER INSERT ON public.messages
  FOR EACH ROW EXECUTE FUNCTION public.update_conversation_on_message();


-- =====================================================================
--  ROW LEVEL SECURITY
--  All tables RLS-enabled. Each policy is intentionally narrow.
-- =====================================================================

ALTER TABLE public.churches          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.events            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.event_rsvps       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.church_followers  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.prayers           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.prayer_responses  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.jobs              ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages          ENABLE ROW LEVEL SECURITY;


-- ---- churches: public read, no app writes (admin via service role) ----
CREATE POLICY "churches_select_all" ON public.churches
  FOR SELECT USING (TRUE);

-- INSERT/UPDATE/DELETE intentionally have no policy → service role only.

-- ---- profiles: authenticated read, owner write -----------------------
CREATE POLICY "profiles_select_authenticated" ON public.profiles
  FOR SELECT USING (auth.role() = 'authenticated');

CREATE POLICY "profiles_insert_self" ON public.profiles
  FOR INSERT WITH CHECK (auth.uid() = id);

CREATE POLICY "profiles_update_self" ON public.profiles
  FOR UPDATE USING (auth.uid() = id) WITH CHECK (auth.uid() = id);

CREATE POLICY "profiles_delete_self" ON public.profiles
  FOR DELETE USING (auth.uid() = id);

-- ---- events: public read, owner write --------------------------------
CREATE POLICY "events_select_all" ON public.events
  FOR SELECT USING (status = 'approved' OR organizer_id = auth.uid());

CREATE POLICY "events_insert_authenticated" ON public.events
  FOR INSERT WITH CHECK (auth.uid() = organizer_id);

CREATE POLICY "events_update_owner" ON public.events
  FOR UPDATE USING (auth.uid() = organizer_id) WITH CHECK (auth.uid() = organizer_id);

CREATE POLICY "events_delete_owner" ON public.events
  FOR DELETE USING (auth.uid() = organizer_id);

-- ---- event_rsvps: authenticated read, self-write ---------------------
CREATE POLICY "event_rsvps_select_authenticated" ON public.event_rsvps
  FOR SELECT USING (auth.role() = 'authenticated');

CREATE POLICY "event_rsvps_insert_self" ON public.event_rsvps
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "event_rsvps_update_self" ON public.event_rsvps
  FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

CREATE POLICY "event_rsvps_delete_self" ON public.event_rsvps
  FOR DELETE USING (auth.uid() = user_id);

-- ---- church_followers: authenticated read, self-write ----------------
CREATE POLICY "church_followers_select_authenticated" ON public.church_followers
  FOR SELECT USING (auth.role() = 'authenticated');

CREATE POLICY "church_followers_insert_self" ON public.church_followers
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "church_followers_delete_self" ON public.church_followers
  FOR DELETE USING (auth.uid() = user_id);

-- ---- prayers: visibility-aware read, owner write ---------------------
-- Public prayers: any authenticated user can read.
-- church_only: only readers who follow the prayer's church.
-- anonymous:   readable; identity hidden in app layer.
CREATE POLICY "prayers_select_visible" ON public.prayers
  FOR SELECT USING (
    auth.role() = 'authenticated' AND (
      visibility IN ('public', 'anonymous')
      OR author_id = auth.uid()
      OR (
        visibility = 'church_only'
        AND church_id IS NOT NULL
        AND EXISTS (
          SELECT 1 FROM public.church_followers cf
          WHERE cf.church_id = prayers.church_id AND cf.user_id = auth.uid()
        )
      )
    )
  );

CREATE POLICY "prayers_insert_self" ON public.prayers
  FOR INSERT WITH CHECK (auth.uid() = author_id);

CREATE POLICY "prayers_update_self" ON public.prayers
  FOR UPDATE USING (auth.uid() = author_id) WITH CHECK (auth.uid() = author_id);

CREATE POLICY "prayers_delete_self" ON public.prayers
  FOR DELETE USING (auth.uid() = author_id);

-- ---- prayer_responses: read if you can read the prayer, self-write --
CREATE POLICY "prayer_responses_select_authenticated" ON public.prayer_responses
  FOR SELECT USING (auth.role() = 'authenticated');

CREATE POLICY "prayer_responses_insert_self" ON public.prayer_responses
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "prayer_responses_delete_self" ON public.prayer_responses
  FOR DELETE USING (auth.uid() = user_id);

-- ---- products: public read of available, seller writes ---------------
CREATE POLICY "products_select_visible" ON public.products
  FOR SELECT USING (status <> 'removed' OR seller_id = auth.uid());

CREATE POLICY "products_insert_self" ON public.products
  FOR INSERT WITH CHECK (auth.uid() = seller_id);

CREATE POLICY "products_update_self" ON public.products
  FOR UPDATE USING (auth.uid() = seller_id) WITH CHECK (auth.uid() = seller_id);

CREATE POLICY "products_delete_self" ON public.products
  FOR DELETE USING (auth.uid() = seller_id);

-- ---- jobs: public read of open, poster writes -----------------------
CREATE POLICY "jobs_select_visible" ON public.jobs
  FOR SELECT USING (
    status IN ('open','filled','closed') OR poster_id = auth.uid()
  );

CREATE POLICY "jobs_insert_self" ON public.jobs
  FOR INSERT WITH CHECK (auth.uid() = poster_id);

CREATE POLICY "jobs_update_self" ON public.jobs
  FOR UPDATE USING (auth.uid() = poster_id) WITH CHECK (auth.uid() = poster_id);

CREATE POLICY "jobs_delete_self" ON public.jobs
  FOR DELETE USING (auth.uid() = poster_id);

-- ---- conversations: only participants ---------------------------------
CREATE POLICY "conversations_select_participant" ON public.conversations
  FOR SELECT USING (auth.uid() = ANY (participant_ids));

CREATE POLICY "conversations_insert_participant" ON public.conversations
  FOR INSERT WITH CHECK (auth.uid() = ANY (participant_ids));

CREATE POLICY "conversations_update_participant" ON public.conversations
  FOR UPDATE USING (auth.uid() = ANY (participant_ids))
              WITH CHECK (auth.uid() = ANY (participant_ids));

-- ---- messages: only conversation participants ------------------------
CREATE POLICY "messages_select_participant" ON public.messages
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.conversations c
      WHERE c.id = messages.conversation_id
        AND auth.uid() = ANY (c.participant_ids)
    )
  );

CREATE POLICY "messages_insert_sender" ON public.messages
  FOR INSERT WITH CHECK (
    auth.uid() = sender_id
    AND EXISTS (
      SELECT 1 FROM public.conversations c
      WHERE c.id = messages.conversation_id
        AND auth.uid() = ANY (c.participant_ids)
    )
  );

CREATE POLICY "messages_update_sender" ON public.messages
  FOR UPDATE USING (auth.uid() = sender_id) WITH CHECK (auth.uid() = sender_id);

CREATE POLICY "messages_delete_sender" ON public.messages
  FOR DELETE USING (auth.uid() = sender_id);


-- =====================================================================
--  REALTIME — enable only for messaging surfaces
--  (Run these in Supabase Studio → Database → Replication or via SQL)
-- =====================================================================
-- ALTER PUBLICATION supabase_realtime ADD TABLE public.messages;
-- ALTER PUBLICATION supabase_realtime ADD TABLE public.conversations;
