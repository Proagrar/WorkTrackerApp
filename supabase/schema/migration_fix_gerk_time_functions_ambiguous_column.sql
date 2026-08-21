-- ============================================================
-- WorkTracker — Fix ambiguous "work_duration" in GERK time RPCs
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================
--
-- start_gerk, end_gerk and set_gerk_times all declare
-- RETURNS TABLE(..., work_duration integer) — which makes PL/pgSQL
-- implicitly declare "work_duration" as an OUT-parameter variable
-- inside the function body. Each of them ALSO runs
-- "update work_logs set work_duration = ... where id = ..." — a bare
-- reference that's now ambiguous between that implicit variable and
-- the real work_logs.work_duration column, so Postgres throws
-- "column reference \"work_duration\" is ambiguous" (PostgREST surfaces
-- this as a plain 400 with no clearer message).
--
-- Confirmed via logs 2026-08-17: a POST to /rpc/set_gerk_times failed
-- with exactly this error, specifically inside the branch that moves a
-- GERK's time entry to a different date (its own per-GERK date field,
-- via the pencil-icon edit panel — a code path noted as never having
-- been live-tested when it was written). start_gerk/end_gerk have the
-- identical RETURNS TABLE + UPDATE shape and are fixed here too rather
-- than left as latent risk, even though only set_gerk_times has
-- actually been observed to fail.
--
-- Fix: #variable_conflict use_column is Postgres's documented pragma
-- for exactly this situation — it makes every bare identifier inside
-- the function prefer a real table column over a same-named variable,
-- which is what every one of these bare "work_duration" references
-- always meant. No logic changes otherwise.

create or replace function public.start_gerk(
    p_work_order_id uuid,
    p_gerk_code     text,
    p_work_date     date default current_date
)
returns table (
    log_id        uuid,
    gerk_id       uuid,
    start_time    timestamptz,
    end_time      timestamptz,
    duration      integer,
    completed     boolean,
    work_duration integer
)
language plpgsql
set search_path = public
as $$
#variable_conflict use_column
declare
    v_log_id   uuid;
    v_hectares numeric;
begin
    if auth.uid() is null then
        raise exception 'Not authenticated';
    end if;

    select kolicina_ha into v_hectares
      from public.delovni_nalogi_gerki
     where delovni_nalog_id = p_work_order_id and gerk_code = p_gerk_code;

    insert into public.work_logs (operator_id, work_order_id, work_date, work_duration)
    values (auth.uid(), p_work_order_id, p_work_date, 0)
    on conflict (operator_id, work_order_id, work_date)
        where work_order_id <> '4f17ae46-3c22-49b8-b078-054575784e9f'
    do update set work_date = excluded.work_date
    returning id into v_log_id;

    insert into public.work_log_gerks (work_log_id, gerk_code, hectares)
    values (v_log_id, p_gerk_code, v_hectares)
    on conflict (work_log_id, gerk_code) do nothing;

    update public.work_log_gerks
       set start_time = now(),
           end_time   = null,
           duration   = null,
           completed  = false
     where work_log_id = v_log_id and gerk_code = p_gerk_code;

    update public.work_logs
       set work_duration = coalesce((
               select round(sum(g.duration) / 60.0)
                 from public.work_log_gerks g
                where g.work_log_id = v_log_id
           ), 0)
     where id = v_log_id;

    return query
        select v_log_id, g.id, g.start_time, g.end_time, g.duration, g.completed, wl.work_duration
          from public.work_log_gerks g
          join public.work_logs wl on wl.id = v_log_id
         where g.work_log_id = v_log_id and g.gerk_code = p_gerk_code;
end;
$$;

create or replace function public.end_gerk(
    p_work_order_id uuid,
    p_gerk_code     text,
    p_work_date     date default current_date
)
returns table (
    log_id        uuid,
    gerk_id       uuid,
    start_time    timestamptz,
    end_time      timestamptz,
    duration      integer,
    completed     boolean,
    work_duration integer
)
language plpgsql
set search_path = public
as $$
#variable_conflict use_column
declare
    v_log_id     uuid;
    v_start_time timestamptz;
