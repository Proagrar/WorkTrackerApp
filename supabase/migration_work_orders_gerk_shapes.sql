-- ============================================================
-- WorkTracker — switch the map overview from pins to real field
-- boundaries (replaces get_work_orders_gerk_points with
-- get_work_orders_gerk_shapes)
-- Run in: Supabase Dashboard -> SQL Editor -> New Query
-- ============================================================
--
-- Same registry-then-zone-fallback shape as get_work_order_gerk_shapes
-- (the per-work-order detail map's own function) and
-- get_work_order_gerk_segments, just across every non-archived work
-- order at once instead of one. Scale check before building this:
-- only 29 active work orders / 140 GERK rows today, so returning full
-- polygon geometry (heavier than a lat/lng pair) for all of them at
-- once is fine — nowhere near the ~5,000-row scale of the whole
-- fields registry.
--
-- One row per shape, not per GERK: a GERK with an official registry
-- boundary gets one row (that boundary); a GERK covered only by
-- imported KML zones gets one row PER zone/segment, each its own
-- polygon — matching how the single-work-order detail map already
-- draws segments individually rather than merging them into one blob.

drop function if exists public.get_work_orders_gerk_points();

create or replace function public.get_work_orders_gerk_shapes()
returns table(delovni_nalog_id uuid, status text, gerk_code text, geojson jsonb)
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
    registry_shapes as (
        select ng.id, ng.delovni_nalog_id, ng.gerk_code,
               coalesce(gpo.polygon_points, gp.polygon_points) as geom
          from numeric_gerks ng
          left join public.gerk_polygon_ours gpo on gpo.gerk_id = ng.gerk_int
          left join public.gerk_polygon gp on gp.gerk_id = ng.gerk_int and gp.drzava = 'SI'
    ),
    segment_shapes as (
        select dng.id, dng.delovni_nalog_id, dng.gerk_code, seg.polygon_points as geom
          from public.delovni_nalogi_gerki dng
          join public.gerk_segmentation gs on gs.gerk_id = dng.gerk_code
          join public.gerk_segment seg on seg.segmentation_id = gs.id
         where dng.id not in (select id from registry_shapes where geom is not null)
    ),
    all_shapes as (
        select delovni_nalog_id, gerk_code, geom from registry_shapes where geom is not null
        union all
        select delovni_nalog_id, gerk_code, geom from segment_shapes where geom is not null
    )
    select a.delovni_nalog_id, dn.status, a.gerk_code, ST_AsGeoJSON(a.geom)::jsonb
      from all_shapes a
      join public.delovni_nalogi dn on dn.id = a.delovni_nalog_id
     where dn.deleted_at is null;
end;
$$;

revoke all on function public.get_work_orders_gerk_shapes() from public, anon;
grant execute on function public.get_work_orders_gerk_shapes() to authenticated;

select pg_notify('pgrst', 'reload schema');
