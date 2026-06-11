-- =====================================================================
--  PATCH 103 — church-only prayers actually scope to the church
--
--  The composer sets visibility='church_only' but never sent church_id,
--  so the row had church_id = NULL and the visibility rule fell through.
--  Now a trigger stamps the author's home church on church-only prayers,
--  and the SELECT rule shows them to people in that church (home church
--  OR followers).
-- =====================================================================

-- Stamp the author's home church on church-only prayers.
CREATE OR REPLACE FUNCTION public.set_prayer_church()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.visibility = 'church_only' AND NEW.church_id IS NULL THEN
    SELECT church_id INTO NEW.church_id
      FROM public.profiles WHERE id = NEW.author_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_set_prayer_church ON public.prayers;
CREATE TRIGGER trg_set_prayer_church
  BEFORE INSERT ON public.prayers
  FOR EACH ROW EXECUTE FUNCTION public.set_prayer_church();

-- Visibility: public/anonymous to all; church-only to the author + people
-- whose HOME church matches OR who follow that church; never to others.
DROP POLICY IF EXISTS prayers_select_visible ON public.prayers;
CREATE POLICY prayers_select_visible ON public.prayers
  FOR SELECT USING (
    (auth.role() = 'authenticated') AND (
      visibility = ANY (ARRAY['public', 'anonymous'])
      OR author_id = auth.uid()
      OR (visibility = 'church_only' AND church_id IS NOT NULL AND (
            EXISTS (SELECT 1 FROM public.church_followers cf
                     WHERE cf.church_id = prayers.church_id
                       AND cf.user_id = auth.uid())
            OR EXISTS (SELECT 1 FROM public.profiles p
                        WHERE p.id = auth.uid()
                          AND p.church_id = prayers.church_id)
         ))
    )
  );
