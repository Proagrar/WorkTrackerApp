-- ============================================================
-- WorkTracker — GERK segment sample points + import/read RPCs
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================
--
-- Adds the sample-point layer that goes with each gerk_segment (see
-- migration_gerk_segmentation.sql) and the two RPCs needed to make
-- the whole gerk_segmentation/gerk_segment/gerk_segment_point trio
-- reachable from the app: importing a parsed KML file (admin-only,
-- per GERK, from a work order) and reading it back for the map.
--
-- Unlike gerk_polygon_ours and the segmentation tables themselves,
-- this data now has an app-side consumer, so it's exposed the same
-- way everything else admin-facing is in this project: RLS stays on
-- with no table policies, and access goes exclusively through
-- SECURITY DEFINER RPCs (narrow, role-checked where they write).

create table public.gerk_segment_point (
    id         uuid primary key default gen_random_uuid(),
    segment_id uuid not null references public.gerk_segment(id) on delete cascade,
    point_no   integer,
    point      geometry(Point, 4326) not null,
    created_at timestamptz not null default now()
);

create index gerk_segment_point_segment_id_idx on public.gerk_segment_point (segment_id);

alter table public.gerk_segment_point enable row level security;

-- Reads every segmentation/segment/point for the GERKs on one work
-- order, in a single round trip — same batching reasoning as
-- get_work_order_gerk_shapes. One row per segment; points come back
-- as a jsonb array aggregated per segment.
create or replace function public.get_work_order_gerk_segments(p_work_order_id uuid)
 returns table(
   gerk_code       text,
   segmentation_id uuid,
   seg_type        text,
   valid_from      date,
   valid_to        date,
   segment_id      uuid,
   segment_label   text,
   segment_geojson jsonb,
   points          jsonb
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
           coalesce(
             (select jsonb_agg(jsonb_build_object('point_no', p.point_no, 'geojson', ST_AsGeoJSON(p.point)::jsonb) order by p.point_no)
                from public.gerk_segment_point p
               where p.segment_id = seg.id),
             '[]'::jsonb
           )
      from public.delovni_nalogi_gerki dng
      join public.gerk_segmentation gs on gs.gerk_id = dng.gerk_code::int
      join public.gerk_segment seg on seg.segmentation_id = gs.id
     where dng.delovni_nalog_id = p_work_order_id
       and dng.gerk_code ~ '^[0-9]+$';
end;
$$;

revoke all on function public.get_work_order_gerk_segments(uuid) from public, anon;
grant execute on function public.get_work_order_gerk_segments(uuid) to authenticated;

-- Admin-only write: one call inserts one gerk_segmentation row plus
-- all its gerk_segment (+ gerk_segment_point) children from a single
-- parsed-KML payload. p_segments shape:
--   [{"label": "10734",
--     "geojson": {<Polygon GeoJSON>},
--     "points": [{"point_no": 1, "geojson": {<Point GeoJSON>}}, ...]}, ...]
create or replace function public.import_gerk_segmentation(
    p_gerk_id    integer,
    p_type       text,
    p_valid_from date,
    p_segments   jsonb
)
 returns uuid
 language plpgsql
 security definer
 set search_path to 'public'
as $$
#variable_conflict use_column
declare
    v_segmentation_id uuid;
    v_segment_id      uuid;
    v_segment         jsonb;
    v_point           jsonb;
begin
    if not exists (select 1 from public.profiles where id = auth.uid() and role = 'admin') then
        raise exception 'Not authorized';
    end if;

    insert into public.gerk_segmentation (gerk_id, type, valid_from)
    values (p_gerk_id, p_type, p_valid_from)
    returning id into v_segmentation_id;

    for v_segment in select * from jsonb_array_elements(p_segments)
    loop
        insert into public.gerk_segment (segmentation_id, label, polygon_points)
        values (
            v_segmentation_id,
            v_segment->>'label',
            ST_Multi(ST_SetSRID(ST_GeomFromGeoJSON(v_segment->'geojson'), 4326))
        )
        returning id into v_segment_id;

        for v_point in select * from jsonb_array_elements(coalesce(v_segment->'points', '[]'::jsonb))
        loop
            insert into public.gerk_segment_point (segment_id, point_no, point)
            values (
                v_segment_id,
                (v_point->>'point_no')::integer,
                ST_SetSRID(ST_GeomFromGeoJSON(v_point->'geojson'), 4326)
            );
        end loop;
    end loop;

    return v_segmentation_id;
end;
$$;

revoke all on function public.import_gerk_segmentation(integer, text, date, jsonb) from public, anon;
grant execute on function public.import_gerk_segmentation(integer, text, date, jsonb) to authenticated;

select pg_notify('pgrst', 'reload schema');
