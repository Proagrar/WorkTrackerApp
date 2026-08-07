-- ============================================================
-- WorkTracker — Single-round-trip GERK time logging RPCs
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================

-- The client previously chained up to ~6 sequential requests per
-- Start/Stop tap (find-or-create today's work_logs row, find-or-create
-- the field's work_log_gerks row, update it, re-sum into the parent).
-- On the patchy mobile signal operators actually work under, that
-- reads as the app hanging. These two RPCs do the whole thing
-- server-side in one call. Both run as SECURITY INVOKER (the caller's
-- own role, not elevated) — they can only ever touch rows the existing
-- RLS policies already let the caller touch directly, so there's no
-- privilege-escalation surface to worry about (unlike start_work_order,
-- which genuinely needs to act across users).

-- ── 1. Guarantee one field row per log — needed for ON CONFLICT ──
-- (verified no existing duplicates before adding this)
alter table public.work_log_gerks
    add constraint uq_work_log_gerks_log_code unique (work_log_id, gerk_code);


-- ── 2. toggle_gerk_timer — Start/Stop for one field ─────────────
-- Accumulates duration across multiple start/stop sessions on the same
-- field/day instead of overwriting it (a restart used to silently wipe
-- whatever was already recorded). Deliberately redoing a field's time
-- is now done via set_gerk_duration (typing a new value), not by
-- mis-tapping Start.
create or replace function public.toggle_gerk_timer(
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
    v_gerk     public.work_log_gerks;
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

    select * into v_gerk
      from public.work_log_gerks
     where work_log_id = v_log_id and gerk_code = p_gerk_code
     for update;

    if v_gerk.start_time is not null and v_gerk.end_time is null then
        -- running -> stop: add this session's elapsed time onto whatever
        -- was already accumulated for this field today
        update public.work_log_gerks
           set end_time  = now(),
               duration  = coalesce(v_gerk.duration, 0)
                            + greatest(0, extract(epoch from (now() - v_gerk.start_time))::int),
               completed = true
         where id = v_gerk.id
        returning * into v_gerk;
    else
        -- stopped -> start/resume a new session; accumulated duration untouched
        update public.work_log_gerks
           set start_time = now(),
               end_time   = null,
               completed  = false
         where id = v_gerk.id
        returning * into v_gerk;
    end if;

    update public.work_logs
       set work_duration = coalesce((
               select round(sum(g.duration) / 60.0)
                 from public.work_log_gerks g
                where g.work_log_id = v_log_id
           ), 0)
     where id = v_log_id;

    return query
        select v_log_id, v_gerk.id, v_gerk.start_time, v_gerk.end_time,
               v_gerk.duration, v_gerk.completed, wl.work_duration
          from public.work_logs wl
         where wl.id = v_log_id;
end;
$$;


-- ── 3. set_gerk_duration — manual hh:mm:ss entry for one field ──
-- No longer gated behind "must have used the timer first" — this is
-- now the deliberate way to type a duration directly (forgotten-phone
-- case) or to correct/redo a value the timer got wrong. If the field
-- happens to be mid-session when this is called, that session is
-- closed out (end_time set) rather than left running underneath a
-- manually-fixed total.
create or replace function public.set_gerk_duration(
    p_work_order_id uuid,
    p_gerk_code     text,
    p_seconds       integer,
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
    v_seconds  integer := greatest(0, coalesce(p_seconds, 0));
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
       set duration  = v_seconds,
           completed = (v_seconds > 0),
           end_time  = case when start_time is not null and end_time is null
                            then now() else end_time end
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


-- ── 4. Grants ─────────────────────────────────────────────────
-- Supabase grants EXECUTE directly to anon/authenticated/service_role
-- on new functions (not via PUBLIC) — revoking from PUBLIC alone is a
-- no-op here. Must revoke from anon by name. (Same mistake bitten this
-- project twice before: create_operator et al., then start_work_order.)
revoke execute on function public.toggle_gerk_timer(uuid, text, date) from public, anon;
revoke execute on function public.set_gerk_duration(uuid, text, integer, date) from public, anon;

grant execute on function public.toggle_gerk_timer(uuid, text, date) to authenticated;
grant execute on function public.set_gerk_duration(uuid, text, integer, date) to authenticated;
