-- =====================================================================
--  PATCH 188 — Close the is_verified_admin self-grant
--
--  FINDING (HIGH, confirmed against production 3 Aug 2026)
--
--  Any authenticated user could award themselves the gold verified tick:
--
--      PATCH /rest/v1/profiles?id=eq.<their own id>
--      {"is_verified_admin": true}
--
--  Proven in a rolled-back transaction on production: with the JWT claim
--  set to an ordinary member, is_super_admin was snapped back, premium_until
--  was refused outright by the column grant — and is_verified_admin stuck.
--
--  Three things had to line up, and they did:
--
--   1. `profiles_update_self` allows a member to UPDATE their own row.
--   2. `authenticated` and `anon` hold a column-level UPDATE grant on
--      is_verified_admin. The premium migration rebuilt profiles' UPDATE
--      grants per-column and excluded ONLY premium_until, so every other
--      column — including this one — was granted back.
--   3. `profiles_block_privilege_self_grant()` snaps back is_super_admin,
--      is_verified, is_banned, is_business and premium_until. It was
--      written in patch_028; is_verified_admin arrived later in patch_134
--      and was never added to it.
--
--  And `trg_profiles_super_admin_verify` is `BEFORE UPDATE OF
--  is_super_admin`, so it does not fire when the member touches only
--  is_verified_admin.
--
--  WHY IT MATTERS. This is not database privilege escalation — it grants
--  no extra read access. It is TRUST escalation, which in this app is
--  worse. is_verified_admin drives the gold tick on posts, comments,
--  stories, chat messages, the inbox, the member directory and the
--  profile screen. It is the single signal a member uses to decide
--  whether an account speaks for a church. A scammer wearing it in the
--  marketplace, or DMing members for money, is a materially different
--  threat from one without it.
--
--  is_verified_admin is a DERIVED column. It is recomputed by
--  `recompute_verified_admin(uid)` from `is_super_admin` OR an approved
--  `church_admins` row. Nothing should ever write it directly.
--
--  THE FIX — two locks, matching how premium_until is protected:
--
--   1. Revoke the column grant. This is the hard lock.
--   2. Snap it back in the privilege trigger. This is the one that
--      survives someone re-running an old GRANT.
--
--  Plus a transaction-local escape hatch so the LEGITIMATE writer still
--  works — the same `current_setting` pattern already used for
--  is_business. Without it the trigger would also block legitimate
--  DOWNGRADES, leaving a removed church admin still wearing the tick,
--  which is the same bug pointing the other way.
-- =====================================================================

-- ---------------------------------------------------------------------
--  1. HARD LOCK — rebuild the per-column UPDATE grant.
--
--  Rebuilt wholesale rather than a bare REVOKE so the excluded set lives
--  in ONE place. Anyone adding a protected column later adds it to this
--  list; a bare REVOKE would be silently undone by the next re-run of
--  the premium migration, which grants every column except premium_until.
--
--  NOTE the trap this codebase has already paid for: a column-level
--  REVOKE is SILENTLY IGNORED while a table-level grant exists. So the
--  table-level UPDATE must be revoked first, every time.
-- ---------------------------------------------------------------------
DO $$
DECLARE cols TEXT;
BEGIN
  SELECT string_agg(quote_ident(attname), ', ')
    INTO cols
    FROM pg_attribute
   WHERE attrelid = 'public.profiles'::regclass
     AND attnum > 0
     AND NOT attisdropped
     AND attname NOT IN ('premium_until', 'is_verified_admin');

  EXECUTE 'REVOKE UPDATE ON public.profiles FROM authenticated, anon';
  EXECUTE format(
    'GRANT UPDATE (%s) ON public.profiles TO authenticated, anon', cols);
END $$;

-- Readable by clients — the tick has to render. Just not writable.
GRANT SELECT (is_verified_admin) ON public.profiles TO authenticated, anon;

-- ---------------------------------------------------------------------
--  2. SECOND LOCK — add is_verified_admin to the privilege trigger.
--
--  Reproduced in full because CREATE OR REPLACE takes the whole body.
--  Everything here except the is_verified_admin block is unchanged from
--  what is live in production today.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.profiles_block_privilege_self_grant()
RETURNS TRIGGER AS $$
DECLARE
  caller_is_super BOOLEAN;
BEGIN
  -- No JWT = the service role (edge functions) or a DB-internal caller.
  -- That is the only path allowed to grant premium.
  IF auth.uid() IS NULL THEN
    RETURN NEW;
  END IF;

  -- Premium is BOUGHT, never self-assigned, so it covers super admins
  -- too — this is the one privilege they may not hand themselves.
  NEW.premium_until := OLD.premium_until;

  SELECT COALESCE(p.is_super_admin, FALSE)
    INTO caller_is_super
    FROM public.profiles p
    WHERE p.id = auth.uid();

  IF caller_is_super THEN
    RETURN NEW;
  END IF;

  NEW.is_super_admin := OLD.is_super_admin;
  NEW.is_verified    := OLD.is_verified;
  NEW.is_banned      := OLD.is_banned;

  -- `is_business` can move TRUE during the auto-approve RPC; otherwise
  -- snap it back to whatever it was before.
  IF current_setting('app.auto_approving_business', true)
       IS DISTINCT FROM 'true' THEN
    NEW.is_business := OLD.is_business;
  END IF;

  -- NEW (patch 188): the gold tick is DERIVED, never self-assigned.
  -- recompute_verified_admin() raises this flag for the duration of its
  -- own transaction; every other caller gets snapped back. The flag is
  -- transaction-local (set_config's third argument), so it cannot leak
  -- into another statement or another session.
  IF current_setting('app.recomputing_verified_admin', true)
       IS DISTINCT FROM 'true' THEN
    NEW.is_verified_admin := OLD.is_verified_admin;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth;

-- ---------------------------------------------------------------------
--  3. Let the legitimate writer through.
--
--  Was LANGUAGE sql; it becomes plpgsql so it can raise the flag before
--  its UPDATE. Same signature, same behaviour, same SECURITY DEFINER.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.recompute_verified_admin(p_uid UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM set_config('app.recomputing_verified_admin', 'true', true);

  UPDATE public.profiles p
     SET is_verified_admin = (
       COALESCE(p.is_super_admin, false)
       OR EXISTS (
         SELECT 1 FROM public.church_admins ca
          WHERE ca.user_id = p_uid AND ca.status = 'approved'
       )
     )
   WHERE p.id = p_uid;

  -- Lower it immediately. Transaction-local would expire on commit
  -- anyway, but leaving it raised would let any LATER statement in the
  -- same transaction write the column freely.
  PERFORM set_config('app.recomputing_verified_admin', 'false', true);
END;
$$;

-- ---------------------------------------------------------------------
--  4. Repair anyone who already exploited it, deliberately or not.
--
--  Recomputes the column from its real source for every row where it
--  currently disagrees. Runs as the definer with no JWT, so the trigger
--  short-circuits on auth.uid() IS NULL.
-- ---------------------------------------------------------------------
UPDATE public.profiles p
   SET is_verified_admin = (
     COALESCE(p.is_super_admin, false)
     OR EXISTS (
       SELECT 1 FROM public.church_admins ca
        WHERE ca.user_id = p.id AND ca.status = 'approved'
     )
   )
 WHERE p.is_verified_admin IS DISTINCT FROM (
     COALESCE(p.is_super_admin, false)
     OR EXISTS (
       SELECT 1 FROM public.church_admins ca
        WHERE ca.user_id = p.id AND ca.status = 'approved'
     )
   );
