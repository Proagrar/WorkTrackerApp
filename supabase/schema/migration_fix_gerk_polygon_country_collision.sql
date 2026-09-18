-- ============================================================
-- WorkTracker — GERK numbers collide between SI and HR registries
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================
--
-- gerk_polygon holds both Slovenian (drzava='SI', 783,350 rows) and
-- Croatian (drzava='HR', 1,367,991 rows) cadastral parcels sharing the
-- same gerk_id numbering space. Example: gerk_id 1876991 (one of
-- Marko Mramor's fields) exists as BOTH a Slovenian parcel near his
-- other fields (lng ~15.57) and a Croatian one (lng ~16.41).
--
-- None of the functions below filtered gerk_polygon by country, so a
-- colliding GERK number could silently resolve to the wrong country's
-- parcel — or, since it's a plain join, return BOTH rows at once,
-- which corrupts anything that averages coordinates (a centroid
-- averaged across an SI+HR collision lands roughly between the two
-- countries, nowhere real). Every WorkTracker customer is Slovenian,
-- so the fix is simply: only ever join the SI side.
--
-- gerk_polygon_ours (the in-house digitized table) has no drzava
-- column and is currently empty — not part of this bug, left as is.

create or replace function public.get_work_order_gerk_shapes(p_work_order_id uuid)
 returns table(gerk_code text, geojson jsonb)
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
#variable_conflict use_column
begin
    if auth.uid() is null then
        raise exception 'Not authenticated';
    end if;

    return query
    with numeric_gerks as (
        select gerk_code, gerk_code::int as gerk_int
          from public.delovni_nalogi_gerki
         where delovni_nalog_id = p_work_order_id
           and gerk_code ~ '^[0-9]+$'
    )
    select ng.gerk_code,
           ST_AsGeoJSON(coalesce(gpo.polygon_points, gp.polygon_points))::jsonb
      from numeric_gerks ng
      left join public.gerk_polygon_ours gpo on gpo.gerk_id = ng.gerk_int
      left join public.gerk_polygon gp on gp.gerk_id = ng.gerk_int and gp.drzava = 'SI'
     where coalesce(gpo.polygon_points, gp.polygon_points) is not null;
end;
$function$;

create or replace function public.capture_gerk_point(p_work_order_id uuid, p_lat double precision, p_lng double precision)
 returns table(id uuid, gerk_code text, point_no integer, lat double precision, lng double precision, segment_label text)
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
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
        select count(*), min(dng.gerk_code) into v_gerk_count, v_gerk_code
          from public.delovni_nalogi_gerki dng
         where dng.delovni_nalog_id = p_work_order_id;
        if v_gerk_count <> 1 then
            v_gerk_code := null;
        end if;
    end if;

    if v_gerk_code is not null then
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
$function$;

create or replace function public.get_work_order_center_point(p_work_order_id uuid)
 returns table(lat double precision, lng double precision, matched_count integer, total_count integer)
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
#variable_conflict use_column
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
        ST_Y(ST_Centroid(ST_Collect(gp.center_point))),
        ST_X(ST_Centroid(ST_Collect(gp.center_point))),
        count(*)
      into v_lat, v_lng, v_matched
      from numeric_gerks ng
      join public.gerk_polygon gp on gp.gerk_id = ng.gerk_int and gp.drzava = 'SI';

    return query select v_lat, v_lng, coalesce(v_matched, 0), v_total;
end;
$function$;

create or replace function public.get_work_orders_center_points()
 returns table(work_order_id uuid, lat double precision, lng double precision)
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
#variable_conflict use_column
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
      left join public.gerk_polygon gp on gp.gerk_id = ng.gerk_int and gp.drzava = 'SI'
     group by ng.delovni_nalog_id;
end;
$function$;

select pg_notify('pgrst', 'reload schema');
