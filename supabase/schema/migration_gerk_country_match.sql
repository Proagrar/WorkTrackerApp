-- Fix: GERK (Slovenia) and ARKOD (Croatia) parcel registries both use the
-- same numeric ID scheme, and gerk_polygon holds both countries' data.
-- Every function that resolves a GERK code to a shape/point hardcoded
-- `gp.drzava = 'SI'`, so a Croatian customer's parcels silently resolved to
-- whatever Slovenian parcel happens to share the same number (e.g. order
-- #99 / customer "Luka Boltiš", GERK codes 1689101, 1689660, 1691729,
-- 2580633, 3619201 — all genuinely Croatian, all showing a Slovenian
-- location instead).
--
-- Fix: resolve each order's registry country from its customer's `country`
-- field instead of hardcoding 'SI'. This mirrors the mapping already used
-- by the existing gerk_field_process_insert trigger (the only place in the
-- schema that already did this correctly, just not reachable from these
-- functions since it requires delovni_nalogi_gerki.field_id to be set,
-- which paste-only orders like #99 never populate).
--
-- Customers whose country isn't a recognized Croatia spelling (Hrvaška /
-- Hrvatska, trimmed/cased) keep the previous default of 'SI' — this is not
-- a regression for the vast majority of (Slovenian) orders, only a fix for
-- explicitly-Croatian ones.

create or replace function public.get_work_order_gerk_shapes(p_work_order_id uuid)
 returns table(gerk_code text, geojson jsonb)
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
#variable_conflict use_column
declare
    v_drzava text;
begin
    if auth.uid() is null then
        raise exception 'Not authenticated';
    end if;

    select case when upper(trim(cu.country)) in ('HRVAŠKA', 'HRVATSKA') then 'HR' else 'SI' end
      into v_drzava
      from public.delovni_nalogi dn
      left join public.customers cu on cu.id = dn.stranka_id
     where dn.id = p_work_order_id;
    v_drzava := coalesce(v_drzava, 'SI');

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
      left join public.gerk_polygon gp on gp.gerk_id = ng.gerk_int and gp.drzava = v_drzava
     where coalesce(gpo.polygon_points, gp.polygon_points) is not null;
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
    v_drzava  text;
begin
    if auth.uid() is null then
        raise exception 'Not authenticated';
    end if;

    select case when upper(trim(cu.country)) in ('HRVAŠKA', 'HRVATSKA') then 'HR' else 'SI' end
      into v_drzava
      from public.delovni_nalogi dn
      left join public.customers cu on cu.id = dn.stranka_id
     where dn.id = p_work_order_id;
    v_drzava := coalesce(v_drzava, 'SI');

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
      join public.gerk_polygon gp on gp.gerk_id = ng.gerk_int and gp.drzava = v_drzava;

    return query select v_lat, v_lng, coalesce(v_matched, 0), v_total;
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
    v_drzava          text;
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

    select case when upper(trim(cu.country)) in ('HRVAŠKA', 'HRVATSKA') then 'HR' else 'SI' end
      into v_drzava
      from public.delovni_nalogi dn
      left join public.customers cu on cu.id = dn.stranka_id
     where dn.id = p_work_order_id;
    v_drzava := coalesce(v_drzava, 'SI');

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
      left join public.gerk_polygon gp on gp.gerk_id = ng.gerk_int and gp.drzava = v_drzava
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

create or replace function public.get_work_orders_gerk_shapes()
 returns table(delovni_nalog_id uuid, status text, gerk_code text, geojson jsonb)
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
    order_country as (
        select dn.id as delovni_nalog_id,
               case when upper(trim(cu.country)) in ('HRVAŠKA', 'HRVATSKA') then 'HR' else 'SI' end as drzava
          from public.delovni_nalogi dn
          left join public.customers cu on cu.id = dn.stranka_id
    ),
    registry_shapes as (
        select ng.id, ng.sub_code, ng.delovni_nalog_id, ng.full_code as gerk_code,
               coalesce(gpo.polygon_points, gp.polygon_points) as geom
          from numeric_gerks ng
          left join order_country oc on oc.delovni_nalog_id = ng.delovni_nalog_id
          left join public.gerk_polygon_ours gpo on gpo.gerk_id = ng.gerk_int
          left join public.gerk_polygon gp on gp.gerk_id = ng.gerk_int and gp.drzava = coalesce(oc.drzava, 'SI')
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
    order_country as (
        select dn.id as delovni_nalog_id,
               case when upper(trim(cu.country)) in ('HRVAŠKA', 'HRVATSKA') then 'HR' else 'SI' end as drzava
          from public.delovni_nalogi dn
          left join public.customers cu on cu.id = dn.stranka_id
    ),
    registry_points as (
        select ng.id, ng.sub_code, ng.delovni_nalog_id,
               coalesce(gpo.center_point, gp.center_point) as pt
          from numeric_gerks ng
          left join order_country oc on oc.delovni_nalog_id = ng.delovni_nalog_id
          left join public.gerk_polygon_ours gpo on gpo.gerk_id = ng.gerk_int
          left join public.gerk_polygon gp on gp.gerk_id = ng.gerk_int and gp.drzava = coalesce(oc.drzava, 'SI')
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
$function$;
