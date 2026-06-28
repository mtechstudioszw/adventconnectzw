-- patch_145: auto-publish RSS-imported news. The fetch-advent-news edge
-- function inserts with author_id = NULL + source_url set (only the service
-- role can do that — RLS forces author_id = auth.uid() for real users), so
-- treating that combination as an auto-approved feed import is safe.
CREATE OR REPLACE FUNCTION public.advent_news_set_status()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $function$
BEGIN
  IF NEW.author_id IS NULL AND NEW.source_url IS NOT NULL THEN
    NEW.status := 'approved';            -- automated SDA news feed import
  ELSIF (SELECT COALESCE(is_super_admin, FALSE)
           FROM public.profiles WHERE id = NEW.author_id) THEN
    NEW.status := 'approved';
  ELSE
    NEW.status := 'pending';
  END IF;
  RETURN NEW;
END;
$function$;

-- Approve the items already imported as pending in the first run.
UPDATE public.advent_news
   SET status = 'approved'
 WHERE author_id IS NULL AND source_url IS NOT NULL AND status = 'pending';
