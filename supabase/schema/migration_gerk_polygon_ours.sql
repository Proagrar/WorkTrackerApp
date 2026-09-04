-- ============================================================
-- WorkTracker — "Ours" GERK polygon overrides (official vs. modified)
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================
--
-- gerk_polygon holds the official MKGP-registry shape per GERK code.
-- Boundaries there can be wrong or out of date for what's actually
-- being farmed. This adds a place to store Proagrar's own corrected
-- shape per GERK — when a row exists here, the map uses it instead of
-- the official one; otherwise it falls back to gerk_polygon exactly
-- like before. Rows go in directly via the database (Table Editor /
-- SQL), not through the app — same access model as gerk_polygon
-- itself (RLS on, no policies: only SECURITY DEFINER functions and a
-- direct DB connection can read or write it).
--
-- center_point is derived from polygon_points instead of being a
-- second value to keep in sync by hand — whoever inserts a row only
-- has to supply the corrected shape.

create table public.gerk_polygon_ours (
    gerk_id        integer primary key,
    polygon_points geometry(MultiPolygon, 4326) not null,
    center_point   geometry(Point, 4326) generated always as (ST_Centroid(polygon_points)) stored,
    created_at     timestamptz not null default now()
);

alter table public.gerk_polygon_ours enable row level security;

-- Both call sites that read gerk_polygon for the map now prefer
-- gerk_polygon_ours when a row exists for that GERK. LEFT JOIN on
-- both tables (the old code had an INNER JOIN on gerk_polygon only)
-- so a GERK that exists only in "ours" — e.g. a newly split parcel
-- not yet in the official registry — still shows up instead of being
-- silently dropped from the map.

create or replace function public.get_work_order_gerk_shapes(p_work_order_id uuid)
 returns table(gerk_code text, geojson jsonb)
 language plpgsql
 security definer
 set search_path to 'public'
as $$
begin
    if auth.uid() is null then
        raise exception 'Not authenticated';
    end if;

    return query
    select dng.gerk_code,
           ST_AsGeoJSON(coalesce(gpo.polygon_points, gp.polygon_points))::jsonb
      from public.delovni_nalogi_gerki dng
      left join public.gerk_polygon_ours gpo on gpo.gerk_id = dng.gerk_code::int
      left join public.gerk_polygon gp on gp.gerk_id = dng.gerk_code::int
     where dng.delovni_nalog_id = p_work_order_id
       and dng.gerk_code ~ '^[0-9]+$'
       and coalesce(gpo.polygon_points, gp.polygon_points) is not null;
end;
$$;

create or replace function public.get_work_orders_center_points()
 returns table(work_order_id uuid, lat double precision, lng double precision)
 language plpgsql
 security definer
 set search_path to 'public'
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
           ST_Y(ST_Centroid(ST_Collect(coalesce(gpo.center_point, gp.center_point)))),
           ST_X(ST_Centroid(ST_Collect(coalesce(gpo.center_point, gp.center_point))))
      from numeric_gerks ng
      left join public.gerk_polygon_ours gpo on gpo.gerk_id = ng.gerk_int
      left join public.gerk_polygon gp on gp.gerk_id = ng.gerk_int
     group by ng.delovni_nalog_id;
end;
$$;

select pg_notify('pgrst', 'reload schema');
