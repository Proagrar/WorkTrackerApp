-- ============================================================
-- WorkTracker — Let the manual hours edit also move an entry to a
-- different day, not just adjust its time-of-day
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================
--
-- The edit panel (pencil icon on a GERK row) now includes a date field
-- alongside start/end time. If the operator changes it to a different
-- day than the one currently open, that's not an in-place edit — the
-- entry has to move: cleared out of the old day's log and written into
-- the new day's log, otherwise the same hours would end up logged
-- twice. set_gerk_times gains p_previous_work_date so the client can
-- say "this row currently lives under this other date" and have the
-- move happen atomically server-side.

drop function if exists public.set_gerk_times(uuid, text, timestamptz, timestamptz, date);

create or replace function public.set_gerk_times(
    p_work_order_id       uuid,
    p_gerk_code           text,
    p_start_time          timestamptz,
    p_end_time            timestamptz,
    p_work_date           date default current_date,
    p_previous_work_date  date default null
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


-- ── Grants ────────────────────────────────────────────────────
-- Supabase grants EXECUTE directly to anon/authenticated/service_role on
-- new functions (not via PUBLIC) — revoking from PUBLIC alone is a no-op
-- here. Must revoke from anon by name.
revoke execute on function public.set_gerk_times(uuid, text, timestamptz, timestamptz, date, date) from public, anon;
grant execute on function public.set_gerk_times(uuid, text, timestamptz, timestamptz, date, date) to authenticated;
