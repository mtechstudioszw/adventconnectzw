-- =====================================================================
--  PATCH 191 — Abuse ceilings on member writes
--
--  patch_026 built `check_and_consume_rate_limit` and then only ever used
--  it for password resets and OTP. Everything a member can CREATE — posts,
--  comments, friend requests, reports, stories, messages — had no ceiling
--  at all. One script could fill the feed for all 171 members, or fire a
--  friend request at every account on the network, and nothing would stop
--  it or even notice.
--
--  ## These are ABUSE ceilings, not a product tier
--
--  Deliberately set high enough that no real member will ever meet one.
--  They exist to stop a script, not to shape behaviour, and they are NOT
--  to be repurposed as something Premium lifts. Selling the removal of a
--  spam limit turns anti-abuse into a product feature and gives the app a
--  reason to want the limit to bite — which is exactly backwards. At 171
--  members the problem is too little content, not too much.
--
--  ## Why triggers and not client calls
--
--  A client-side check protects nobody: an attacker with the anon key
--  (it ships in the APK) just doesn't call it. The ceiling has to live
--  where the row is written.
--
--  ## Identity is auth.uid(), not a column
--
--  Every guarded table names its author differently. Using the caller's
--  JWT subject sidesteps that entirely and is the thing we actually want
--  to limit. It also means `auth.uid() IS NULL` — service role, pg_cron,
--  edge functions — passes straight through, so nothing the server does
--  on a member's behalf can be throttled by their own ceiling.
--
--  ## Not covered here, on purpose
--
--  Messaging a stranger is already gated: one message, then it waits on
--  the friend request. That is a better control than a counter and it is
--  already live, so this patch does not stack a second rule on top of it.
--
--  TRAP, freshly paid for in patch_189: these are BEFORE INSERT triggers
--  ONLY. A BEFORE trigger on DELETE that returns NEW returns NULL, which
--  silently cancels the delete. Do not extend these to DELETE without
--  returning COALESCE(NEW, OLD).
-- =====================================================================

CREATE OR REPLACE FUNCTION public.enforce_write_rate_limit()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_action TEXT := TG_ARGV[0];
  v_max    INTEGER := TG_ARGV[1]::INTEGER;
  v_window INTEGER := TG_ARGV[2]::INTEGER;
BEGIN
  -- No JWT means the server is acting, not a member. Never throttle
  -- ourselves: cron reminders, edge functions and admin tooling all land
  -- here and none of them are the threat model.
  IF auth.uid() IS NULL THEN
    RETURN NEW;
  END IF;

  IF NOT public.check_and_consume_rate_limit(
       auth.uid()::text, v_action, v_max, v_window) THEN
    -- 42501 so supabase-dart surfaces a PostgrestException the client can
    -- recognise, matching how maintenance mode already reports itself.
    -- The message is a stable token; the HINT is what a human reads.
    RAISE EXCEPTION 'RATE_LIMITED_%', v_action
      USING ERRCODE = '42501',
            HINT = 'You have done that a lot in a short time. '
                || 'Please wait a little while and try again.';
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.enforce_write_rate_limit() FROM PUBLIC;

-- ---------------------------------------------------------------------
--  The ceilings. Window is seconds; 86400 = one day.
--
--  Sized against real behaviour, then roughly doubled. The busiest real
--  member on this network is nowhere near any of these.
-- ---------------------------------------------------------------------

-- Posting 30 times in a day is already unusual for a person.
DROP TRIGGER IF EXISTS trg_rate_limit_posts ON public.posts;
CREATE TRIGGER trg_rate_limit_posts
  BEFORE INSERT ON public.posts
  FOR EACH ROW EXECUTE FUNCTION
    public.enforce_write_rate_limit('post_create', '30', '86400');

-- Comments are cheap and conversational, so the ceiling is generous.
DROP TRIGGER IF EXISTS trg_rate_limit_comments ON public.post_comments;
CREATE TRIGGER trg_rate_limit_comments
  BEFORE INSERT ON public.post_comments
  FOR EACH ROW EXECUTE FUNCTION
    public.enforce_write_rate_limit('comment_create', '100', '86400');

-- The one that matters most. Blasting friend requests at every account is
-- the classic way to farm a social graph, and 40/day is far past what any
-- genuine member does.
DROP TRIGGER IF EXISTS trg_rate_limit_friend_requests ON public.friendships;
CREATE TRIGGER trg_rate_limit_friend_requests
  BEFORE INSERT ON public.friendships
  FOR EACH ROW EXECUTE FUNCTION
    public.enforce_write_rate_limit('friend_request', '40', '86400');

-- Reports are a moderation queue. Mass-reporting is itself harassment,
-- and it drowns the real reports.
DROP TRIGGER IF EXISTS trg_rate_limit_reports ON public.reports;
CREATE TRIGGER trg_rate_limit_reports
  BEFORE INSERT ON public.reports
  FOR EACH ROW EXECUTE FUNCTION
    public.enforce_write_rate_limit('report_create', '20', '86400');

DROP TRIGGER IF EXISTS trg_rate_limit_stories ON public.stories;
CREATE TRIGGER trg_rate_limit_stories
  BEFORE INSERT ON public.stories
  FOR EACH ROW EXECUTE FUNCTION
    public.enforce_write_rate_limit('story_create', '30', '86400');

-- Messages get an HOURLY window, not a daily one. A real conversation can
-- run to hundreds of messages in a day and must never trip; what we care
-- about is a burst, so 300 in an hour catches a script while leaving the
-- most talkative member on the network untouched.
DROP TRIGGER IF EXISTS trg_rate_limit_messages ON public.messages;
CREATE TRIGGER trg_rate_limit_messages
  BEFORE INSERT ON public.messages
  FOR EACH ROW EXECUTE FUNCTION
    public.enforce_write_rate_limit('message_send', '300', '3600');

-- ---------------------------------------------------------------------
--  Keep the ledger small.
--
--  check_and_consume_rate_limit prunes opportunistically, but only for the
--  action_key it was called with. Fold a full sweep into the nightly log
--  prune from patch_190 so a quiet action key cannot leave rows behind
--  forever.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.prune_operational_logs()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, net, cron
AS $$
DECLARE
  v_resp_bytes BIGINT;
BEGIN
  DELETE FROM net._http_response WHERE created < now() - interval '1 day';

  SELECT pg_total_relation_size('net._http_response') INTO v_resp_bytes;
  IF v_resp_bytes > 20 * 1024 * 1024 THEN
    EXECUTE 'VACUUM FULL net._http_response';
  END IF;

  DELETE FROM cron.job_run_details WHERE end_time < now() - interval '2 days';

  -- New in patch_191: nothing here is needed once its window has passed.
  DELETE FROM public.rate_limits WHERE hit_at < now() - interval '2 days';
END;
$$;

REVOKE ALL ON FUNCTION public.prune_operational_logs() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.prune_operational_logs() FROM authenticated, anon;
