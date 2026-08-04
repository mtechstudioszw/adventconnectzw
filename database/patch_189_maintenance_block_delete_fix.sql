-- =====================================================================
--  PATCH 189 — maintenance_block was silently cancelling EVERY DELETE
--
--  FINDING (CRITICAL, proven against production 3 Aug 2026)
--
--  `block_during_maintenance()` ends with `RETURN NEW`. It is attached as
--  BEFORE INSERT OR UPDATE OR DELETE on 26 tables (patch_187).
--
--  In a BEFORE ... FOR EACH ROW trigger on a DELETE, `NEW` is NULL.
--  Returning NULL from a BEFORE row trigger tells PostgreSQL to SKIP the
--  operation for that row — and it does so SILENTLY. No error, no
--  warning, and the client's `delete()` returns success having deleted
--  nothing.
--
--  So since patch_187 shipped, with maintenance mode OFF, every DELETE on
--  every guarded table has been a no-op. Measured on production inside a
--  rolled-back transaction, maintenance_active() = false:
--
--      post_likes   259 -> 259
--      friendships  101 -> 101
--
--  What that breaks, from the member's side:
--
--    * unliking a post                      (post_likes)
--    * unfriending / cancelling a request   (friendships)
--    * deleting your own post or comment    (posts, post_comments)
--    * deleting a message                   (messages)
--    * leaving a group                      (conversation_members)
--    * cancelling an RSVP                   (event_rsvps)
--    * deleting a story                     (stories)
--    * removing a product or job listing    (products, jobs)
--    * removing a church admin              (church_admins)
--
--  Most of those fail INVISIBLY: the UI updates optimistically, the row
--  survives, and the old state returns on the next refresh. That is the
--  worst failure shape available — it reads as "the app is flaky" rather
--  than pointing at a cause.
--
--  It is also more than a functional bug. A member who deletes a post or
--  a message is making a privacy decision, and the app has been telling
--  them it succeeded while keeping the row. Anything that promises
--  deletion has to actually delete.
--
--  THE FIX — one line, one function, all 26 triggers.
--
--      RETURN COALESCE(NEW, OLD);
--
--  On INSERT/UPDATE, NEW is the row: unchanged behaviour. On DELETE, NEW
--  is NULL and OLD is the row being removed, so returning OLD lets the
--  delete proceed — which is what a pass-through guard must do.
--
--  Maintenance mode itself is unaffected: when maintenance_active() is
--  true the function still raises before it reaches the RETURN, so DELETE
--  is blocked during maintenance exactly as intended.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.block_during_maintenance()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF public.maintenance_active() THEN
    -- 42501 (insufficient_privilege) so supabase-dart surfaces it as a
    -- PostgrestException the client can recognise rather than a crash.
    RAISE EXCEPTION 'MAINTENANCE_MODE'
      USING ERRCODE = '42501',
            HINT = 'Advent Connect is down for maintenance.';
  END IF;

  -- COALESCE, not NEW. On DELETE, NEW is NULL, and returning NULL from a
  -- BEFORE row trigger silently skips the row. See the header — this one
  -- line is the whole of patch 189.
  RETURN COALESCE(NEW, OLD);
END;
$function$;
