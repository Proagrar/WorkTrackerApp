-- ============================================================
-- WorkTracker — fix + prevent RETURNS TABLE ambiguous-column bug
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================
--
-- get_work_order_gerk_shapes was missing #variable_conflict use_column
-- (the other two functions written in the same migration had it — this
-- one just got missed). Its CTE has a bare "gerk_code" reference that
-- collides with the RETURNS TABLE(gerk_code text, ...) output column,
-- which without the pragma raises 42702 "column reference is
-- ambiguous" on every call. Since this RPC's error is the one checked
-- in the frontend's Promise.all guard (showWoDetailMap), that error
-- silently aborted the whole map/segmentation-icon render for every
-- work order — not just ones with text-named GERKs.
--
-- While fixing it, auditing every other RETURNS TABLE function in the
-- project for the same gap: the 6 others below don't currently have an
-- ambiguous bare reference (their local variables happen to be
-- prefixed differently, or their bare references don't share a name
-- with an output column), but adding the pragma is free insurance
-- against the next edit introducing one — which is exactly how this
-- bit get_work_order_gerk_shapes in the first place. Not touched:
-- get_work_orders_durations (language sql, pragma doesn't apply).

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

create or replace function public.add_road_time(
    p_work_order_id uuid,
    p_minutes integer,
    p_vehicle_type text default 'Traktor'::text,
    p_work_date date default current_date
)
 returns table(log_id uuid, road_duration integer, entries jsonb)
 language plpgsql
 set search_path to 'public'
as $$
#variable_conflict use_column
declare
    v_log_id uuid;
begin
    if auth.uid() is null then
        raise exception 'Not authenticated';
    end if;

    if p_minutes is null or p_minutes <= 0 then
        raise exception 'Neveljavno trajanje';
    end if;

    if p_vehicle_type not in ('Avto', 'Traktor') then
        raise exception 'Neveljaven tip vozila';
    end if;

    insert into public.work_logs (operator_id, work_order_id, work_date, work_duration)
    values (auth.uid(), p_work_order_id, p_work_date, 0)
    on conflict (operator_id, work_order_id, work_date)
        where work_order_id <> '4f17ae46-3c22-49b8-b078-054575784e9f'
    do update set work_date = excluded.work_date
    returning id into v_log_id;

    insert into public.work_log_road_time (work_log_id, minutes, vehicle_type)
    values (v_log_id, p_minutes, p_vehicle_type);

    update public.work_logs
       set road_duration = coalesce((
               select sum(r.minutes) from public.work_log_road_time r where r.work_log_id = v_log_id
           ), 0)
     where id = v_log_id;

    return query
        select v_log_id, wl.road_duration,
               coalesce((
                   select jsonb_agg(jsonb_build_object('id', r.id, 'minutes', r.minutes, 'vehicle_type', r.vehicle_type) order by r.created_at)
                     from public.work_log_road_time r where r.work_log_id = v_log_id
               ), '[]'::jsonb)
          from public.work_logs wl
         where wl.id = v_log_id;
end;
$$;

create or replace function public.remove_road_time(p_entry_id uuid)
 returns table(log_id uuid, road_duration integer, entries jsonb)
 language plpgsql
 set search_path to 'public'
as $$
#variable_conflict use_column
declare
    v_log_id uuid;
begin
    if auth.uid() is null then
        raise exception 'Not authenticated';
    end if;

    select work_log_id into v_log_id from public.work_log_road_time where id = p_entry_id;
    if v_log_id is null then
        raise exception 'Vnos ne obstaja';
    end if;

    delete from public.work_log_road_time where id = p_entry_id;

    update public.work_logs
       set road_duration = coalesce((
               select sum(r.minutes) from public.work_log_road_time r where r.work_log_id = v_log_id
           ), 0)
     where id = v_log_id;

    return query
        select v_log_id, wl.road_duration,
               coalesce((
                   select jsonb_agg(jsonb_build_object('id', r.id, 'minutes', r.minutes, 'vehicle_type', r.vehicle_type) order by r.created_at)
                     from public.work_log_road_time r where r.work_log_id = v_log_id
               ), '[]'::jsonb)
          from public.work_logs wl
         where wl.id = v_log_id;
end;
$$;

create or replace function public.capture_sample_location(p_sample_id uuid, p_lat double precision, p_lng double precision)
 returns table(id uuid, lat double precision, lng double precision)
 language plpgsql
 security definer
 set search_path to 'public'
as $$
#variable_conflict use_column
begin
    if auth.uid() is null then
        raise exception 'Not authenticated';
    end if;

    if p_lat is null or p_lng is null or p_lat < -90 or p_lat > 90 or p_lng < -180 or p_lng > 180 then
        raise exception 'Neveljavne koordinate';
    end if;

    if not exists (
        select 1
          from public.delovni_nalogi_vzorci v
          join public.delovni_nalogi_gerki g on g.id = v.delovni_nalog_gerk_id
          join public.delovni_nalogi dn on dn.id = g.delovni_nalog_id
         where v.id = p_sample_id
           and dn.status = any (array['Plan', 'V delu'])
    ) then
        raise exception 'Vzorec ne obstaja ali ni več na voljo za urejanje';
    end if;

    update public.delovni_nalogi_vzorci
       set lat = p_lat, lng = p_lng
     where delovni_nalogi_vzorci.id = p_sample_id;

    return query select v.id, v.lat, v.lng from public.delovni_nalogi_vzorci v where v.id = p_sample_id;
end;
$$;

create or replace function public.get_work_order_center_point(p_work_order_id uuid)
 returns table(lat double precision, lng double precision, matched_count integer, total_count integer)
 language plpgsql
 security definer
 set search_path to 'public'
as $$
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
      join public.gerk_polygon gp on gp.gerk_id = ng.gerk_int;

    return query select v_lat, v_lng, coalesce(v_matched, 0), v_total;
end;
$$;

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
      left join public.gerk_polygon gp on gp.gerk_id = ng.gerk_int
     group by ng.delovni_nalog_id;
end;
$$;

create or replace function public.move_work_log_date(p_work_order_id uuid, p_old_date date, p_new_date date)
 returns table(log_id uuid)
 language plpgsql
 security definer
 set search_path to 'public'
as $$
#variable_conflict use_column
declare
    v_old_log_id uuid;
    v_new_log_id uuid;
begin
    if auth.uid() is null then
        raise exception 'Not authenticated';
    end if;

    select id into v_old_log_id
      from public.work_logs
     where operator_id = auth.uid()
       and work_order_id = p_work_order_id
       and work_date = p_old_date;

    if v_old_log_id is null or p_old_date = p_new_date then
        return query select v_old_log_id;
        return;
    end if;

    -- Find-or-create the target day's log.
    insert into public.work_logs (operator_id, work_order_id, work_date, work_duration)
    values (auth.uid(), p_work_order_id, p_new_date, 0)
    on conflict (operator_id, work_order_id, work_date)
        where work_order_id <> '4f17ae46-3c22-49b8-b078-054575784e9f'
    do update set work_date = excluded.work_date
    returning id into v_new_log_id;

    -- GERK rows: reparent any not already present on the target day.
    -- Anything left over is a genuine same-GERK clash on both days —
    -- dropped rather than silently overwriting either side.
    update public.work_log_gerks
       set work_log_id = v_new_log_id
     where work_log_id = v_old_log_id
       and gerk_code not in (
           select gerk_code from public.work_log_gerks where work_log_id = v_new_log_id
       );
    delete from public.work_log_gerks where work_log_id = v_old_log_id;

    -- Road time: no natural per-row conflict, always safe to reparent.
    update public.work_log_road_time
       set work_log_id = v_new_log_id
     where work_log_id = v_old_log_id;

    -- Tractor/description: target's own value wins if already set,
    -- otherwise adopt whatever was on the day being moved.
    update public.work_logs tgt
       set tractor     = coalesce(nullif(tgt.tractor, ''), src.tractor),
           description = coalesce(nullif(tgt.description, ''), src.description)
      from public.work_logs src
     where tgt.id = v_new_log_id
       and src.id = v_old_log_id;

    update public.work_logs
       set work_duration = coalesce((
               select round(sum(g.duration) / 60.0)
                 from public.work_log_gerks g
                where g.work_log_id = v_new_log_id
           ), 0),
           road_duration = coalesce((
               select sum(r.minutes)
                 from public.work_log_road_time r
                where r.work_log_id = v_new_log_id
           ), 0)
     where id = v_new_log_id;

    delete from public.work_logs where id = v_old_log_id;

    return query select v_new_log_id;
end;
$$;

select pg_notify('pgrst', 'reload schema');
