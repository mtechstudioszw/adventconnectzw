-- =====================================================================
--  PATCH 300 — end-to-end encrypted stories
--  STATUS: APPLIED 1 Nov 2026 (by Claude via the Supabase connector)
--
--  Stories are already friends-only (policy stories_select_active), so
--  each one has a known audience at posting time. The app now:
--    * seals a story photo with its own AES-256-GCM key (the bucket gets
--      ciphertext), and puts the key, the text and the caption in a small
--      envelope;
--    * encrypts that envelope once for each friend's current phone with
--      the 1:1 Signal session chat already uses, and stores those wraps in
--      story_keys. The stories row itself then carries no readable text.
--
--  A friend on an old build (no keys) sees "Update the app to see this
--  story". A story stays readable to its own author on the phone that
--  posted it. Unencrypted stories (encryption off) are unchanged.
--
--  CLAUDE.md checklist: no profiles change; no triggers. story_keys has
--  RLS on and no policies/grants — reached only through the functions.
-- =====================================================================

BEGIN;

ALTER TABLE public.stories
  ADD COLUMN IF NOT EXISTS e2ee_version smallint;

CREATE TABLE IF NOT EXISTS public.story_keys (
  story_id         uuid    NOT NULL REFERENCES public.stories(id) ON DELETE CASCADE,
  recipient_user   uuid    NOT NULL,
  recipient_device integer NOT NULL,
  sender_device    integer NOT NULL,
  ciphertext       text    NOT NULL,
  ciphertext_type  integer NOT NULL,
  created_at       timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (story_id, recipient_user, recipient_device)
);
ALTER TABLE public.story_keys ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.story_keys FROM PUBLIC, anon, authenticated;

-- The author hands out wraps for their own story, to accepted friends only.
CREATE OR REPLACE FUNCTION public.story_add_keys(p_story uuid, p_rows jsonb)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_count integer := 0;
  r jsonb;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.stories s
                  WHERE s.id = p_story AND s.author_id = auth.uid()) THEN
    RAISE EXCEPTION 'Not your story.' USING ERRCODE = '42501';
  END IF;
  IF jsonb_typeof(p_rows) <> 'array' OR jsonb_array_length(p_rows) > 2000 THEN
    RAISE EXCEPTION 'Bad key list.' USING ERRCODE = '22023';
  END IF;
  FOR r IN SELECT * FROM jsonb_array_elements(p_rows) LOOP
    -- Only friends (and the author's own other phones) may get a key.
    IF (r->>'u')::uuid <> auth.uid() AND NOT EXISTS (
         SELECT 1 FROM public.friendships f
          WHERE f.status = 'accepted'
            AND ((f.requester_id = auth.uid() AND f.addressee_id = (r->>'u')::uuid)
              OR (f.addressee_id = auth.uid() AND f.requester_id = (r->>'u')::uuid))) THEN
      CONTINUE;
    END IF;
    IF length(r->>'c') > 20000 THEN CONTINUE; END IF;
    INSERT INTO public.story_keys (story_id, recipient_user, recipient_device,
      sender_device, ciphertext, ciphertext_type)
    VALUES (p_story, (r->>'u')::uuid, (r->>'d')::int, (r->>'s')::int,
            r->>'c', (r->>'t')::int)
    ON CONFLICT (story_id, recipient_user, recipient_device) DO UPDATE
      SET ciphertext = EXCLUDED.ciphertext,
          ciphertext_type = EXCLUDED.ciphertext_type,
          sender_device = EXCLUDED.sender_device;
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END;
$function$;
GRANT EXECUTE ON FUNCTION public.story_add_keys(uuid, jsonb) TO authenticated;

-- A viewer picks up the wraps for stories they can see, for one phone.
CREATE OR REPLACE FUNCTION public.story_keys_for(p_stories uuid[], p_device integer)
RETURNS TABLE(story_id uuid, sender_device integer, ciphertext text, ciphertext_type integer)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT k.story_id, k.sender_device, k.ciphertext, k.ciphertext_type
    FROM public.story_keys k
    JOIN public.stories s ON s.id = k.story_id
   WHERE k.recipient_user = auth.uid()
     AND k.recipient_device = p_device
     AND s.expires_at > now()
     AND k.story_id = ANY (p_stories[1:300]);
$function$;
GRANT EXECUTE ON FUNCTION public.story_keys_for(uuid[], integer) TO authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;
