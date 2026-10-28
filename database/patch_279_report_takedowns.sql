-- ============================================================================
--  patch_279 — reports you can act on: see what was reported, take it down,
--  ban the person behind it
--  STATUS: APPLIED to the live database 28 Oct 2026.
-- ============================================================================
--
--  Owner, 28 Oct 2026: "is there an option to report jobs … products …
--  stores? … it will get to my admin dashboard. Then I will ban if it's
--  necessary."
--
--  Before this patch:
--    * The app already had Report on jobs, products and stores, and the
--      reports reached the dashboard's Reports queue — but the queue showed
--      only "product" and an id, not WHICH listing or WHO posted it.
--    * "Ban" existed only for reports against a person. For a reported job,
--      product or store the only button was "Resolve" (a note) — nothing
--      actually came down.
--    * A banned member can't post anything new (user_is_active()), but what
--      they had already posted stayed live.
--    * The same member could file the same report again and again.
--
--  This patch:
--    1. reports.reported_user_id is filled by the SERVER for jobs, products,
--       stores, Pages and people (the column existed for messages only), so
--       a report can't point at the wrong person; old reports backfilled.
--    2. One open report per member per item (a repeat is a no-op).
--    3. admin_list_reports also returns what was reported (title, a short
--       preview, its current state), who is behind it (name, banned?) and
--       how many open reports that item has.
--    4. admin_takedown_report(report, reason, ban):
--         job → status 'rejected' (gone from the board), poster notified;
--         product → admin_set_product_status('removed') from patch_272
--                   (seller notified, can appeal);
--         store → status 'rejected_final', closed, its listings removed,
--                 owner notified;
--         Page → hidden via admin_set_page_state (patch_275);
--         post → admin_set_post_hidden (patch_272);
--       then, if ban = true, bans the person (admin_set_banned: refuses to
--       ban yourself or another super admin, notifies them) AND takes down
--       everything else they have live — open jobs, listings, their store.
--       Every open report on that item is closed as actioned.
--
--  Super admins only (is_super_admin), like every other report function.
--  CLAUDE.md: not `profiles` columns; BEFORE trigger returns COALESCE.
-- ============================================================================

BEGIN;

-- 1. Who is behind the reported item -----------------------------------------
CREATE OR REPLACE FUNCTION public.report_owner(p_type text, p_id text)
RETURNS uuid LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v uuid;
  v_num boolean := p_id ~ '^\d+$';
  v_uuid boolean := p_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';
BEGIN
  CASE p_type
    WHEN 'job' THEN
      IF v_num THEN SELECT poster_id INTO v FROM jobs WHERE id = p_id::bigint; END IF;
    WHEN 'product' THEN
      IF v_num THEN SELECT seller_id INTO v FROM products WHERE id = p_id::bigint; END IF;
    WHEN 'seller' THEN
      -- The storefront reports the owner's account id; older builds the row id.
      IF v_uuid THEN v := p_id::uuid;
      ELSIF v_num THEN SELECT auth_user_id INTO v FROM sellers WHERE id = p_id::bigint;
      END IF;
    WHEN 'page' THEN
      IF v_uuid THEN
        SELECT pa.user_id INTO v FROM page_admins pa
         WHERE pa.page_id = p_id::uuid AND pa.role = 'owner' LIMIT 1;
      END IF;
    WHEN 'post' THEN
      IF v_uuid THEN SELECT author_id INTO v FROM posts WHERE id = p_id::uuid; END IF;
    WHEN 'user', 'profile' THEN
      IF v_uuid THEN v := p_id::uuid; END IF;
    ELSE
      v := NULL;
  END CASE;
  RETURN v;
EXCEPTION WHEN undefined_table OR undefined_column THEN
  RETURN NULL;
END;
$function$;
REVOKE ALL ON FUNCTION public.report_owner(text, text) FROM public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.reports_fill_owner()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
BEGIN
  -- Messages are stamped by report_message() (patch_165); keep that.
  IF NEW.content_type <> 'message' THEN
    NEW.reported_user_id := public.report_owner(NEW.content_type, NEW.content_id);
  END IF;
  RETURN COALESCE(NEW, OLD);
END;
$function$;

DROP TRIGGER IF EXISTS reports_fill_owner_trg ON public.reports;
CREATE TRIGGER reports_fill_owner_trg BEFORE INSERT ON public.reports
  FOR EACH ROW EXECUTE FUNCTION public.reports_fill_owner();

UPDATE public.reports
   SET reported_user_id = public.report_owner(content_type, content_id)
 WHERE reported_user_id IS NULL AND content_type <> 'message';

