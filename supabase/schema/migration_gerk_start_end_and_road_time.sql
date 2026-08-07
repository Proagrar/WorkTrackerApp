-- ============================================================
-- WorkTracker — Explicit Start/Konec times + editable + multi-line road time
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================
--
-- Replaces the Start/Stop-with-live-ticking-timer UI with two explicit
-- buttons (Start stamps start_time=now(), Konec stamps end_time=now()),
-- both times shown next to their button, plus a manual edit (via
-- set_gerk_times) for backfilling/correcting. Drops toggle_gerk_timer
-- and set_gerk_duration — the old accumulate-across-sessions model and
-- the type-hh:mm:ss-directly flow are both superseded by this.
--
-- Also replaces the single road_duration select with a list of
-- entries in a new work_log_road_time table (one row per "Dodaj" click)
-- — work_logs.road_duration becomes a maintained sum, same pattern as
-- work_duration already is for work_log_gerks.

drop function if exists public.toggle_gerk_timer(uuid, text, date);
drop function if exists public.set_gerk_duration(uuid, text, integer, date);


-- ── 1. work_log_road_time ────────────────────────────────────
create table if not exists public.work_log_road_time (
    id          uuid primary key default gen_random_uuid(),
    work_log_id uuid not null references public.work_logs(id) on delete cascade,
    minutes     integer not null check (minutes > 0),
    created_at  timestamptz not null default now()
);

create index if not exists idx_work_log_road_time_work_log_id on public.work_log_road_time (work_log_id);

alter table public.work_log_road_time enable row level security;

drop policy if exists "Operators can view own road time"   on public.work_log_road_time;
drop policy if exists "Operators can insert own road time" on public.work_log_road_time;
drop policy if exists "Operators can delete own road time" on public.work_log_road_time;

create policy "Operators can view own road time"
    on public.work_log_road_time for select
    using (work_log_id in (select id from public.work_logs where operator_id = auth.uid()));

create policy "Operators can insert own road time"
    on public.work_log_road_time for insert
    with check (work_log_id in (select id from public.work_logs where operator_id = auth.uid()));

create policy "Operators can delete own road time"
    on public.work_log_road_time for delete
    using (work_log_id in (select id from public.work_logs where operator_id = auth.uid()));


-- ── 2. start_gerk — Start button ─────────────────────────────
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
security invoker
set search_path = public
as $$
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


-- ── 3. end_gerk — Konec button ───────────────────────────────
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
security invoker
set search_path = public
as $$
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

    select start_time into v_start_time
      from public.work_log_gerks
     where work_log_id = v_log_id and gerk_code = p_gerk_code;

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


-- ── 4. set_gerk_times — manual edit (backfill/correct) ───────
create or replace function public.set_gerk_times(
    p_work_order_id uuid,
    p_gerk_code     text,
    p_start_time    timestamptz,
    p_end_time      timestamptz,
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
security invoker
set search_path = public
as $$
declare
    v_log_id   uuid;
    v_hectares numeric;
    v_duration integer;
begin
    if auth.uid() is null then
        raise exception 'Not authenticated';
    end if;

    if p_start_time is not null and p_end_time is not null and p_end_time < p_start_time then
        raise exception 'Konec ne more biti pred začetkom';
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


-- ── 5. add_road_time / remove_road_time ──────────────────────
create or replace function public.add_road_time(
    p_work_order_id uuid,
    p_minutes       integer,
    p_work_date     date default current_date
)
returns table (
    log_id        uuid,
    road_duration integer,
    entries       jsonb
)
language plpgsql
security invoker
set search_path = public
as $$
declare
    v_log_id uuid;
begin
    if auth.uid() is null then
        raise exception 'Not authenticated';
    end if;

    if p_minutes is null or p_minutes <= 0 then
        raise exception 'Neveljavno trajanje';
    end if;

    insert into public.work_logs (operator_id, work_order_id, work_date, work_duration)
    values (auth.uid(), p_work_order_id, p_work_date, 0)
    on conflict (operator_id, work_order_id, work_date)
        where work_order_id <> '4f17ae46-3c22-49b8-b078-054575784e9f'
    do update set work_date = excluded.work_date
    returning id into v_log_id;

    insert into public.work_log_road_time (work_log_id, minutes)
    values (v_log_id, p_minutes);

    update public.work_logs
       set road_duration = coalesce((
               select sum(r.minutes) from public.work_log_road_time r where r.work_log_id = v_log_id
           ), 0)
     where id = v_log_id;

    return query
        select v_log_id, wl.road_duration,
               coalesce((
                   select jsonb_agg(jsonb_build_object('id', r.id, 'minutes', r.minutes) order by r.created_at)
                     from public.work_log_road_time r where r.work_log_id = v_log_id
               ), '[]'::jsonb)
          from public.work_logs wl
         where wl.id = v_log_id;
end;
$$;

create or replace function public.remove_road_time(p_entry_id uuid)
returns table (
    log_id        uuid,
    road_duration integer,
    entries       jsonb
)
language plpgsql
security invoker
set search_path = public
as $$
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
                   select jsonb_agg(jsonb_build_object('id', r.id, 'minutes', r.minutes) order by r.created_at)
                     from public.work_log_road_time r where r.work_log_id = v_log_id
               ), '[]'::jsonb)
          from public.work_logs wl
         where wl.id = v_log_id;
end;
$$;


-- ── 6. Grants ─────────────────────────────────────────────────
-- Supabase grants EXECUTE directly to anon/authenticated/service_role on
-- new functions (not via PUBLIC) — revoking from PUBLIC alone is a no-op
-- here. Must revoke from anon by name.
revoke execute on function public.start_gerk(uuid, text, date) from public, anon;
revoke execute on function public.end_gerk(uuid, text, date) from public, anon;
revoke execute on function public.set_gerk_times(uuid, text, timestamptz, timestamptz, date) from public, anon;
revoke execute on function public.add_road_time(uuid, integer, date) from public, anon;
revoke execute on function public.remove_road_time(uuid) from public, anon;

grant execute on function public.start_gerk(uuid, text, date) to authenticated;
grant execute on function public.end_gerk(uuid, text, date) to authenticated;
grant execute on function public.set_gerk_times(uuid, text, timestamptz, timestamptz, date) to authenticated;
grant execute on function public.add_road_time(uuid, integer, date) to authenticated;
grant execute on function public.remove_road_time(uuid) to authenticated;
