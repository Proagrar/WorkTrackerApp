-- ============================================================
-- WorkTracker — Fix center-point RPCs: GERK_POLYGON table/column
-- case mismatch
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================
--
-- get_work_order_center_point / get_work_orders_center_points were
-- written against public."GERK_POLYGON" ("GERK_ID", "CENTER_POINT")
-- but that table no longer exists under that name — only the lower-
-- case public.gerk_polygon (gerk_id, center_point) does now. Calling
-- either RPC as an authenticated user hit "relation GERK_POLYGON
-- does not exist" (42P01), which PostgREST maps to a plain 404 —
-- indistinguishable from the earlier schema-cache 404 unless you
-- test with a real authenticated call, not just an anon-key one.
-- Anon calls never got this far (blocked by the grant revoke first),
-- which is why testing with the anon key looked like a pass.
--
-- No logic changes — same ST_Centroid(ST_Collect(...)) aggregation,
-- just pointed at the real table/column names.

create or replace function public.get_work_order_center_point(p_work_order_id uuid)
returns table (
    lat            double precision,
    lng            double precision,
    matched_count  integer,
    total_count    integer
)
language plpgsql
security definer
set search_path = public
as $$
declare
    v_total   integer;
    v_matched integer;
    v_lat     double precision;
    v_lng     double precision;
begin
    if auth.uid() is null then
        raise exception 'Not authenticated';
    end if;

    select count(*) into v_total
      from public.delovni_nalogi_gerki
     where delovni_nalog_id = p_work_order_id;

    with numeric_gerks as (
        select gerk_code::int as gerk_int
          from public.delovni_nalogi_gerki
         where delovni_nalog_id = p_work_order_id
           and gerk_code ~ '^[0-9]+$'
    )
    select
        ST_Y(ST_Centroid(ST_Collect(gp.center_point))),
        ST_X(ST_Centroid(ST_Collect(gp.center_point))),
        count(*)
      into v_lat, v_lng, v_matched
      from numeric_gerks ng
      join public.gerk_polygon gp on gp.gerk_id = ng.gerk_int;

    return query select v_lat, v_lng, coalesce(v_matched, 0), v_total;
end;
$$;

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
           ST_Y(ST_Centroid(ST_Collect(gp.center_point))),
           ST_X(ST_Centroid(ST_Collect(gp.center_point)))
      from numeric_gerks ng
      join public.gerk_polygon gp on gp.gerk_id = ng.gerk_int
     group by ng.delovni_nalog_id;
end;
$$;

revoke execute on function public.get_work_order_center_point(uuid) from public, anon;
grant execute on function public.get_work_order_center_point(uuid) to authenticated;

revoke execute on function public.get_work_orders_center_points() from public, anon;
grant execute on function public.get_work_orders_center_points() to authenticated;