begin
    if auth.uid() is null then
        raise exception 'Not authenticated';
    end if;

    select id into v_log_id
      from public.work_logs
     where operator_id = auth.uid() and work_order_id = p_work_order_id and work_date = p_work_date;

    if v_log_id is null then
        raise exception 'Delo za ta dan še ni bilo začeto';
    end if;

    select g.start_time into v_start_time
      from public.work_log_gerks g
     where g.work_log_id = v_log_id and g.gerk_code = p_gerk_code;

    if v_start_time is null then
        raise exception 'Najprej pritisnite Start';
    end if;

    update public.work_log_gerks
       set end_time  = now(),
           duration  = greatest(0, extract(epoch from (now() - v_start_time))::int),
           completed = true
     where work_log_id = v_log_id and gerk_code = p_gerk_code;

    update public.work_logs
       set work_duration = coalesce((
               select round(sum(g.duration) / 60.0)
                 from public.work_log_gerks g
                where g.work_log_id = v_log_id
           ), 0)
     where id = v_log_id;

    return query
        select v_log_id, g.id, g.start_time, g.end_time, g.duration, g.completed, wl.work_duration
          from public.work_log_gerks g
          join public.work_logs wl on wl.id = v_log_id
         where g.work_log_id = v_log_id and g.gerk_code = p_gerk_code;
end;
$$;

create or replace function public.set_gerk_times(
    p_work_order_id    uuid,
    p_gerk_code        text,
    p_start_time       timestamptz,
    p_end_time         timestamptz,
    p_work_date        date default current_date,
    p_previous_work_date date default null::date
)
returns table (
    log_id        uuid,
    gerk_id       uuid,
    start_time    timestamptz,
    end_time      timestamptz,
    duration      integer,
    completed     boolean,
    work_duration integer
)
language plpgsql
set search_path = public
as $$
#variable_conflict use_column
declare
    v_log_id     uuid;
    v_old_log_id uuid;
    v_hectares   numeric;
    v_duration   integer;
begin
    if auth.uid() is null then
        raise exception 'Not authenticated';
    end if;

    if p_start_time is not null and p_end_time is not null and p_end_time < p_start_time then
        raise exception 'Konec ne more biti pred začetkom';
    end if;

    -- Moving to a different day: clear this GERK's entry out of its
    -- previous day's log first, so it isn't left logged on both days.
    if p_previous_work_date is not null and p_previous_work_date <> p_work_date then
        select id into v_old_log_id
          from public.work_logs
         where operator_id = auth.uid()
           and work_order_id = p_work_order_id
           and work_date = p_previous_work_date;

        if v_old_log_id is not null then
            delete from public.work_log_gerks
             where work_log_id = v_old_log_id and gerk_code = p_gerk_code;

            update public.work_logs
               set work_duration = coalesce((
                       select round(sum(g.duration) / 60.0)
                         from public.work_log_gerks g
                        where g.work_log_id = v_old_log_id
                   ), 0)
             where id = v_old_log_id;

            -- Don't leave a phantom 0h row in Evidenca dela if that was
            -- the only thing on the old day's log.
            delete from public.work_logs
             where id = v_old_log_id
               and work_duration = 0
               and coalesce(road_duration, 0) = 0
               and coalesce(tractor, '') = ''
               and coalesce(description, '') = ''
               and not exists (select 1 from public.work_log_gerks g where g.work_log_id = v_old_log_id)
               and not exists (select 1 from public.work_log_road_time r where r.work_log_id = v_old_log_id);
        end if;
    end if;

    select kolicina_ha into v_hectares
      from public.delovni_nalogi_gerki
     where delovni_nalog_id = p_work_order_id and gerk_code = p_gerk_code;

    insert into public.work_logs (operator_id, work_order_id, work_date, work_duration)
    values (auth.uid(), p_work_order_id, p_work_date, 0)
    on conflict (operator_id, work_order_id, work_date)
        where work_order_id <> '4f17ae46-3c22-49b8-b078-054575784e9f'
    do update set work_date = excluded.work_date
    returning id into v_log_id;

    insert into public.work_log_gerks (work_log_id, gerk_code, hectares)
    values (v_log_id, p_gerk_code, v_hectares)
    on conflict (work_log_id, gerk_code) do nothing;

    v_duration := case
        when p_start_time is not null and p_end_time is not null
            then greatest(0, extract(epoch from (p_end_time - p_start_time))::int)
        else null
    end;

    update public.work_log_gerks
       set start_time = p_start_time,
           end_time   = p_end_time,
           duration   = v_duration,
           completed  = (p_end_time is not null)
     where work_log_id = v_log_id and gerk_code = p_gerk_code;

    update public.work_logs
       set work_duration = coalesce((
               select round(sum(g.duration) / 60.0)
                 from public.work_log_gerks g
                where g.work_log_id = v_log_id
           ), 0)
     where id = v_log_id;

    return query
        select v_log_id, g.id, g.start_time, g.end_time, g.duration, g.completed, wl.work_duration
          from public.work_log_gerks g
          join public.work_logs wl on wl.id = v_log_id
         where g.work_log_id = v_log_id and g.gerk_code = p_gerk_code;
end;
$$;
