-- ============================================================
-- WorkTracker — Move a work log to a different date
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================
--
-- work_logs is one row per (operator, work_order, day). Changing the
-- date picker in the work-order detail modal used to just re-fetch a
-- *different* day's row, leaving whatever hours were already entered
-- under the old date sitting untouched but invisible — looked like
-- they'd been erased (switching the date back made them "reappear").
--
-- This RPC actually moves the in-progress log to the new date instead,
-- merging into that day's log if one already exists there (same
-- find-or-create pattern as set_gerk_times, which already solves this
-- for a single GERK's date field — this is the equivalent for the
-- whole log: all GERK rows, road time, tractor, description).
--
-- security definer: work_log_road_time has no UPDATE RLS policy for
-- operators (only insert/delete/view), so reparenting its rows needs
-- to bypass RLS the same way start_gerk/end_gerk/set_gerk_times/
-- add_road_time already do — every query is explicitly scoped to
-- auth.uid() to compensate.

create or replace function public.move_work_log_date(
    p_work_order_id uuid,
    p_old_date       date,
    p_new_date       date
)
returns table (log_id uuid)
language plpgsql
security definer
set search_path = public
as $$
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

revoke execute on function public.move_work_log_date(uuid, date, date) from public, anon;
grant execute on function public.move_work_log_date(uuid, date, date) to authenticated;
