-- =============================================================================
-- 20260522000000_event_end_columns.sql
-- =============================================================================
-- Adds optional end_date + end_time columns to events so multi-day
-- events (camp meetings, weeks of prayer) and events with explicit
-- end times (concerts, programs) can be modelled. Both columns are
-- nullable — single-day, open-ended events keep working unchanged.
--
-- Safe to run more than once.
-- =============================================================================

alter table public.events
  add column if not exists end_date date,
  add column if not exists end_time time;

-- Optional integrity guard — keep end_date >= start_date when both
-- are set. Wrapped in a do-block so re-runs don't crash on the
-- duplicate-constraint error.
do $$
begin
  if not exists (
    select 1
    from information_schema.table_constraints
    where table_schema = 'public'
      and table_name = 'events'
      and constraint_name = 'events_end_after_start'
  ) then
    alter table public.events
      add constraint events_end_after_start
      check (end_date is null or end_date >= start_date);
  end if;
end$$;
