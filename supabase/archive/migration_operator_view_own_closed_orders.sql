-- ============================================================
-- WorkTracker — Operators can see their own work orders regardless
-- of status (not just Plan/V delu)
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================
--
-- delovni_nalogi's only non-admin SELECT policy was scoped to
-- status in (Plan, V delu) — the moment an order moved to Izvedeno
-- or Izdan Račun, it vanished from the app entirely for anyone but
-- an admin, even the operator who did the work and logged hours
-- against it. Reported directly: Blaz Sinur couldn't see work orders
-- 21–33 (all Izvedeno) despite 34 (V delu, assigned to him) and 20
-- (Plan) showing up fine.
--
-- Adds a second, permissive SELECT policy (Postgres OR's multiple
-- permissive policies together, so the existing "open work orders"
-- policy is untouched) covering: the order's assigned izvajalec, or
-- anyone who has logged time against it — regardless of status. No
-- app.js change needed; the work-order list query has no client-side
-- status filter, so whatever RLS now allows through just shows up.

create policy "Operators can view own work orders regardless of status"
    on public.delovni_nalogi for select
    to authenticated
    using (
        izvajalec = auth.uid()
        or exists (
            select 1 from public.work_logs wl
             where wl.work_order_id = delovni_nalogi.id
               and wl.operator_id = auth.uid()
        )
    );
