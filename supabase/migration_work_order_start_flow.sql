-- ============================================================
-- WorkTracker — Start work order flow (claim + auto-assign)
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================

-- ── 1. start_work_order(): claim an open order ────────────────
-- Any authenticated user can press "Start" on a Plan-status order,
-- which assigns it to themselves and moves it to "V delu" — even if
-- someone else was previously assigned (whoever starts it now owns
-- it). Only touches status/izvajalec, nothing else on the order, and
-- only fires from the Plan state (idempotent no-op otherwise).
create or replace function public.start_work_order(p_work_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    update public.delovni_nalogi
    set status = 'V delu', izvajalec = auth.uid()
    where id = p_work_order_id
      and status = 'Plan';
end;
$$;

revoke all on function public.start_work_order(uuid) from public;
grant execute on function public.start_work_order(uuid) to authenticated;


-- ── 2. Visibility: any authenticated user sees all open orders ──
-- Previously operators only saw orders already assigned to them,
-- which would make unassigned/other-assigned orders unreachable to
-- "Start". Widened to a shared job-board model: anyone signed in can
-- see (and pick up) any non-completed order. Admins keep full CRUD.
drop policy if exists "Supervisors can view work orders"   on public.delovni_nalogi;
drop policy if exists "Operators can view own work orders" on public.delovni_nalogi;

create policy "Authenticated users can view open work orders"
    on public.delovni_nalogi for select
    to authenticated
    using (status in ('Plan', 'V delu'));

drop policy if exists "Supervisors can view work order fields"     on public.delovni_nalogi_gerki;
drop policy if exists "Operators can view own work order fields"   on public.delovni_nalogi_gerki;

create policy "Authenticated users can view fields of open work orders"
    on public.delovni_nalogi_gerki for select
    to authenticated
    using (
        exists (
            select 1 from public.delovni_nalogi dn
            where dn.id = delovni_nalogi_gerki.delovni_nalog_id
              and dn.status in ('Plan', 'V delu')
        )
    );
