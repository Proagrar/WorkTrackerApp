-- ============================================================
-- WorkTracker — KML re-import replaces, never duplicates
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================
--
-- One-off cleanup first: the second "Pangos L P2" import created a
-- duplicate of the already-working segmentation. Keeping the earlier
-- one, dropping the later duplicate (identical 4 zones either way).
update public.gerk_captured_point
   set segmentation_id = null, segment_id = null
 where segmentation_id = 'e8ad2b6d-35de-43bd-92bd-891062451377';
delete from public.gerk_segmentation where id = 'e8ad2b6d-35de-43bd-92bd-891062451377';

-- Going forward: import_gerk_segmentation now replaces any existing
-- segmentation for the same (gerk_id, type) instead of adding another
-- one alongside it — re-importing the same GERK/type is always a
-- clean swap, never a duplicate, regardless of whether the caller
-- checked first. Same gerk_captured_point unlink-not-delete safety as
-- remove_gerk_segmentation.
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
    v_old_id          uuid;
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

    return v_segmentation_id;
end;
$$;

-- Lets the frontend warn before calling the (now-destructive) import
-- above — "this GERK already has N zones imported for this type,
-- continuing replaces them" — instead of the replacement happening
-- silently.
create or replace function public.check_gerk_segmentation_exists(p_gerk_id text, p_type text)
 returns table(segmentation_id uuid, valid_from date, zone_count bigint)
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
    select gs.id, gs.valid_from, count(seg.id)
      from public.gerk_segmentation gs
      left join public.gerk_segment seg on seg.segmentation_id = gs.id
     where gs.gerk_id = p_gerk_id and gs.type = p_type
     group by gs.id, gs.valid_from;
end;
$$;

revoke all on function public.check_gerk_segmentation_exists(text, text) from public, anon;
grant execute on function public.check_gerk_segmentation_exists(text, text) to authenticated;

select pg_notify('pgrst', 'reload schema');
