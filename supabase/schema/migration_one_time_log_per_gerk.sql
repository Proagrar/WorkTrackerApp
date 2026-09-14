-- ============================================================
-- WorkTracker — enforce "only one start/end time log per field"
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================
--
-- start_gerk and end_gerk always unconditionally overwrote
-- start_time/end_time/duration/completed, with no check for whether
-- the field already had a value — clicking Start again after a field
-- was already logged (by anyone, on any date) silently wiped the
-- recorded time, and clicking Konec again after already finishing
-- silently changed the end time. The frontend now disables those
-- buttons once a field is locked, but that's just UX — these
-- server-side guards are the actual enforcement, so a stale page or a
-- second tab can't do it either.
--
-- set_gerk_times (used by the ✎ edit panel) gets one addition: when
-- an admin submits an edit with both times blank, that's "remove the
-- time that was logged" — the escape hatch for the lock above. It now
-- deletes whichever entry actually exists for that field, regardless
-- of which operator/date it belongs to (previously it would only ever
-- touch the caller's own row, so an admin trying to clear someone
-- else's logged time just silently created an empty row under their
-- own name instead, leaving the original untouched). Non-admin
-- behavior (clearing/editing your own entry) is unchanged.

create or replace function public.start_gerk(p_work_order_id uuid, p_gerk_code text, p_work_date date default current_date)
 returns table(log_id uuid, gerk_id uuid, start_time timestamp with time zone, end_time timestamp with time zone, duration integer, completed boolean, work_duration integer)
 language plpgsql
 set search_path to 'public'
as $function$
#variable_conflict use_column
declare
    v_log_id   uuid;
    v_hectares numeric;
begin
    if auth.uid() is null then
        raise exception 'Not authenticated';
    end if;

    if exists (
        select 1
          from public.work_log_gerks g
          join public.work_logs wl on wl.id = g.work_log_id
         where wl.work_order_id = p_work_order_id
           and g.gerk_code = p_gerk_code
           and g.start_time is not null
    ) then
        raise exception 'Za ta GERK je čas že vpisan.';
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
$function$;

create or replace function public.end_gerk(p_work_order_id uuid, p_gerk_code text, p_work_date date default current_date)
 returns table(log_id uuid, gerk_id uuid, start_time timestamp with time zone, end_time timestamp with time zone, duration integer, completed boolean, work_duration integer)
 language plpgsql
 set search_path to 'public'
as $function$
#variable_conflict use_column
declare
    v_log_id     uuid;
    v_start_time timestamptz;
    v_completed  boolean;
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

    select g.start_time, g.completed into v_start_time, v_completed
      from public.work_log_gerks g
     where g.work_log_id = v_log_id and g.gerk_code = p_gerk_code;

    if v_start_time is null then
        raise exception 'Najprej pritisnite Start';
    end if;

    if v_completed then
        raise exception 'Za ta GERK je čas že zaključen.';
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
$function$;

create or replace function public.set_gerk_times(p_work_order_id uuid, p_gerk_code text, p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_work_date date default current_date, p_previous_work_date date default null::date)
 returns table(log_id uuid, gerk_id uuid, start_time timestamp with time zone, end_time timestamp with time zone, duration integer, completed boolean, work_duration integer)
 language plpgsql
 set search_path to 'public'
as $function$
#variable_conflict use_column
declare
    v_log_id       uuid;
    v_old_log_id   uuid;
    v_hectares     numeric;
    v_duration     integer;
    v_is_admin     boolean;
    v_clear_log_id uuid;
begin
    if auth.uid() is null then
        raise exception 'Not authenticated';
    end if;

    if p_start_time is not null and p_end_time is not null and p_end_time < p_start_time then
        raise exception 'Konec ne more biti pred začetkom';
    end if;

    select exists(select 1 from public.profiles where id = auth.uid() and role = 'admin') into v_is_admin;

    -- Admin clearing a field (both times blank in the edit panel) is
    -- the escape hatch for the one-time-log-per-field lock — it has to
    -- be able to remove whichever entry actually exists, not just the
    -- admin's own (which usually doesn't exist at all).
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
$function$;
