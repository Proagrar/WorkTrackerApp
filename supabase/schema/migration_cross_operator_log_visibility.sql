-- ============================================================
-- WorkTracker — Let operators see each other's progress on a shared work order
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================
--
-- Today, "Operators can view own work logs" / "Operators can view own gerks"
-- restrict a regular operator to *only* their own work_logs/work_log_gerks
-- rows. That's correct for privacy across unrelated work, but it means two
-- operators handing off the same work order can't see each other's
-- progress — operator B opening a work order operator A already partly
-- worked has no way to know which GERKs are already done.
--
-- Work orders themselves are already visible to any authenticated operator
-- while open (see "Authenticated users can view open work orders" on
-- delovni_nalogi) — this just extends that same "visible while open"
-- boundary to the logs recorded against it. Closed work orders (Izvedeno /
-- Izdan Račun) still fall back to the existing own-logs-only policies.

create policy "Operators can view logs for open work orders"
    on public.work_logs for select
    to authenticated
    using (
        exists (
            select 1 from public.delovni_nalogi dn
             where dn.id = work_logs.work_order_id
               and dn.status = any (array['Plan', 'V delu'])
        )
    );

create policy "Operators can view gerks for open work orders"
    on public.work_log_gerks for select
    to authenticated
    using (
        exists (
            select 1
              from public.work_logs wl
              join public.delovni_nalogi dn on dn.id = wl.work_order_id
             where wl.id = work_log_gerks.work_log_id
               and dn.status = any (array['Plan', 'V delu'])
        )
    );
