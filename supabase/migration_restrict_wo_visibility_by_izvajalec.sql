-- ============================================================
-- WorkTracker — Restrict work-order visibility for izvajalci (operators)
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================
--
-- Previously "Authenticated users can view all work orders" (qual: true)
-- let every logged-in user see every work order regardless of role.
-- Operators should only see work orders assigned to them, or not yet
-- assigned to anyone — not every other operator's job. Admins and
-- supervisors keep full visibility (matches their broader access
-- elsewhere in the app, e.g. Evidenca dela).

drop policy "Authenticated users can view all work orders" on public.delovni_nalogi;

create policy "Operators see their own or unassigned work orders" on public.delovni_nalogi
    for select to authenticated
    using (
        exists (
            select 1 from public.profiles
            where id = auth.uid() and role in ('admin', 'supervisor')
        )
        or izvajalec = auth.uid()
        or izvajalec is null
    );
