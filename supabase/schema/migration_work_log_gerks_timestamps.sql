-- ============================================================
-- WorkTracker — Per-field start/stop timestamps on work_log_gerks
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================

-- Replaces manual duration entry with a live Start/Stop toggle per
-- field. duration (minutes) is now computed client-side from these
-- two timestamps when Stop is pressed, kept for backward-compat with
-- existing stats rendering.
alter table public.work_log_gerks
    add column if not exists start_time timestamptz,
    add column if not exists end_time   timestamptz;

-- Start/Stop and the completed checkbox now UPDATE existing rows in
-- place (rather than the old delete+reinsert pattern), so an UPDATE
-- policy is needed — none existed before now (only view/insert/delete).
drop policy if exists "Operators can update own gerks" on public.work_log_gerks;

create policy "Operators can update own gerks"
    on public.work_log_gerks for update
    using (work_log_id in (select id from public.work_logs where operator_id = auth.uid()))
    with check (work_log_id in (select id from public.work_logs where operator_id = auth.uid()));
