-- ============================================================
-- WorkTracker — auto-set status to Izvedeno once every field on a
-- work order has a completed time log
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================
--
-- Pairs with migration_one_time_log_per_gerk.sql's "locked once
-- logged" rule: once every planned GERK on a work order has a
-- completed start/end entry (by anyone, any date — same "any entry
-- counts" rule as the frontend lock), the order auto-advances from
-- Plan/V delu to Izvedeno. Only advances forward — clearing a field's
-- logged time afterward does NOT auto-revert the status; that stays a
-- manual admin decision via the status dropdown, same as today.
--
-- SECURITY DEFINER because a regular operator finishing the last
-- field of an order has no UPDATE grant on delovni_nalogi.status
-- themselves (admin-only via RLS) — the trigger needs to act with
-- elevated privilege to make that status change on their behalf.

create or replace function public.check_work_order_auto_complete()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
#variable_conflict use_column
declare
    v_work_order_id uuid;
    v_total  integer;
    v_done   integer;
    v_status text;
begin
    select wl.work_order_id into v_work_order_id
      from public.work_logs wl
     where wl.id = coalesce(new.work_log_id, old.work_log_id);

    if v_work_order_id is null then
        return coalesce(new, old);
    end if;

    select status into v_status from public.delovni_nalogi where id = v_work_order_id;
    if v_status is null or v_status not in ('Plan', 'V delu') then
        return coalesce(new, old);
    end if;

    select count(*) into v_total
      from public.delovni_nalogi_gerki
     where delovni_nalog_id = v_work_order_id;

    if v_total = 0 then
        return coalesce(new, old);
    end if;

    select count(distinct g.gerk_code) into v_done
      from public.work_log_gerks g
      join public.work_logs wl on wl.id = g.work_log_id
      join public.delovni_nalogi_gerki pf
        on pf.delovni_nalog_id = wl.work_order_id and pf.gerk_code = g.gerk_code
     where wl.work_order_id = v_work_order_id
       and g.completed = true;

    if v_done >= v_total then
        update public.delovni_nalogi set status = 'Izvedeno' where id = v_work_order_id;
    end if;

    return coalesce(new, old);
end;
$$;

drop trigger if exists trg_check_work_order_auto_complete on public.work_log_gerks;
create trigger trg_check_work_order_auto_complete
after insert or update on public.work_log_gerks
for each row
execute function public.check_work_order_auto_complete();

-- One-time backfill: any order that's already fully logged right now
-- (like #54) but never got marked Izvedeno because this trigger didn't
-- exist yet when its last field was completed.
update public.delovni_nalogi dn
   set status = 'Izvedeno'
 where dn.status in ('Plan', 'V delu')
   and exists (select 1 from public.delovni_nalogi_gerki pf where pf.delovni_nalog_id = dn.id)
   and not exists (
       select 1
         from public.delovni_nalogi_gerki pf
        where pf.delovni_nalog_id = dn.id
          and not exists (
              select 1
                from public.work_log_gerks g
                join public.work_logs wl on wl.id = g.work_log_id
               where wl.work_order_id = dn.id
                 and g.gerk_code = pf.gerk_code
                 and g.completed = true
          )
   );
