-- ============================================================
-- WorkTracker — work_log_gerks.duration now stores SECONDS, not minutes
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================

-- The per-field editable duration now displays/edits as hh:mm:ss, so it
-- needs second-level precision. Column stays an integer, just reinterpreted.
-- Recompute existing rows from their actual start/end timestamps (only 3
-- test rows exist today, with 0/0/1-minute values from testing yesterday).
update public.work_log_gerks
set duration = extract(epoch from (end_time - start_time))::int
where start_time is not null and end_time is not null;

-- work_logs.work_duration stays in MINUTES (existing stats/rendering
-- depend on that), so re-derive it from the now-in-seconds child rows.
update public.work_logs wl
set work_duration = coalesce((
    select round(sum(g.duration) / 60.0)
    from public.work_log_gerks g
    where g.work_log_id = wl.id
), 0)
where exists (
    select 1 from public.work_log_gerks g
    where g.work_log_id = wl.id and g.duration is not null
);
