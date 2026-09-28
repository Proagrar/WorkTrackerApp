-- ============================================================
-- WorkTracker -- add a guaranteed-inside-polygon label point for
-- imported KML segments, so the segment label never renders outside
-- its own border (or inside a neighboring segment's border).
-- Run in: Supabase Dashboard -> SQL Editor -> New Query
-- ============================================================
--
-- Root cause: the map bound the segment label as a Leaflet tooltip
-- with direction: 'center', which for a GeoJSON polygon layer
-- resolves to the layer's BOUNDING-BOX center (getBounds().getCenter()),
-- not the polygon's true centroid. For irregular/elongated/L-shaped
-- sampling zones -- common in real fields -- the bounding-box center
-- routinely falls outside the polygon entirely, or inside a
-- different, tightly-packed neighboring zone.
--
-- Fix: compute ST_PointOnSurface(polygon), which PostGIS guarantees
-- to be a point actually ON/inside the polygon's surface (unlike a
-- plain centroid, which can still land outside for concave shapes).
-- app.js positions the label tooltip at this point directly instead
-- of relying on Leaflet's bounds-based 'center' direction.

create or replace function public.get_work_order_gerk_segments(p_work_order_id uuid)
returns table(
    gerk_code text, segmentation_id uuid, seg_type text, valid_from date, valid_to date,
    segment_id uuid, segment_label text, segment_geojson jsonb, label_point jsonb, points jsonb
)
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
    select dng.gerk_code,
           gs.id,
           gs.type,
           gs.valid_from,
           gs.valid_to,
           seg.id,
           seg.label,
           ST_AsGeoJSON(seg.polygon_points)::jsonb,
           ST_AsGeoJSON(ST_PointOnSurface(seg.polygon_points))::jsonb,
           coalesce(
             (select jsonb_agg(jsonb_build_object('point_no', p.point_no, 'geojson', ST_AsGeoJSON(p.point)::jsonb) order by p.point_no)
                from public.gerk_segment_point p
               where p.segment_id = seg.id),
             '[]'::jsonb
           )
      from public.delovni_nalogi_gerki dng
      join public.gerk_segmentation gs on gs.gerk_id = dng.gerk_code
      join public.gerk_segment seg on seg.segmentation_id = gs.id
     where dng.delovni_nalog_id = p_work_order_id;
end;
$$;

revoke all on function public.get_work_order_gerk_segments(uuid) from public, anon;
grant execute on function public.get_work_order_gerk_segments(uuid) to authenticated;

select pg_notify('pgrst', 'reload schema');
