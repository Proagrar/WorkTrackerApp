-- ============================================================
-- WorkTracker — Allow capturing a point outside any GERK boundary
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================
--
-- capture_gerk_point previously raised an exception when the captured
-- location didn't fall inside any of the work order's GERK shapes,
-- losing the reading entirely. Boundary/segment coverage isn't
-- complete for every GERK yet, so (temporarily) this now stores the
-- point unattributed (gerk_code/segmentation_id/segment_id left null)
-- instead of rejecting it outright. Still auto-links to the GERK and
-- segment when the point *does* fall inside a known boundary — that
-- part is unchanged.

alter table public.gerk_captured_point alter column gerk_code drop not null;

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

    select dng.gerk_code into v_gerk_code
      from public.delovni_nalogi_gerki dng
      left join public.gerk_polygon_ours gpo on gpo.gerk_id = dng.gerk_code::int
      left join public.gerk_polygon gp on gp.gerk_id = dng.gerk_code::int
     where dng.delovni_nalog_id = p_work_order_id
       and dng.gerk_code ~ '^[0-9]+$'
       and ST_Contains(coalesce(gpo.polygon_points, gp.polygon_points), v_point)
     limit 1;

    if v_gerk_code is null then
        select count(*), min(dng.gerk_code) into v_gerk_count, v_gerk_code
          from public.delovni_nalogi_gerki dng
         where dng.delovni_nalog_id = p_work_order_id
           and dng.gerk_code ~ '^[0-9]+$';
        if v_gerk_count <> 1 then
            v_gerk_code := null;
        end if;
    end if;

    -- Previously: "raise exception 'Lokacija ne pripada nobenemu
    -- GERK-u na tem nalogu'" here. Relaxed — see migration comment.
    if v_gerk_code is not null then
        select seg.id, seg.label, gs.id
          into v_segment_id, v_segment_label, v_segmentation_id
          from public.gerk_segmentation gs
          join public.gerk_segment seg on seg.segmentation_id = gs.id
         where gs.gerk_id = v_gerk_code::int
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

select pg_notify('pgrst', 'reload schema');
