-- ============================================================
-- WorkTracker — Total logged duration per work order (list column)
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================
--
-- The work-order list needs every visible row's total logged time at
-- once, not one round trip per row — same batching reasoning as
-- get_work_orders_center_points. Sums work_logs.work_duration (GERK
-- time only, already maintained in minutes by start_gerk/end_gerk/
-- set_gerk_times/move_work_log_date) across every operator and every
-- date for that work order — deliberately not road_duration, to match
-- the "Skupaj" total already shown in the detail modal.
--
-- security definer for the same reason as get_work_orders_center_points:
-- a plain SECURITY INVOKER aggregate would under-count for orders an
-- operator can't fully see via RLS (e.g. another operator's entries on
-- a completed order).

create or replace function public.get_work_orders_durations()
returns table (
    work_order_id uuid,
    total_minutes integer
)
language sql
security definer
set search_path = public
as $$
    select work_order_id, sum(work_duration)::int as total_minutes
      from public.work_logs
     where auth.uid() is not null
     group by work_order_id;
$$;

revoke execute on function public.get_work_orders_durations() from public, anon;
grant execute on function public.get_work_orders_durations() to authenticated;