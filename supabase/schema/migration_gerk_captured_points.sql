-- ============================================================
-- WorkTracker — Operator-captured soil-sampling points
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================
--
-- gerk_segment_point (see migration_gerk_segment_import.sql) holds
-- the *planned* points from an imported KML — where a sample is
-- supposed to be taken. This is the counterpart: where an operator
-- actually stood and tapped "capture" while doing the work, on a
-- given work order. Same trio of connections the earlier segmentation
-- work established (gerk / segmentation / segment), but this one is
-- written by operators in the field, not imported by an admin — so
-- unlike gerk_polygon_ours/gerk_segmentation/gerk_segment, this data
-- does have an app-side write path (open to any authenticated user,
-- same as the sample-location capture it replaces).
--
-- Which GERK a point belongs to is resolved server-side by spatial
-- containment against that work order's GERK shapes (preferring
-- gerk_polygon_ours over gerk_polygon, same as the map itself) so the
-- operator doesn't have to pick one manually. If no shape contains
-- the point but the order only has a single GERK, it's assigned there
-- directly — keeps single-GERK orders working even without polygon
-- data. Segment/segmentation are filled in the same way when the
-- point falls inside an imported zone; both stay null otherwise.
--
-- point_no is one running sequence per work order (not per GERK) —
-- matches the flat "Point 1, 2, 3…" list the capture panel shows.

create table public.gerk_captured_point (
    id                uuid primary key default gen_random_uuid(),
    delovni_nalog_id  uuid not null references public.delovni_nalogi(id) on delete cascade,
    gerk_code         text not null,
    segmentation_id   uuid references public.gerk_segmentation(id),
    segment_id        uuid references public.gerk_segment(id),
    point_no          integer not null,
    point             geometry(Point, 4326) not null,
    operator_id       uuid not null references public.profiles(id),
    captured_at       timestamptz not null default now()
);

create index gerk_captured_point_delovni_nalog_id_idx on public.gerk_captured_point (delovni_nalog_id);

alter table public.gerk_captured_point enable row level security;

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

    if v_gerk_code is null then
        raise exception 'Lokacija ne pripada nobenemu GERK-u na tem nalogu';
    end if;

    -- A GERK can have more than one segmentation on file — prefer the
    -- one still currently valid (valid_to null or in the future),
    -- most recently started, when more than one zone happens to match.
    select seg.id, seg.label, gs.id
      into v_segment_id, v_segment_label, v_segmentation_id
      from public.gerk_segmentation gs
      join public.gerk_segment seg on seg.segmentation_id = gs.id
     where gs.gerk_id = v_gerk_code::int
       and ST_Contains(seg.polygon_points, v_point)
     order by (gs.valid_to is null or gs.valid_to >= current_date) desc, gs.valid_from desc
     limit 1;

    select coalesce(max(point_no), 0) + 1 into v_point_no
      from public.gerk_captured_point
     where delovni_nalog_id = p_work_order_id;

    insert into public.gerk_captured_point (delovni_nalog_id, gerk_code, segmentation_id, segment_id, point_no, point, operator_id)
    values (p_work_order_id, v_gerk_code, v_segmentation_id, v_segment_id, v_point_no, v_point, auth.uid())
    returning gerk_captured_point.id into v_id;

    return query select v_id, v_gerk_code, v_point_no, p_lat, p_lng, v_segment_label;
end;
$$;

create or replace function public.get_work_order_captured_points(p_work_order_id uuid)
 returns table(
   id            uuid,
   gerk_code     text,
   point_no      integer,
   lat           double precision,
   lng           double precision,
   segment_label text,
   operator_name text,
   captured_at   timestamptz
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
    select cp.id, cp.gerk_code, cp.point_no,
           ST_Y(cp.point), ST_X(cp.point),
           seg.label, pr.full_name, cp.captured_at
      from public.gerk_captured_point cp
      left join public.gerk_segment seg on seg.id = cp.segment_id
      left join public.profiles pr on pr.id = cp.operator_id
     where cp.delovni_nalog_id = p_work_order_id
     order by cp.point_no;
end;
$$;

-- Correcting a mis-tap is a field action too — open to the operator
-- who captured it, or an admin, while the order is still active.
create or replace function public.remove_gerk_captured_point(p_point_id uuid)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $$
#variable_conflict use_column
begin
    if auth.uid() is null then
        raise exception 'Not authenticated';
    end if;

    delete from public.gerk_captured_point cp
     using public.delovni_nalogi dn
     where cp.id = p_point_id
       and cp.delovni_nalog_id = dn.id
       and dn.status = any (array['Plan', 'V delu'])
       and (
         cp.operator_id = auth.uid()
         or exists (select 1 from public.profiles where id = auth.uid() and role = 'admin')
       );

    if not found then
        raise exception 'Točka ne obstaja ali nimate dovoljenja za brisanje';
    end if;
end;
$$;

revoke all on function public.capture_gerk_point(uuid, double precision, double precision) from public, anon;
grant execute on function public.capture_gerk_point(uuid, double precision, double precision) to authenticated;

revoke all on function public.get_work_order_captured_points(uuid) from public, anon;
grant execute on function public.get_work_order_captured_points(uuid) to authenticated;

revoke all on function public.remove_gerk_captured_point(uuid) from public, anon;
grant execute on function public.remove_gerk_captured_point(uuid) to authenticated;

select pg_notify('pgrst', 'reload schema');