-- 2. One open report per member per item ----------------------------------------
CREATE UNIQUE INDEX IF NOT EXISTS reports_one_open_per_member
  ON public.reports (reported_by, content_type, content_id)
  WHERE status IN ('pending', 'reviewing');

-- 3. The queue, with what and who ---------------------------------------------
DROP FUNCTION IF EXISTS public.admin_list_reports(text, integer);
CREATE FUNCTION public.admin_list_reports(
  p_status text DEFAULT 'pending', p_limit integer DEFAULT 100)
RETURNS TABLE(
  id bigint, reported_by uuid, reporter_name text,
  content_type text, content_id text, reason text, details text,
  status text, action_taken text, created_at timestamptz,
  content_title text, content_preview text, content_state text,
  reported_user_id uuid, reported_user_name text, reported_user_banned boolean,
  open_reports_on_content integer)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_status text := CASE WHEN p_status = 'open' THEN 'pending' ELSE p_status END;
BEGIN
  PERFORM public.assert_super_admin();
  RETURN QUERY
    WITH r AS (
      SELECT r.*,
             r.content_id ~ '^\d+$' AS is_num,
             r.content_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' AS is_uuid
        FROM public.reports r
       WHERE (v_status = 'all' OR COALESCE(r.status, 'pending') = v_status)
       ORDER BY r.created_at DESC
       LIMIT GREATEST(p_limit, 1)
    )
    SELECT r.id, r.reported_by,
           COALESCE(NULLIF(btrim(rp.full_name), ''), 'Member'),
           r.content_type, r.content_id, r.reason, r.details,
           COALESCE(r.status, 'pending'), r.action_taken, r.created_at,
           COALESCE(j.title, pr.title, s.business_name, pg.name, op.full_name,
                    left(po.body, 80), left(r.reported_text, 80)),
           left(COALESCE(j.description, pr.description, s.description,
                         pg.description, po.body, r.reported_text), 200),
           COALESCE(j.status, pr.status, s.status, pg.status,
                    CASE WHEN op.is_banned THEN 'banned' END),
           r.reported_user_id,
           NULLIF(btrim(owner.full_name), ''),
           COALESCE(owner.is_banned, false),
           (SELECT count(*)::int FROM public.reports x
             WHERE x.content_type = r.content_type
               AND x.content_id = r.content_id
               AND x.status IN ('pending', 'reviewing'))
      FROM r
      LEFT JOIN public.profiles rp ON rp.id = r.reported_by
      LEFT JOIN public.profiles owner ON owner.id = r.reported_user_id
      LEFT JOIN public.jobs j
             ON r.content_type = 'job' AND r.is_num AND j.id = r.content_id::bigint
      LEFT JOIN public.products pr
             ON r.content_type = 'product' AND r.is_num AND pr.id = r.content_id::bigint
      LEFT JOIN public.sellers s
             ON r.content_type = 'seller'
            AND ((r.is_uuid AND s.auth_user_id = r.content_id::uuid)
              OR (r.is_num AND s.id = r.content_id::bigint))
      LEFT JOIN public.pages pg
             ON r.content_type = 'page' AND r.is_uuid AND pg.id = r.content_id::uuid
      LEFT JOIN public.posts po
             ON r.content_type = 'post' AND r.is_uuid AND po.id = r.content_id::uuid
      LEFT JOIN public.profiles op
             ON r.content_type IN ('user', 'profile') AND r.is_uuid
            AND op.id = r.content_id::uuid
     ORDER BY r.created_at DESC;
END;
$function$;
REVOKE ALL ON FUNCTION public.admin_list_reports(text, integer) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_reports(text, integer) TO authenticated;

