-- ============================================================
-- WorkTracker — let admins edit any operator's GERK time entry
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================
--
-- set_gerk_times has always written under auth.uid() only, so an admin
-- opening the ✎ edit panel on a GERK that someone ELSE already logged
-- (a "locked" row, showing that operator's start/end time) silently
-- created a brand-new, separate entry under the ADMIN's own name
-- instead of touching the real one — the original entry was left
-- completely untouched, with no error shown either way.
--
-- This also means the "admin clears a field with both times blank"
-- escape hatch added in migration_one_time_log_per_gerk.sql has been a
-- silent no-op for anyone else's entry the whole time: work_log_gerks/
-- work_logs only have RLS policies for `operator_id = auth.uid()`, no
-- admin write bypass, and the function was never SECURITY DEFINER — so
-- that DELETE affected 0 rows without ever raising an error either.
--
-- Fix: make the function SECURITY DEFINER (matching every other
-- admin-only RPC in this project — get_operators_with_email,
-- create_operator, etc.) so an admin's write can actually reach
-- another operator's rows, gated by the function's own admin check
-- rather than RLS. New optional p_target_operator_id lets an admin
-- explicitly edit the entry belonging to that operator; it's ignored
-- for non-admin callers, who keep exactly today's behavior (always
-- their own auth.uid()).

drop function if exists public.set_gerk_times(uuid, text, timestamptz, timestamptz, date, date);

create or replace function public.set_gerk_times(
    p_work_order_id       uuid,
    p_gerk_code           text,
    p_start_time          timestamptz,
    p_end_time            timestamptz,
    p_work_date           date default current_date,
    p_previous_work_date  date default null,
    p_target_operator_id  uuid default null
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
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
    v_log_id          uuid;
    v_old_log_id      uuid;
    v_hectares        numeric;
    v_duration        integer;
    v_is_admin        boolean;
    v_clear_log_id    uuid;
    v_target_operator uuid;
begin
    if auth.uid() is null then
        raise exception 'Not authenticated';
    end if;

    if p_start_time is not null and p_end_time is not null and p_end_time < p_start_time then
        raise exception 'Konec ne more biti pred začetkom';
    end if;

    select exists(select 1 from public.profiles where id = auth.uid() and role = 'admin') into v_is_admin;

    -- Only an admin may target someone else's entry; anyone else always
    -- edits their own, exactly as before.
    v_target_operator := auth.uid();
    if v_is_admin and p_target_operator_id is not null then
        v_target_operator := p_target_operator_id;
    end if;

    -- Admin clearing a field (both times blank in the edit panel) is
    -- the escape hatch for the one-time-log-per-field lock — it has to
    -- be able to remove whichever entry actually exists, not just the
    -- admin's own (which usually doesn't exist at all). Now actually
    -- reaches another operator's row, since the function is DEFINER.
    if v_is_admin and p_start_time is null and p_end_time is null then
        select g.work_log_id into v_clear_log_id
          from public.work_log_gerks g
          join public.work_logs wl on wl.id = g.work_log_id
         where wl.work_order_id = p_work_order_id and g.gerk_code = p_gerk_code
         limit 1;

        if v_clear_log_id is not null then
            delete from public.work_log_gerks
             where work_log_id = v_clear_log_id and gerk_code = p_gerk_code;

            update public.work_logs
               set work_duration = coalesce((
                       select round(sum(g.duration) / 60.0)
                         from public.work_log_gerks g
                        where g.work_log_id = v_clear_log_id
                   ), 0)
             where id = v_clear_log_id;

            delete from public.work_logs
             where id = v_clear_log_id
               and work_duration = 0
               and coalesce(road_duration, 0) = 0
               and coalesce(tractor, '') = ''
               and coalesce(description, '') = ''
               and not exists (select 1 from public.work_log_gerks g where g.work_log_id = v_clear_log_id)
               and not exists (select 1 from public.work_log_road_time r where r.work_log_id = v_clear_log_id);
        end if;

        return query select null::uuid, null::uuid, null::timestamptz, null::timestamptz, null::integer, false, 0;
        return;
    end if;

    -- Moving to a different day: clear this GERK's entry out of its
    -- previous day's log first — that entry's own operator, which for
    -- a cross-operator admin edit is NOT necessarily the caller.
    if p_previous_work_date is not null and p_previous_work_date <> p_work_date then
        select id into v_old_log_id
          from public.work_logs
         where operator_id = v_target_operator
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
    values (v_target_operator, p_work_order_id, p_work_date, 0)
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
revoke execute on function public.set_gerk_times(uuid, text, timestamptz, timestamptz, date, date, uuid) from public, anon;
grant execute on function public.set_gerk_times(uuid, text, timestamptz, timestamptz, date, date, uuid) to authenticated;

-- Signature changed (new 7th param) — PostgREST won't see it until reload.
notify pgrst, 'reload schema';
