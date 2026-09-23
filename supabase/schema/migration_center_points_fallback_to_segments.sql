-- ============================================================
-- WorkTracker — fall back to imported-zone geometry for the main
-- list's 📍 Google Maps link when a GERK has no registry match
-- Run in: Supabase Dashboard -> SQL Editor -> New Query
-- ============================================================
--
-- get_work_orders_center_points only ever looked at gerk_code's that
-- are purely numeric (gerk_code ~ '^[0-9]+$'), then joined that
-- against the official registry (gerk_polygon_ours / gerk_polygon).
-- Custom or sub-divided GERK codes (e.g. a large field split into KML
-- sub-fields like "1526437_CH1", "1526437_MO7" — the Puklavec family
-- being the concrete case) aren't purely numeric at all, so they were
-- silently skipped entirely: no row came back for that work order, no
-- pin, no maps link. The Ha figure had the exact same class of bug,
-- fixed in v2.13 / migration_backfill_gerk_ha_from_segments.sql by
-- falling back to gerk_segment's imported polygon geometry — same fix
-- here, computing a centroid instead of a sum.
--
-- For any delovni_nalogi_gerki row whose registry lookup produced no
-- point (either non-numeric code, or numeric but no polygon on file),
-- fall back to ST_Centroid(ST_Collect(...)) over that GERK's own
-- imported zones (gerk_segmentation.gerk_id = gerk_code, joined to
-- gerk_segment.polygon_points, both already SRID 4326 — no transform
-- needed). A work order mixing registered and custom-coded GERKs gets
-- a combined centroid across both sources, same as before.

create or replace function public.get_work_orders_center_points()
returns table(work_order_id uuid, lat double precision, lng double precision)
language plpgsql
security definer
set search_path to 'public'
as $$
#variable_conflict use_column
begin
    if auth.uid() is null then
        raise exception 'Not authenticated';
    end if;

    return query
    with numeric_gerks as (
        select id, delovni_nalog_id, gerk_code::int as gerk_int
          from public.delovni_nalogi_gerki
         where gerk_code ~ '^[0-9]+$'
    ),
    registry_points as (
        select ng.id, ng.delovni_nalog_id,
               coalesce(gpo.center_point, gp.center_point) as pt
          from numeric_gerks ng
          left join public.gerk_polygon_ours gpo on gpo.gerk_id = ng.gerk_int
          left join public.gerk_polygon gp on gp.gerk_id = ng.gerk_int and gp.drzava = 'SI'
    ),
    segment_points as (
        select dng.id, dng.delovni_nalog_id,
               ST_Centroid(ST_Collect(seg.polygon_points)) as pt
          from public.delovni_nalogi_gerki dng
          join public.gerk_segmentation gs on gs.gerk_id = dng.gerk_code
          join public.gerk_segment seg on seg.segmentation_id = gs.id
         where dng.id not in (select id from registry_points where pt is not null)
         group by dng.id, dng.delovni_nalog_id
    ),
    all_points as (
        select delovni_nalog_id, pt from registry_points where pt is not null
        union all
        select delovni_nalog_id, pt from segment_points where pt is not null
    )
    select delovni_nalog_id,
           ST_Y(ST_Centroid(ST_Collect(pt))),
           ST_X(ST_Centroid(ST_Collect(pt)))
      from all_points
     group by delovni_nalog_id;
end;
$$;

revoke all on function public.get_work_orders_center_points() from public, anon;
grant execute on function public.get_work_orders_center_points() to authenticated;

select pg_notify('pgrst', 'reload schema');
