-- ============================================================
-- WorkTracker — Fix end_gerk: "column reference start_time is ambiguous"
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================
--
-- Bug: end_gerk's RETURNS TABLE declares an output column named
-- start_time. PL/pgSQL treats RETURNS TABLE columns as in-scope
-- variables for the whole function body, so the unqualified
-- `select start_time into v_start_time from work_log_gerks ...`
-- collided with that output variable — Postgres can't tell whether
-- `start_time` means the OUT parameter or the table column, and always
-- errored instead of guessing. Confirmed via Supabase logs: every real
-- Konec tap failed with exactly this error (400 from PostgREST).
-- Fix: qualify the column with the table alias.

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

-- Signature unchanged, so grants from migration_gerk_start_end_and_road_time.sql
-- carry over automatically — no new revoke/grant needed.
