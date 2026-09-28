-- ============================================================
-- WorkTracker -- capture_gerk_point(): fall back to imported zone
-- geometry when resolving which GERK a captured point belongs to
-- Run in: Supabase Dashboard -> SQL Editor -> New Query
-- ============================================================
--
-- Root cause of "captured points aren't split by GERK on the map":
-- this function only ever checked the OFFICIAL registry polygon
-- (gerk_polygon_ours / gerk_polygon) for a containing match. Custom
-- or sub-divided GERKs with no registry entry (same class of gap as
-- the Ha and Google-Maps-link fixes earlier) never match, so
-- gerk_code stays null -- and the old single-GERK fallback only
-- covers work orders with exactly one GERK, so any multi-GERK work
-- order made of unregistered fields got null gerk_code (and null
-- segment_id) for every single captured point, forever.
--
-- Fix: after the official-polygon check, also try every one of this
-- work order's GERKs' imported zones (gerk_segmentation/gerk_segment)
-- for a containing match -- this resolves gerk_code AND segment_id
-- in one step, since a zone match implies which GERK it belongs to.
-- The old "exactly one GERK" fallback stays as the last resort.

create or replace function public.capture_gerk_point(p_work_order_id uuid, p_lat double precision, p_lng double precision)
returns table(id uuid, gerk_code text, point_no integer, lat double precision, lng double precision, segment_label text)
language plpgsql
security definer
set search_path to 'public'
as $$
#variable_conflict use_column
declare
    v_point           geometry;
    v_gerk_code       text;
    v_gerk_count      integer;
    v_segmentation_id uuid;
    v_segment_id      uuid;
    v_segment_label   text;
    v_point_no        integer;
    v_id              uuid;
begin
    if auth.uid() is null then
        raise exception 'Not authenticated';
    end if;

    if p_lat is null or p_lng is null or p_lat < -90 or p_lat > 90 or p_lng < -180 or p_lng > 180 then
        raise exception 'Neveljavne koordinate';
    end if;

    if not exists (
        select 1 from public.delovni_nalogi
         where id = p_work_order_id and status = any (array['Plan', 'V delu'])
    ) then
        raise exception 'Delovni nalog ne obstaja ali ni več na voljo za urejanje';
    end if;

    v_point := ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326);

    with numeric_gerks as (
        select gerk_code, gerk_code::int as gerk_int
          from public.delovni_nalogi_gerki
         where delovni_nalog_id = p_work_order_id
           and gerk_code ~ '^[0-9]+$'
    )
    select ng.gerk_code into v_gerk_code
      from numeric_gerks ng
      left join public.gerk_polygon_ours gpo on gpo.gerk_id = ng.gerk_int
      left join public.gerk_polygon gp on gp.gerk_id = ng.gerk_int and gp.drzava = 'SI'
     where ST_Contains(coalesce(gpo.polygon_points, gp.polygon_points), v_point)
     limit 1;

    if v_gerk_code is null then
        select gs.gerk_id, seg.id, seg.label, gs.id
          into v_gerk_code, v_segment_id, v_segment_label, v_segmentation_id
          from public.delovni_nalogi_gerki dng
          join public.gerk_segmentation gs on gs.gerk_id = dng.gerk_code
          join public.gerk_segment seg on seg.segmentation_id = gs.id
         where dng.delovni_nalog_id = p_work_order_id
           and ST_Contains(seg.polygon_points, v_point)
         order by (gs.valid_to is null or gs.valid_to >= current_date) desc, gs.valid_from desc
         limit 1;
    end if;

    if v_gerk_code is null then
        select count(*), min(dng.gerk_code) into v_gerk_count, v_gerk_code
          from public.delovni_nalogi_gerki dng
         where dng.delovni_nalog_id = p_work_order_id;
        if v_gerk_count <> 1 then
            v_gerk_code := null;
        end if;
    end if;

    -- Only needed when gerk_code was resolved via the official-polygon
    -- branch above (v_segment_id still null there) -- the zone-fallback
    -- branch already set it directly.
    if v_gerk_code is not null and v_segment_id is null then
        select seg.id, seg.label, gs.id
          into v_segment_id, v_segment_label, v_segmentation_id
          from public.gerk_segmentation gs
          join public.gerk_segment seg on seg.segmentation_id = gs.id
         where gs.gerk_id = v_gerk_code
           and ST_Contains(seg.polygon_points, v_point)
         order by (gs.valid_to is null or gs.valid_to >= current_date) desc, gs.valid_from desc
         limit 1;
    end if;

    select coalesce(max(point_no), 0) + 1 into v_point_no
      from public.gerk_captured_point
     where delovni_nalog_id = p_work_order_id;

    insert into public.gerk_captured_point (delovni_nalog_id, gerk_code, segmentation_id, segment_id, point_no, point, operator_id)
    values (p_work_order_id, v_gerk_code, v_segmentation_id, v_segment_id, v_point_no, v_point, auth.uid())
    returning gerk_captured_point.id into v_id;

    return query select v_id, v_gerk_code, v_point_no, p_lat, p_lng, v_segment_label;
end;
$$;

revoke all on function public.capture_gerk_point(uuid, double precision, double precision) from public, anon;
grant execute on function public.capture_gerk_point(uuid, double precision, double precision) to authenticated;

select pg_notify('pgrst', 'reload schema');
