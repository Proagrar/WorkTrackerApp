-- ============================================================
-- WorkTracker — Work order center point (Google Maps link)
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================
--
-- GERK_POLYGON has RLS enabled with zero policies — even authenticated
-- users get nothing back from it directly, so this has to be
-- SECURITY DEFINER (same pattern as the field-declaration RPCs) to
-- actually read it, narrowly scoped to return only an aggregate point,
-- never raw table rows.
--
-- Combines the CENTER_POINT of every GERK on the work order into one
-- point via ST_Centroid(ST_Collect(...)) — the geometrically correct
-- way to combine multiple points, not a naive lat/lng average. Only
-- numeric-looking gerk_codes are matched (GERK_POLYGON.GERK_ID is the
-- raw GERK code as an integer — verified this session, ~85-100% match
-- rate on real work orders); suffixed codes like "1515325-1" are
-- skipped rather than erroring, since a straight ::int cast on those
-- fails. matched_count/total_count are returned so the client can
-- tell "found nothing" apart from "found a partial point."

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
        ST_Y(ST_Centroid(ST_Collect(gp."CENTER_POINT"))),
        ST_X(ST_Centroid(ST_Collect(gp."CENTER_POINT"))),
        count(*)
      into v_lat, v_lng, v_matched
      from numeric_gerks ng
      join public."GERK_POLYGON" gp on gp."GERK_ID" = ng.gerk_int;

    return query select v_lat, v_lng, coalesce(v_matched, 0), v_total;
end;
$$;

revoke execute on function public.get_work_order_center_point(uuid) from public, anon;
grant execute on function public.get_work_order_center_point(uuid) to authenticated;
