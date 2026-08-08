-- ============================================================
-- WorkTracker — Work order "confirmed" flag + batched center points
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================
--
-- confirmed: admin-only review flag on the work order list. No new
-- RLS policy needed — "Admins can manage work orders" already grants
-- ALL (including UPDATE) to admins; everyone else already only has
-- SELECT via "Authenticated users can view all work orders".
--
-- get_work_orders_center_points: the list view needs every visible
-- work order's map point at once, not one RPC round trip per row
-- (get_work_order_center_point, used in the detail modal, stays as
-- the single-order version for that one case). Same SECURITY DEFINER
-- reasoning as that function — GERK_POLYGON has RLS enabled with zero
-- policies, so this can't run as SECURITY INVOKER.

alter table public.delovni_nalogi
    add column if not exists confirmed boolean not null default false;

create or replace function public.get_work_orders_center_points()
returns table (
    work_order_id uuid,
    lat           double precision,
    lng           double precision
)
language plpgsql
security definer
set search_path = public
as $$
begin
    if auth.uid() is null then
        raise exception 'Not authenticated';
    end if;

    return query
    with numeric_gerks as (
        select delovni_nalog_id, gerk_code::int as gerk_int
          from public.delovni_nalogi_gerki
         where gerk_code ~ '^[0-9]+$'
    )
    select ng.delovni_nalog_id,
           ST_Y(ST_Centroid(ST_Collect(gp."CENTER_POINT"))),
           ST_X(ST_Centroid(ST_Collect(gp."CENTER_POINT")))
      from numeric_gerks ng
      join public."GERK_POLYGON" gp on gp."GERK_ID" = ng.gerk_int
     group by ng.delovni_nalog_id;
end;
$$;

revoke execute on function public.get_work_orders_center_points() from public, anon;
grant execute on function public.get_work_orders_center_points() to authenticated;
