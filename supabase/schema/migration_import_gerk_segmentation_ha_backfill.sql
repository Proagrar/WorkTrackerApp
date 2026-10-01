-- Makes the Ha backfill from imported KML geometry unconditional and
-- server-side, inside import_gerk_segmentation itself, instead of
-- relying on client-side follow-up calls (app.js's showWoDetailMap KML
-- import handler and the new-order form's confirmNewKmlImport). Both of
-- those already attempted this, but clearly weren't 100% reliable --
-- 102 GERK lines with real imported geometry ended up with kolicina_ha
-- still null (see migration_backfill_ha_from_kml.sql, the one-time
-- catch-up for the existing backlog). This closes the gap for every
-- future import, regardless of which client code path triggers it.
--
-- gerk_segmentation/gerk_segment are keyed by gerk_id alone, not per
-- work order, so a single import backfills every delovni_nalogi_gerki
-- row referencing that code across any order that uses it. Never
-- overwrites an existing kolicina_ha (manually entered or
-- registry-matched) -- same "only fill in if missing" rule the client
-- code already followed.

create or replace function public.import_gerk_segmentation(p_gerk_id text, p_type text, p_valid_from date, p_segments jsonb)
 returns uuid
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
#variable_conflict use_column
declare
    v_segmentation_id uuid;
    v_segment_id      uuid;
    v_segment         jsonb;
    v_point           jsonb;
    v_old_id          uuid;
    v_total_ha        numeric;
begin
    if not exists (select 1 from public.profiles where id = auth.uid() and role = 'admin') then
        raise exception 'Not authorized';
    end if;

    for v_old_id in
        select id from public.gerk_segmentation where gerk_id = p_gerk_id and type = p_type
    loop
        update public.gerk_captured_point
           set segmentation_id = null, segment_id = null
         where segmentation_id = v_old_id;
        delete from public.gerk_segmentation where id = v_old_id;
    end loop;

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

    select sum(seg.area_ha) into v_total_ha
      from public.gerk_segment seg
     where seg.segmentation_id = v_segmentation_id;

    if v_total_ha > 0 then
        update public.delovni_nalogi_gerki
           set kolicina_ha = v_total_ha
         where gerk_code = p_gerk_id
           and kolicina_ha is null;
    end if;

    return v_segmentation_id;
end;
$function$;