-- 4. Take it down (and optionally ban) ---------------------------------------
-- Removes one item. Internal: callers check is_super_admin().
CREATE OR REPLACE FUNCTION public.moderation_remove_item(
  p_type text, p_id text, p_reason text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_owner uuid;
  v_title text;
  v_seller public.sellers;
BEGIN
  CASE p_type
    WHEN 'job' THEN
      UPDATE jobs SET status = 'rejected'
       WHERE id = p_id::bigint AND status <> 'rejected'
      RETURNING poster_id, title INTO v_owner, v_title;
      IF v_owner IS NOT NULL THEN
        INSERT INTO notifications (user_id, title, body, type, reference_id, reference_type)
        VALUES (v_owner, 'Job removed',
                '"' || v_title || '" was removed by the moderators: ' || p_reason
                  || ' Contact support if you believe this is a mistake.',
                'moderation', p_id, 'job');
      END IF;
    WHEN 'product' THEN
      PERFORM public.admin_set_product_status(p_id::bigint, 'removed', p_reason);
    WHEN 'seller' THEN
      IF p_id ~ '^\d+$' THEN
        SELECT * INTO v_seller FROM sellers WHERE id = p_id::bigint;
      ELSE
        SELECT * INTO v_seller FROM sellers WHERE auth_user_id = p_id::uuid;
      END IF;
      IF v_seller.id IS NOT NULL THEN
        UPDATE sellers
           SET status = 'rejected_final', is_active = false,
               rejection_reason = p_reason
         WHERE id = v_seller.id;
        -- A closed store's listings come down with it.
        UPDATE products
           SET status = 'removed', moderation_hidden_at = now(),
               moderation_reason = p_reason
         WHERE seller_id = v_seller.auth_user_id AND status <> 'removed';
        INSERT INTO notifications (user_id, title, body, type, reference_id, reference_type)
        VALUES (v_seller.auth_user_id, 'Store closed',
                v_seller.business_name || ' was closed by the moderators: ' || p_reason
                  || ' Contact support if you believe this is a mistake.',
                'moderation', v_seller.id::text, 'seller');
      END IF;
    WHEN 'page' THEN
      PERFORM public.admin_set_page_state(
        p_id::uuid,
        COALESCE((SELECT is_verified FROM pages WHERE id = p_id::uuid), false),
        true, p_reason);
    WHEN 'post' THEN
      PERFORM public.admin_set_post_hidden(p_id::uuid, true, p_reason);
    ELSE
      -- People are handled by the ban; other types have no takedown yet.
      NULL;
  END CASE;
END;
$function$;
REVOKE ALL ON FUNCTION public.moderation_remove_item(text, text, text)
  FROM public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.admin_takedown_report(
  p_report_id bigint, p_reason text, p_ban boolean DEFAULT false)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  r public.reports;
  v_reason text := COALESCE(NULLIF(btrim(p_reason), ''),
                            'It broke the community guidelines.');
  v_owner uuid;
  v_action text;
  v_id text;
BEGIN
  PERFORM public.assert_super_admin();
  SELECT * INTO r FROM reports WHERE id = p_report_id;
  IF r.id IS NULL THEN
    RAISE EXCEPTION 'Report % not found.', p_report_id USING ERRCODE = 'P0002';
  END IF;

  v_owner := COALESCE(r.reported_user_id,
                      public.report_owner(r.content_type, r.content_id));

  PERFORM public.moderation_remove_item(r.content_type, r.content_id, v_reason);
  v_action := CASE WHEN r.content_type IN ('user', 'profile', 'message')
                   THEN 'Reviewed' ELSE 'Removed' END;

  IF p_ban THEN
    IF v_owner IS NULL THEN
      RAISE EXCEPTION 'No account found behind this report to ban.'
        USING ERRCODE = 'P0002';
    END IF;
    -- Refuses yourself / another super admin; notifies the member.
    PERFORM public.admin_set_banned(v_owner, true);

    -- What they already posted comes down too.
    FOR v_id IN SELECT j.id::text FROM jobs j
                 WHERE j.poster_id = v_owner AND j.status IN ('open', 'pending', 'filled')
    LOOP
      PERFORM public.moderation_remove_item('job', v_id, v_reason);
    END LOOP;
    FOR v_id IN SELECT s.id::text FROM sellers s
                 WHERE s.auth_user_id = v_owner AND s.status <> 'rejected_final'
    LOOP
      PERFORM public.moderation_remove_item('seller', v_id, v_reason);
    END LOOP;
    UPDATE products
       SET status = 'removed', moderation_hidden_at = now(),
           moderation_reason = v_reason
     WHERE seller_id = v_owner AND status <> 'removed';

    v_action := v_action || ' + banned the account and removed their listings';
  END IF;

  v_action := v_action || ': ' || v_reason;

  UPDATE reports
     SET status = 'actioned', action_taken = v_action,
         reviewed_by = auth.uid(), reviewed_at = now()
   WHERE content_type = r.content_type AND content_id = r.content_id
     AND status IN ('pending', 'reviewing');

  RETURN v_action;
END;
$function$;
REVOKE ALL ON FUNCTION public.admin_takedown_report(bigint, text, boolean) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_takedown_report(bigint, text, boolean) TO authenticated;

COMMIT;

-- Checks (as a super admin, from the dashboard):
--   * Report a product from the app → the queue shows its title, the
--     seller's name and "1 open report".
--   * Report it again from the same account → still 1.
--   * "Remove" → the listing disappears for buyers; the seller gets
--     "A listing was hidden" with the appeal option; the report is actioned.
--   * "Remove & ban" on a reported job → the job is gone, the poster is
--     banned and notified, and their other jobs / store / listings are gone.
--   * Try "Remove & ban" on a report about your own listing → refused.
