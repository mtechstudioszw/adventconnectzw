-- =====================================================================
--  PATCH 168 — Ministry involvement & spiritual gifts
--
--  A church directory's most useful question is not "who is this" but
--  "who can help with this". Nothing in the app could answer it: a
--  profile carried a name, a photo and a bio, none of which tell you the
--  person three rows down leads the choir or teaches Sabbath School.
--
--  Two tag kinds share one table because they behave identically —
--  a controlled vocabulary the user picks from, rendered as chips:
--    ministry — a role you serve in    (Choir, Pathfinders, Deacon)
--    gift     — a way you serve        (Teaching, Hospitality, Mercy)
--
--  Controlled vocabulary, not free text, on purpose: free-text tags
--  fragment instantly ("Pathfinders" / "pathfinder" / "PF Club") and
--  become useless for the directory search this is meant to feed.
-- =====================================================================

CREATE TABLE IF NOT EXISTS public.ministry_tags (
  id         SERIAL PRIMARY KEY,
  code       TEXT NOT NULL UNIQUE,
  label      TEXT NOT NULL,
  kind       TEXT NOT NULL CHECK (kind IN ('ministry','gift')),
  sort_order INTEGER NOT NULL DEFAULT 100
);

COMMENT ON TABLE public.ministry_tags IS
  'Controlled vocabulary of ministry roles and spiritual gifts. Reference '
  'data — seeded here, never written by the client.';

CREATE TABLE IF NOT EXISTS public.profile_ministry_tags (
  profile_id UUID    NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  tag_id     INTEGER NOT NULL REFERENCES public.ministry_tags(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (profile_id, tag_id)
);

CREATE INDEX IF NOT EXISTS idx_profile_ministry_tags_profile
  ON public.profile_ministry_tags (profile_id);
-- Reverse lookup: "who in this church can teach?" — the directory
-- feature this table exists to make possible.
CREATE INDEX IF NOT EXISTS idx_profile_ministry_tags_tag
  ON public.profile_ministry_tags (tag_id);

-- ── RLS ──────────────────────────────────────────────────────────────
ALTER TABLE public.ministry_tags         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profile_ministry_tags ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS ministry_tags_select ON public.ministry_tags;
CREATE POLICY ministry_tags_select ON public.ministry_tags
  FOR SELECT TO authenticated USING (true);

-- Someone's tags are readable exactly when their profile is: their own
-- always, others only when discoverable. This mirrors how the profile
-- screen already gates bio/posts, so tags can't become a side channel
-- that leaks details of a private profile.
DROP POLICY IF EXISTS profile_ministry_tags_select ON public.profile_ministry_tags;
CREATE POLICY profile_ministry_tags_select ON public.profile_ministry_tags
  FOR SELECT TO authenticated
  USING (
    profile_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.profiles p
       WHERE p.id = profile_ministry_tags.profile_id
         AND p.is_discoverable = TRUE
    )
  );

DROP POLICY IF EXISTS profile_ministry_tags_insert ON public.profile_ministry_tags;
CREATE POLICY profile_ministry_tags_insert ON public.profile_ministry_tags
  FOR INSERT TO authenticated
  WITH CHECK (profile_id = auth.uid());

DROP POLICY IF EXISTS profile_ministry_tags_delete ON public.profile_ministry_tags;
CREATE POLICY profile_ministry_tags_delete ON public.profile_ministry_tags
  FOR DELETE TO authenticated
  USING (profile_id = auth.uid());

-- ── Seed ─────────────────────────────────────────────────────────────
-- Ministries follow how an SDA congregation in Zimbabwe is actually
-- organised, not a generic "volunteering" list.
INSERT INTO public.ministry_tags (code, label, kind, sort_order) VALUES
  ('choir',             'Choir',                 'ministry', 10),
  ('pathfinders',       'Pathfinders',           'ministry', 20),
  ('adventurers',       'Adventurers',           'ministry', 30),
  ('ay',                'AY',                    'ministry', 40),
  ('sabbath_school',    'Sabbath School',        'ministry', 50),
  ('elder',             'Elder',                 'ministry', 60),
  ('deacon',            'Deacon',                'ministry', 70),
  ('deaconess',         'Deaconess',             'ministry', 80),
  ('personal_ministries','Personal Ministries',  'ministry', 90),
  ('community_services','Community Services',    'ministry', 100),
  ('health',            'Health Ministries',     'ministry', 110),
  ('womens',            'Women''s Ministries',   'ministry', 120),
  ('mens',              'Men''s Ministries',     'ministry', 130),
  ('children',          'Children''s Ministries','ministry', 140),
  ('music',             'Music',                 'ministry', 150),
  ('media',             'Media & Sound',         'ministry', 160),
  ('stewardship',       'Stewardship',           'ministry', 170),
  ('bible_worker',      'Bible Worker',          'ministry', 180),
  ('teaching',          'Teaching',              'gift',     200),
  ('preaching',         'Preaching',             'gift',     210),
  ('evangelism',        'Evangelism',            'gift',     220),
  ('hospitality',       'Hospitality',           'gift',     230),
  ('encouragement',     'Encouragement',         'gift',     240),
  ('administration',    'Administration',        'gift',     250),
  ('leadership',        'Leadership',            'gift',     260),
  ('mercy',             'Mercy',                 'gift',     270),
  ('giving',            'Giving',                'gift',     280),
  ('intercession',      'Intercession',          'gift',     290),
  ('service',           'Service',               'gift',     300),
  ('faith',             'Faith',                 'gift',     310)
ON CONFLICT (code) DO UPDATE
  SET label = EXCLUDED.label,
      kind = EXCLUDED.kind,
      sort_order = EXCLUDED.sort_order;
