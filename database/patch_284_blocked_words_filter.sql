-- ============================================================================
--  patch_284 — filter objectionable words before they are posted
--  STATUS: DRAFT — rehearse, then apply.
-- ============================================================================
--
--  Apple Guideline 1.2 (user-generated content) asks for four things:
--  Terms the user accepts, a way to report, a way to block — the app has
--  all three — and "a method for filtering objectionable material from
--  being posted". This is the fourth.
--
--  How it works
--    * public.blocked_words holds the list (lowercase letters only). It is
--      editable from the Supabase dashboard — add Shona / Ndebele words
--      there; this seed is English only, on purpose: words were only added
--      where the meaning is certain.
--    * content_filter_check() is a BEFORE INSERT OR UPDATE trigger on every
--      public text field. A match raises CONTENT_BLOCKED and the save is
--      refused; the app shows a plain message.
--    * Whole words only ("class" never matches "ass"). On UPDATE only the
--      columns that CHANGED are checked, so moderation, likes, last-active
--      stamps and old rows are never blocked.
--    * Server jobs (no signed-in user — e.g. the news importer) are not
--      filtered: news articles legitimately name things like
--      "pornography" when reporting on campaigns against it.
--
--  Deliberately NOT blocked, because they are Bible words (KJV) or
--  everyday product/farm words: ass, bastard, damn, hell, whore, piss,
--  cock, prick, nude, rape (prayer requests for victims must go through).
--
--  Not covered: chat messages. They are end-to-end encrypted, so the
--  server cannot read them; chat has report, block and the one-message
--  limit for strangers instead.
--
--  Profiles: only on UPDATE. Sign-up creates the profile inside an auth
--  trigger, where a raise would surface as an unhelpful "Database error
--  saving new user"; the sign-up form already validates names.
--
--  Also fixes guard_moderation_columns() (see the end of this file):
--  members could not edit their own posts at all.
--
--  CLAUDE.md checklist: no new profiles columns; the new BEFORE trigger
--  returns COALESCE(NEW, OLD); the guard fix keeps its behaviour and its
--  COALESCE(NEW, OLD) return.
-- ============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.blocked_words (
  word       text PRIMARY KEY CHECK (word ~ '^[a-z]+$'),
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.blocked_words ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.blocked_words FROM anon, authenticated;

INSERT INTO public.blocked_words (word) VALUES
  ('fuck'), ('fucks'), ('fucking'), ('fucked'), ('fucker'), ('fuckers'),
  ('motherfucker'), ('motherfuckers'), ('fck'), ('fuk'), ('fuking'),
  ('shit'), ('shits'), ('shitty'), ('bullshit'),
  ('asshole'), ('assholes'), ('cunt'), ('cunts'), ('dickhead'),
  ('bitch'), ('bitches'), ('slut'), ('sluts'), ('twat'), ('wanker'),
  ('cocksucker'), ('blowjob'), ('handjob'), ('dildo'),
  ('porn'), ('porno'), ('pornhub'), ('xxx'),
  ('nigger'), ('niggers'), ('nigga'), ('niggas'),
  ('faggot'), ('faggots'), ('fag'), ('fags'),
  ('retard'), ('retards'), ('kaffir'), ('kaffirs')
ON CONFLICT (word) DO NOTHING;

-- True when [p] contains a blocked word as a whole word.
CREATE OR REPLACE FUNCTION public.contains_blocked_word(p text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
  SELECT p IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.blocked_words w
     WHERE lower(p) ~ ('(^|[^a-z])' || w.word || '([^a-z]|$)')
  );
$function$;

REVOKE ALL ON FUNCTION public.contains_blocked_word(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.contains_blocked_word(text) TO authenticated;

-- Trigger: TG_ARGV are the text columns to check.
CREATE OR REPLACE FUNCTION public.content_filter_check()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_new jsonb;
  v_old jsonb;
  v_col text;
  v_val text;
BEGIN
  -- Server jobs (news importer, admin SQL) are not filtered.
  IF auth.uid() IS NULL THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  v_new := to_jsonb(NEW);
  v_old := CASE WHEN TG_OP = 'UPDATE' THEN to_jsonb(OLD) ELSE NULL END;

  FOREACH v_col IN ARRAY TG_ARGV LOOP
    v_val := v_new ->> v_col;
    IF v_val IS NULL OR v_val = '' THEN
      CONTINUE;
    END IF;
    -- On UPDATE, only what changed.
    IF v_old IS NOT NULL AND (v_old ->> v_col) IS NOT DISTINCT FROM v_val THEN
      CONTINUE;
    END IF;
    IF public.contains_blocked_word(v_val) THEN
      RAISE EXCEPTION 'CONTENT_BLOCKED'
        USING ERRCODE = 'P0001',
              HINT = 'This contains words that are not allowed.';
    END IF;
  END LOOP;

  RETURN COALESCE(NEW, OLD);
END;
$function$;

DROP TRIGGER IF EXISTS content_filter ON public.posts;
CREATE TRIGGER content_filter BEFORE INSERT OR UPDATE ON public.posts
  FOR EACH ROW EXECUTE FUNCTION public.content_filter_check('body');

DROP TRIGGER IF EXISTS content_filter ON public.post_comments;
CREATE TRIGGER content_filter BEFORE INSERT OR UPDATE ON public.post_comments
  FOR EACH ROW EXECUTE FUNCTION public.content_filter_check('body');

DROP TRIGGER IF EXISTS content_filter ON public.prayers;
CREATE TRIGGER content_filter BEFORE INSERT OR UPDATE ON public.prayers
  FOR EACH ROW EXECUTE FUNCTION public.content_filter_check('title', 'content');

DROP TRIGGER IF EXISTS content_filter ON public.prayer_responses;
CREATE TRIGGER content_filter BEFORE INSERT OR UPDATE ON public.prayer_responses
  FOR EACH ROW EXECUTE FUNCTION public.content_filter_check('message');

DROP TRIGGER IF EXISTS content_filter ON public.stories;
CREATE TRIGGER content_filter BEFORE INSERT OR UPDATE ON public.stories
  FOR EACH ROW EXECUTE FUNCTION public.content_filter_check('caption', 'text_content');

DROP TRIGGER IF EXISTS content_filter ON public.products;
CREATE TRIGGER content_filter BEFORE INSERT OR UPDATE ON public.products
  FOR EACH ROW EXECUTE FUNCTION public.content_filter_check('title', 'description');

DROP TRIGGER IF EXISTS content_filter ON public.sellers;
CREATE TRIGGER content_filter BEFORE INSERT OR UPDATE ON public.sellers
  FOR EACH ROW EXECUTE FUNCTION public.content_filter_check('description');

DROP TRIGGER IF EXISTS content_filter ON public.events;
CREATE TRIGGER content_filter BEFORE INSERT OR UPDATE ON public.events
  FOR EACH ROW EXECUTE FUNCTION public.content_filter_check('title', 'description');

DROP TRIGGER IF EXISTS content_filter ON public.jobs;
CREATE TRIGGER content_filter BEFORE INSERT OR UPDATE ON public.jobs
  FOR EACH ROW EXECUTE FUNCTION public.content_filter_check('title', 'description');

DROP TRIGGER IF EXISTS content_filter ON public.advent_news;
CREATE TRIGGER content_filter BEFORE INSERT OR UPDATE ON public.advent_news
  FOR EACH ROW EXECUTE FUNCTION public.content_filter_check('title', 'summary', 'body');

DROP TRIGGER IF EXISTS content_filter ON public.pages;
CREATE TRIGGER content_filter BEFORE INSERT OR UPDATE ON public.pages
  FOR EACH ROW EXECUTE FUNCTION public.content_filter_check('name', 'description');

DROP TRIGGER IF EXISTS content_filter ON public.profiles;
CREATE TRIGGER content_filter BEFORE UPDATE OF full_name, username, bio ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.content_filter_check('full_name', 'username', 'bio');

-- ---------------------------------------------------------------------------
-- Bug fix found while rehearsing this patch: guard_moderation_columns() is
-- the BEFORE UPDATE trigger on BOTH products and posts, and its products-
-- only check read NEW.status in the same expression as the table-name
-- test. PL/pgSQL resolves every field in an expression, and posts has no
-- `status` column, so EVERY member update of a post — editing it, making
-- it friends-only — failed with 'record "new" has no field "status"'.
-- Same behaviour as before; the status check is just nested so it is only
-- ever evaluated for products.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.guard_moderation_columns()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
  -- SQL editor / service role (no JWT) and super admins are not limited.
  IF auth.uid() IS NULL OR public.is_super_admin() THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  -- Members can never set or clear a moderation decision themselves.
  NEW.moderation_hidden_at := OLD.moderation_hidden_at;
  NEW.moderation_reason    := OLD.moderation_reason;

  -- A listing the moderators hid stays hidden until they restore it.
  IF TG_TABLE_NAME = 'products' THEN
    IF OLD.moderation_hidden_at IS NOT NULL
       AND NEW.status IS DISTINCT FROM OLD.status THEN
      RAISE EXCEPTION 'This listing was hidden by the moderators. Appeal to have it reviewed.'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$function$;

NOTIFY pgrst, 'reload schema';

COMMIT;
