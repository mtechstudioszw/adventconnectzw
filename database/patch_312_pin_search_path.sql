-- patch_312 — Pin search_path on the six functions the security advisor
-- still flags after patch 310 (4 Nov 2026). Same fix as patch 310 §6:
-- a function without a fixed search_path can be tricked into calling a
-- look-alike object a caller created. Behaviour is otherwise unchanged.
DO $$
DECLARE f record;
BEGIN
  FOR f IN
    SELECT p.oid::regprocedure AS sig
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.prokind = 'f'
       AND p.proname IN ('premium_tier_rank', 'message_public_preview',
         'premium_tier_for_base_plan', 'boost_credit_allowance',
         'page_name_key', 'page_name_is_protected')
       AND NOT EXISTS (SELECT 1 FROM unnest(coalesce(p.proconfig, '{}')) c
                        WHERE c LIKE 'search_path=%')
  LOOP
    EXECUTE format('ALTER FUNCTION %s SET search_path = public', f.sig);
  END LOOP;
END $$;
