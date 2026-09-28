-- ============================================================
-- WorkTracker — per-GERK points for the main list's map toggle
-- (admin-only "🗺 Zemljevid" view, one pin per GERK colored by its
-- work order's status)
-- Run in: Supabase Dashboard -> SQL Editor -> New Query
-- ============================================================
--
-- Same registry-then-zone-fallback shape as get_work_orders_center_points
-- (migration_center_points_fallback_to_segments.sql) — reuses that exact
-- CTE structure almost verbatim, but skips its final per-work-order
-- aggregation step: this returns one row per GERK (delovni_nalogi_gerki
-- row), not one combined centroid per work order, plus the work
-- order's status and the GERK code, for map markers that need to be
-- colored and clickable individually. Filtered to non-archived work
-- orders (deleted_at is null) since there's no reason to plot deleted
-- ones on an admin overview map.

create or replace function public.get_work_orders_gerk_points()
returns table(delovni_nalog_id uuid, status text, gerk_code text, lat double precision, lng double precision)
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
        select id, delovni_nalog_id, gerk_code, gerk_code::int as gerk_int
          from public.delovni_nalogi_gerki
         where gerk_code ~ '^[0-9]+$'
    ),
    registry_points as (
        select ng.id, ng.delovni_nalog_id, ng.gerk_code,
               coalesce(gpo.center_point, gp.center_point) as pt
          from numeric_gerks ng
          left join public.gerk_polygon_ours gpo on gpo.gerk_id = ng.gerk_int
          left join public.gerk_polygon gp on gp.gerk_id = ng.gerk_int and gp.drzava = 'SI'
    ),
    segment_points as (
        select dng.id, dng.delovni_nalog_id, dng.gerk_code,
               ST_Centroid(ST_Collect(seg.polygon_points)) as pt
          from public.delovni_nalogi_gerki dng
          join public.gerk_segmentation gs on gs.gerk_id = dng.gerk_code
          join public.gerk_segment seg on seg.segmentation_id = gs.id
         where dng.id not in (select id from registry_points where pt is not null)
         group by dng.id, dng.delovni_nalog_id, dng.gerk_code
    ),
    all_points as (
        select delovni_nalog_id, gerk_code, pt from registry_points where pt is not null
        union all
        select delovni_nalog_id, gerk_code, pt from segment_points where pt is not null
    )
    select ap.delovni_nalog_id, dn.status, ap.gerk_code,
           ST_Y(ap.pt), ST_X(ap.pt)
      from all_points ap
      join public.delovni_nalogi dn on dn.id = ap.delovni_nalog_id
     where dn.deleted_at is null;
end;
$$;

revoke all on function public.get_work_orders_gerk_points() from public, anon;
grant execute on function public.get_work_orders_gerk_points() to authenticated;

select pg_notify('pgrst', 'reload schema');
