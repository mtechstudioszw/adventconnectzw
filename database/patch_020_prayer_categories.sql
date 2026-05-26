-- =====================================================================
--  PATCH 020 — Prayer categories
--
--  WHY: The prayer screen lists every request chronologically with no
--       way to filter, so as the corpus grows it gets crowded fast.
--       Adding a coarse category (healing / family / spiritual /
--       provision / thanksgiving / ministry / other) lets users
--       narrow by intent without an ML topic model.
--
--  WHAT:
--   1. Adds `category TEXT` to prayers, defaulting to 'other' so
--      existing rows remain queryable.
--   2. Constrains it to a fixed set of values so the chip row maps
--      cleanly. Easy to extend later by altering the CHECK.
--   3. Index on category for the filtered-list query.
--
--  PREREQUISITES: schema.sql.
--  IDEMPOTENT:    yes — IF NOT EXISTS guards + DROP IF EXISTS for
--                 the check constraint before recreating.
-- =====================================================================

ALTER TABLE public.prayers
  ADD COLUMN IF NOT EXISTS category TEXT NOT NULL DEFAULT 'other';

ALTER TABLE public.prayers
  DROP CONSTRAINT IF EXISTS prayers_category_chk;

ALTER TABLE public.prayers
  ADD CONSTRAINT prayers_category_chk
  CHECK (category IN (
    'healing',
    'family',
    'spiritual',
    'provision',
    'thanksgiving',
    'ministry',
    'other'
  ));

CREATE INDEX IF NOT EXISTS idx_prayers_category
  ON public.prayers (category);
