-- =====================================================================
--  PATCH 114 — birthdays fire reliably on the day.
--
--  notify_birthdays() was scheduled once a day at 04:00 Harare. If a user
--  set their DOB later in the day (or the 04:00 run was missed) they got no
--  birthday notification at all that day. notify_birthdays() already
--  de-dupes (skips if a 'birthday' notification was sent in the last 20h),
--  so running it every 2 hours is safe and catches same-day DOB edits.
-- =====================================================================

SELECT cron.unschedule('birthday-notifications')
  WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'birthday-notifications');

SELECT cron.schedule(
  'birthday-notifications',
  '0 */2 * * *',                       -- every 2 hours
  'SELECT public.notify_birthdays();'
);

-- Send today's birthdays right now (de-dup guard prevents repeats).
SELECT public.notify_birthdays();
