-- ============================================================
-- WorkTracker — admins (and supervisors) can't see other people's
-- logged times once a work order is no longer Plan/V delu
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================
--
-- work_logs already has "Admins can view all logs" (any status,
-- any operator) and "Supervisors can view org logs" (org-scoped).
-- But the two child tables that hold the actual logged time detail —
-- work_log_gerks (per-field start/end/duration, what the app renders
-- as each GERK row's Start/Konec times and the "who else worked this"
-- list) and work_log_road_time — never got the same bypass. Their
-- only non-"own rows" grant is "any authenticated user, but only
-- while the work order's status is Plan or V delu" (work_log_gerks
-- only — work_log_road_time doesn't even have that much).
--
-- So the moment a work order moves to Izvedeno/Račun, an admin who
-- didn't personally log the time sees nothing for it — not an error,
-- RLS just silently returns zero rows. This is what was reported:
-- "I know time has been logged... but I don't see it."
--
-- Fix: add the same admin/supervisor bypass work_logs already has,
-- directly on both child tables — mirrors the pattern, doesn't touch
-- the existing open-work-order grant for regular operators.

create policy "Admins can view all work log gerks" on public.work_log_gerks
for select
using (
  exists (select 1 from public.profiles where profiles.id = auth.uid() and profiles.role = 'admin')
);

create policy "Supervisors can view org work log gerks" on public.work_log_gerks
for select to authenticated
using (
  exists (
    select 1
    from public.work_logs wl
    join public.profiles sup on sup.id = auth.uid()
    join public.profiles op  on op.id = wl.operator_id
    where wl.id = work_log_gerks.work_log_id
      and sup.role = 'supervisor'
      and sup.organization is not null
      and op.organization = sup.organization
  )
);

create policy "Admins can view all work log road time" on public.work_log_road_time
for select
using (
  exists (select 1 from public.profiles where profiles.id = auth.uid() and profiles.role = 'admin')
);

create policy "Supervisors can view org work log road time" on public.work_log_road_time
for select to authenticated
using (
  exists (
    select 1
    from public.work_logs wl
    join public.profiles sup on sup.id = auth.uid()
    join public.profiles op  on op.id = wl.operator_id
    where wl.id = work_log_road_time.work_log_id
      and sup.role = 'supervisor'
      and sup.organization is not null
      and op.organization = sup.organization
  )
);
