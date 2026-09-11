-- ============================================================
-- WorkTracker — Allow text (non-numeric) GERK ids for KML import
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================
--
-- gerk_segmentation.gerk_id was a hard integer — fine for real GERKs,
-- but plenty of fields are only known by a common name (not in the
-- official registry at all), and delovni_nalogi_gerki.gerk_code
-- already allows that (see the earlier "varchar GERK names"
-- migration). This brings gerk_segmentation in line: gerk_id becomes
-- text, so a KML can be imported and its zones attached to a
-- string-named field too.
--
-- While touching every function that reads gerk_id, this also fixes a
-- latent crash bug the varchar-names change introduced: several of
-- them cast delovni_nalogi_gerki.gerk_code::int *inside a JOIN's ON
-- clause*, guarded only by a later "gerk_code ~ '^[0-9]+$'" in the
-- WHERE clause. That guard does NOT protect the cast — a LEFT/INNER
-- JOIN's ON condition is evaluated per candidate row during the join
-- itself, before the WHERE clause filters anything out, so a single
-- text-named GERK on a work order would throw "invalid input syntax
-- for type integer" and take down the whole map/capture RPC for that
-- order. The fix (already used correctly by get_work_orders_center_
-- points) is a CTE that filters to numeric gerk_codes *before* casting,
-- so the cast only ever runs on rows that already passed the regex.

alter table public.gerk_segmentation alter column gerk_id type text using gerk_id::text;

drop function if exists public.import_gerk_segmentation(integer, text, date, jsonb);

create or replace function public.import_gerk_segmentation(
    p_gerk_id    text,
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

-- Text-to-text join now — no cast, no numeric filter needed at all,
-- so a text-named GERK's segmentation shows up on the map/badge too.
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
      join public.gerk_segmentation gs on gs.gerk_id = dng.gerk_code
      join public.gerk_segment seg on seg.segmentation_id = gs.id
     where dng.delovni_nalog_id = p_work_order_id;
end;
$$;

-- gerk_polygon/gerk_polygon_ours stay integer-keyed (the official
-- registry's own numbering) — this just makes the numeric-only cast
-- safe via a pre-filtering CTE instead of an unguarded JOIN-clause cast.
create or replace function public.get_work_order_gerk_shapes(p_work_order_id uuid)
 returns table(gerk_code text, geojson jsonb)
 language plpgsql
 security definer
 set search_path to 'public'
as $$
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
      left join public.gerk_polygon gp on gp.gerk_id = ng.gerk_int
     where coalesce(gpo.polygon_points, gp.polygon_points) is not null;
end;
$$;

-- Same CTE-safety fix for the spatial GERK lookup, plus: the single-
-- GERK fallback no longer requires a numeric code (gerk_id is text now,
-- so there's nothing left that needs it to be), and the segmentation
-- lookup drops its now-unnecessary ::int cast.
create or replace function public.capture_gerk_point(
    p_work_order_id uuid,
    p_lat           double precision,
    p_lng           double precision
)
 returns table(
   id            uuid,
   gerk_code     text,
   point_no      integer,
   lat           double precision,
   lng           double precision,
   segment_label text
 )
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
      left join public.gerk_polygon gp on gp.gerk_id = ng.gerk_int
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
$$;

revoke all on function public.import_gerk_segmentation(text, text, date, jsonb) from public, anon;
grant execute on function public.import_gerk_segmentation(text, text, date, jsonb) to authenticated;

select pg_notify('pgrst', 'reload schema');
