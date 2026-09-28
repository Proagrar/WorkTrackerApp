-- ============================================================
-- WorkTracker -- one-time backfill: resolve gerk_code/segment for
-- already-captured points that predate the capture_gerk_point()
-- zone-fallback fix (migration_capture_gerk_point_zone_fallback.sql)
-- Run in: Supabase Dashboard -> SQL Editor -> New Query, AFTER that
-- migration. This one only touches rows where gerk_code is still null.
-- ============================================================
--
-- Re-runs the same two matching passes (official registry polygon,
-- then imported zone geometry) against each existing point's already-
-- stored coordinates. As of 2026-09-28, 623 of 1199 gerk_captured_point
-- rows have gerk_code is null -- most from work orders whose GERKs
-- have no official registry polygon at all, so every captured point on
-- them (like work order #84 in this session) has no gerk_code/segment
-- and the map draws them as one long unbroken line across the whole
-- work order instead of one line per GERK.
--
-- Segment/segmentation are only attached when they belong to the SAME
-- gerk_code that resolved (guards against a rare case where an official
-- match and a different GERK's zone geometry both happen to contain the
-- same point -- adjacent/overlapping fields). Existing non-null
-- segment_id/segmentation_id values are never overwritten (coalesce).

with official_resolved as (
  select distinct on (cp.id) cp.id as point_id, dng.gerk_code
    from public.gerk_captured_point cp
    join public.delovni_nalogi_gerki dng on dng.delovni_nalog_id = cp.delovni_nalog_id
    left join public.gerk_polygon_ours gpo on dng.gerk_code ~ '^[0-9]+$' and gpo.gerk_id = dng.gerk_code::int
    left join public.gerk_polygon gp on dng.gerk_code ~ '^[0-9]+$' and gp.gerk_id = dng.gerk_code::int and gp.drzava = 'SI'
   where cp.gerk_code is null
     and coalesce(gpo.polygon_points, gp.polygon_points) is not null
     and ST_Contains(coalesce(gpo.polygon_points, gp.polygon_points), cp.point)
   order by cp.id
),
zone_resolved as (
  select distinct on (cp.id) cp.id as point_id, gs.gerk_id as gerk_code, seg.id as segment_id, gs.id as segmentation_id
    from public.gerk_captured_point cp
    join public.delovni_nalogi_gerki dng on dng.delovni_nalog_id = cp.delovni_nalog_id
    join public.gerk_segmentation gs on gs.gerk_id = dng.gerk_code
    join public.gerk_segment seg on seg.segmentation_id = gs.id
   where cp.gerk_code is null
     and ST_Contains(seg.polygon_points, cp.point)
   order by cp.id, (gs.valid_to is null or gs.valid_to >= current_date) desc, gs.valid_from desc
),
resolved as (
  select cp.id as point_id,
         coalesce(o.gerk_code, z.gerk_code) as gerk_code,
         case when o.gerk_code is null or z.gerk_code = o.gerk_code then z.segment_id end as segment_id,
         case when o.gerk_code is null or z.gerk_code = o.gerk_code then z.segmentation_id end as segmentation_id
    from public.gerk_captured_point cp
    left join official_resolved o on o.point_id = cp.id
    left join zone_resolved z on z.point_id = cp.id
   where cp.gerk_code is null
     and (o.gerk_code is not null or z.gerk_code is not null)
)
update public.gerk_captured_point cp
   set gerk_code       = resolved.gerk_code,
       segment_id      = coalesce(cp.segment_id, resolved.segment_id),
       segmentation_id = coalesce(cp.segmentation_id, resolved.segmentation_id)
  from resolved
 where resolved.point_id = cp.id;
