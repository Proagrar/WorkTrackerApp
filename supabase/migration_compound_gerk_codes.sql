-- ============================================================
-- WorkTracker — support "+"-joined compound GERK codes (multiple
-- real fields shown/computed as one work-order GERK line)
-- Run in: Supabase Dashboard -> SQL Editor -> New Query
-- ============================================================
--
-- Motivating case: work order 73's GERK row is coded "688697", but
-- its imported KML segmentation covers ~4.55 ha across 4 zones while
-- the single official GERK 688697 is only ~2.75 ha. The real
-- situation (per Matej) is that 3 separate official GERKs together
-- cover that area: 688697 (2.75 ha), 6492082 (0.58 ha), 6492080
-- (0.54 ha) -- all three confirmed to exist with real registry
-- polygons. This lets a GERK-code field hold "688697+6492082+6492080"
-- and have every shape/geometry lookup resolve all three, combined,
-- instead of just the first one.
--
-- Work-log/time-tracking functions (start_gerk, end_gerk,
-- set_gerk_times, move_work_log_date, check_work_order_auto_complete)
-- already treat gerk_code as an opaque text key (exact equality
-- only) -- a compound string passes through them completely
-- unchanged, nothing to update there.
--
-- Only the shape/geometry-resolving functions need to understand
-- "+": each gets a split_gerks CTE up front (unnest on '+'), every
-- existing join runs against the split sub_code instead of the whole
-- gerk_code (registry: sub_code::int; segmentation:
-- gs.gerk_id = sub_code), while the OUTPUT gerk_code column stays the
-- full compound string so the client still groups everything under
-- one map/list key. A plain (non-compound) code is just a 1-element
-- split, so existing single-code behavior is unchanged.
--
-- Where a function excludes "already resolved via registry" before
-- falling back to segmentation, the exclusion is keyed on
-- (id, sub_code), not just id -- otherwise one sub-code resolving via
-- registry would wrongly suppress a DIFFERENT sub-code's segmentation
-- fallback on the same compound row.
--
-- Deferred (not in this migration): capture_gerk_point (a newly
-- captured GPS point on a compound-coded GERK won't yet resolve which
-- one it's in -- existing single-code capture is unaffected), and
-- automatic Ha computation for compound codes.

-- ---------------------------------------------------------------
-- 1. get_work_order_gerk_shapes -- single work order's official
--    registry boundaries
-- ---------------------------------------------------------------
create or replace function public.get_work_order_gerk_shapes(p_work_order_id uuid)
returns table(gerk_code text, geojson jsonb)
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
    with split_gerks as (
        select dng.gerk_code as full_code, trim(part) as sub_code
          from public.delovni_nalogi_gerki dng,
               unnest(string_to_array(dng.gerk_code, '+')) as part
         where dng.delovni_nalog_id = p_work_order_id
    ),
    numeric_gerks as (
        select full_code, sub_code::int as gerk_int
          from split_gerks
         where sub_code ~ '^[0-9]+$'
    )
    select ng.full_code,
           ST_AsGeoJSON(coalesce(gpo.polygon_points, gp.polygon_points))::jsonb
      from numeric_gerks ng
      left join public.gerk_polygon_ours gpo on gpo.gerk_id = ng.gerk_int
      left join public.gerk_polygon gp on gp.gerk_id = ng.gerk_int and gp.drzava = 'SI'
     where coalesce(gpo.polygon_points, gp.polygon_points) is not null;
end;
$$;

-- ---------------------------------------------------------------
-- 2. get_work_order_gerk_segments -- single work order's imported
--    KML zone shapes (label_point unchanged from this session's
--    earlier fix)
-- ---------------------------------------------------------------
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
    with split_gerks as (
        select dng.gerk_code as full_code, trim(part) as sub_code
          from public.delovni_nalogi_gerki dng,
               unnest(string_to_array(dng.gerk_code, '+')) as part
         where dng.delovni_nalog_id = p_work_order_id
    )
    select sg.full_code,
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
      from split_gerks sg
      join public.gerk_segmentation gs on gs.gerk_id = sg.sub_code
      join public.gerk_segment seg on seg.segmentation_id = gs.id;
end;
$$;

-- ---------------------------------------------------------------
-- 3. get_work_orders_center_points -- main list's 📍 Google Maps pin,
--    across all work orders
-- ---------------------------------------------------------------
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
    with split_gerks as (
        select dng.id, dng.delovni_nalog_id, trim(part) as sub_code
          from public.delovni_nalogi_gerki dng,
               unnest(string_to_array(dng.gerk_code, '+')) as part
    ),
    numeric_gerks as (
        select id, delovni_nalog_id, sub_code, sub_code::int as gerk_int
          from split_gerks
         where sub_code ~ '^[0-9]+$'
    ),
    registry_points as (
        select ng.id, ng.sub_code, ng.delovni_nalog_id,
               coalesce(gpo.center_point, gp.center_point) as pt
          from numeric_gerks ng
          left join public.gerk_polygon_ours gpo on gpo.gerk_id = ng.gerk_int
          left join public.gerk_polygon gp on gp.gerk_id = ng.gerk_int and gp.drzava = 'SI'
    ),
    segment_points as (
        select sg.id, sg.sub_code, sg.delovni_nalog_id,
               ST_Centroid(ST_Collect(seg.polygon_points)) as pt
          from split_gerks sg
          join public.gerk_segmentation gs on gs.gerk_id = sg.sub_code
          join public.gerk_segment seg on seg.segmentation_id = gs.id
         where (sg.id, sg.sub_code) not in (select id, sub_code from registry_points where pt is not null)
         group by sg.id, sg.sub_code, sg.delovni_nalog_id
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

-- ---------------------------------------------------------------
-- 4. get_work_orders_gerk_shapes -- admin map-overview toggle,
--    across all work orders
-- ---------------------------------------------------------------
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
    with split_gerks as (
        select dng.id, dng.delovni_nalog_id, dng.gerk_code as full_code, trim(part) as sub_code
          from public.delovni_nalogi_gerki dng,
               unnest(string_to_array(dng.gerk_code, '+')) as part
    ),
    numeric_gerks as (
        select id, delovni_nalog_id, full_code, sub_code, sub_code::int as gerk_int
          from split_gerks
         where sub_code ~ '^[0-9]+$'
    ),
    registry_shapes as (
        select ng.id, ng.sub_code, ng.delovni_nalog_id, ng.full_code as gerk_code,
               coalesce(gpo.polygon_points, gp.polygon_points) as geom
          from numeric_gerks ng
          left join public.gerk_polygon_ours gpo on gpo.gerk_id = ng.gerk_int
          left join public.gerk_polygon gp on gp.gerk_id = ng.gerk_int and gp.drzava = 'SI'
    ),
    segment_shapes as (
        select sg.id, sg.sub_code, sg.delovni_nalog_id, sg.full_code as gerk_code, seg.polygon_points as geom
          from split_gerks sg
          join public.gerk_segmentation gs on gs.gerk_id = sg.sub_code
          join public.gerk_segment seg on seg.segmentation_id = gs.id
         where (sg.id, sg.sub_code) not in (select id, sub_code from registry_shapes where geom is not null)
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

-- Grants unchanged from each function's original migration (same
-- signatures throughout, so CREATE OR REPLACE above didn't drop them
-- -- re-asserted here only for certainty, harmless if already correct).
revoke all on function public.get_work_order_gerk_shapes(uuid) from public, anon;
grant execute on function public.get_work_order_gerk_shapes(uuid) to authenticated;
revoke all on function public.get_work_order_gerk_segments(uuid) from public, anon;
grant execute on function public.get_work_order_gerk_segments(uuid) to authenticated;
revoke all on function public.get_work_orders_center_points() from public, anon;
grant execute on function public.get_work_orders_center_points() to authenticated;
revoke all on function public.get_work_orders_gerk_shapes() from public, anon;
grant execute on function public.get_work_orders_gerk_shapes() to authenticated;

-- ---------------------------------------------------------------
-- 5. One-off data fix: work order 73's existing GERK row.
--    Plain UPDATE only -- never delete+recreate this row, its id is
--    the FK target for real logged samples/captured points and a
--    delete would cascade-destroy them.
-- ---------------------------------------------------------------
update public.delovni_nalogi_gerki
   set gerk_code = '688697+6492082+6492080'
 where id = '8d43ac6b-6b3f-462f-a467-bdbb79dd8dce'
   and gerk_code = '688697';

select pg_notify('pgrst', 'reload schema');
