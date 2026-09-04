-- ============================================================
-- WorkTracker — Allow admins to add new customers
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================
--
-- customers only had a SELECT policy ("Authenticated users can view
-- customers") — no INSERT policy at all, so RLS silently blocked
-- everyone, including admins, from creating one. Scoped to INSERT
-- only (not UPDATE/DELETE) since customers is shared with the CRM app,
-- which manages the fuller record (billing, VAT, sales_person, etc.)
-- — WorkTracker's own need here is just "let an admin add one on the
-- fly when the CRM hasn't caught up yet", not manage existing rows.

create policy "Admins can insert customers" on public.customers
    for insert to authenticated
    with check (exists (
        select 1 from public.profiles where id = auth.uid() and role = 'admin'
    ));
