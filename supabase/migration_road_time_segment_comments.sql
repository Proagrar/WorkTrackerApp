-- ============================================================
-- WorkTracker — short comment field on road time entries and segments
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================

alter table public.work_log_road_time add column if not exists comment text;
alter table public.delovni_nalogi_vzorci add column if not exists comment text;

create or replace function public.add_road_time(
    p_work_order_id uuid,
    p_minutes integer,
    p_vehicle_type text default 'Traktor'::text,
    p_work_date date default current_date,
    p_comment text default null
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

    insert into public.work_log_road_time (work_log_id, minutes, vehicle_type, comment)
    values (v_log_id, p_minutes, p_vehicle_type, nullif(trim(p_comment), ''));

    update public.work_logs
       set road_duration = coalesce((
               select sum(r.minutes) from public.work_log_road_time r where r.work_log_id = v_log_id
           ), 0)
     where id = v_log_id;

    return query
        select v_log_id, wl.road_duration,
               coalesce((
                   select jsonb_agg(jsonb_build_object('id', r.id, 'minutes', r.minutes, 'vehicle_type', r.vehicle_type, 'comment', r.comment) order by r.created_at)
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
                   select jsonb_agg(jsonb_build_object('id', r.id, 'minutes', r.minutes, 'vehicle_type', r.vehicle_type, 'comment', r.comment) order by r.created_at)
                     from public.work_log_road_time r where r.work_log_id = v_log_id
               ), '[]'::jsonb)
          from public.work_logs wl
         where wl.id = v_log_id;
end;
$$;

select pg_notify('pgrst', 'reload schema');
