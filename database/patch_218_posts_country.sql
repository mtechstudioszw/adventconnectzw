-- =====================================================================
--  PATCH 218 — country on posts, so the feed can be country-first
--
--  patch_213 put `country` on every table that carries a LISTING, but the
--  feed was left out and it is the screen members actually live on. The
--  founder's decision stands: country-first with a Worldwide toggle.
--
--  --------------------------------------------------------------------
--  WHY A TRIGGER AND NOT A CLIENT FIELD
--
--  Products and jobs take country from the form, because the seller is
--  telling us where the thing IS — that is genuinely their answer to give.
--  A post has no such question: its country is simply where its author is.
--  Asking the client to send it would mean every insert path has to
--  remember, and the one that forgets re-creates exactly the silent-'ZW'
--  bug this whole effort exists to kill. So the database fills it in.
--
--  The trigger only fills a NULL. It does not overwrite a value the client
--  sent, which keeps the door open for a future "post as if from home"
--  without another migration.
--
--  SNAPSHOT, NOT A LIVE LINK. The country is copied at insert and then
--  left alone. A member who moves to the UK does not retro-move three
--  years of posts out of their home country's feed — the post was made
--  where it was made, and their old church still expects to see it.
--  --------------------------------------------------------------------
--
--  CLAUDE.md checklist — this touches `posts`, not `profiles`:
--   1. profiles_block_privilege_self_grant() — untouched, not a privilege.
--   2. Grants — not needed. `posts` keeps ordinary table-level grants and
--      RLS; the per-column grant trap is specific to `profiles`, which
--      revoked its table-level SELECT in patch_132.
--   3. No REVOKEs here.
--   4. BEFORE ... DELETE must RETURN COALESCE(NEW, OLD) — this trigger is
--      BEFORE INSERT only, so NEW is never NULL. Do NOT widen it to
--      UPDATE or DELETE without revisiting that rule.
--
--  IDEMPOTENT: yes. ADD COLUMN IF NOT EXISTS, CREATE OR REPLACE FUNCTION,
--  DROP TRIGGER IF EXISTS before CREATE.
-- =====================================================================

ALTER TABLE public.posts
  ADD COLUMN IF NOT EXISTS country TEXT;

-- Backfill from the author. Every existing row is a Zimbabwean member's
-- post, so this lands 'ZW' — but read it from the profile rather than
-- hard-coding, so re-running after any profile correction stays right.
UPDATE public.posts p
   SET country = pr.country
  FROM public.profiles pr
 WHERE pr.id = p.author_id
   AND p.country IS NULL;

CREATE INDEX IF NOT EXISTS idx_posts_country ON public.posts (country);

-- The feed's real access path is "this country, newest first".
CREATE INDEX IF NOT EXISTS idx_posts_country_created
  ON public.posts (country, created_at DESC);

CREATE OR REPLACE FUNCTION public.posts_stamp_country()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.country IS NULL THEN
    SELECT pr.country INTO NEW.country
      FROM public.profiles pr
     WHERE pr.id = NEW.author_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS trg_posts_stamp_country ON public.posts;
CREATE TRIGGER trg_posts_stamp_country
  BEFORE INSERT ON public.posts
  FOR EACH ROW EXECUTE FUNCTION public.posts_stamp_country();

-- ---------------------------------------------------------------------
--  Verification — run these and read the output.
-- ---------------------------------------------------------------------
-- SELECT country, count(*) FROM public.posts GROUP BY 1 ORDER BY 1;
--   -- expect: every row carries a country, none NULL
--
-- SELECT tgname FROM pg_trigger
--  WHERE tgrelid='public.posts'::regclass AND NOT tgisinternal;
--   -- expect: trg_posts_stamp_country
