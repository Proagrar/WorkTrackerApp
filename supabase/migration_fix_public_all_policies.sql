-- ============================================================
-- WorkTracker — Close an unrestricted anon read/write/delete hole
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================
--
-- Found while investigating the fields/FIELD merge, unrelated to it:
-- customers, fields, orders, and reports each carry a policy named
-- "service role full access on X" that is actually
--     FOR ALL TO public USING (true)
-- "public" in Postgres RLS means literally every role — anon included
-- — so right now any unauthenticated request with just the published
-- anon key can select/insert/update/DELETE rows in all four tables,
-- including customers (email, phone, address, VAT number).
--
-- This was never needed for its stated purpose: Supabase's
-- service_role bypasses RLS entirely on its own, so a permissive
-- policy grants it nothing. And nothing in this app writes to any of
-- these four tables at all (verified: no .insert/.update/.delete
-- calls anywhere in app.js against customers/fields/orders/reports),
-- so dropping the write access breaks nothing live.
--
-- Reads: customers already has a proper "authenticated" SELECT
-- policy, so it's unaffected. fields does NOT — it was silently
-- riding on the broken public-ALL policy for authenticated reads
-- (loadFields, the Deklaracije review table), so this adds the
-- missing dedicated policy alongside the cleanup, or those would
-- break the moment the bad policy is dropped.
--
-- orders/reports: confirmed unused anywhere in app.js. Left with RLS
-- enabled and zero policies afterward, i.e. fully locked down (only
-- postgres/service_role can touch them) — matches their "not
-- WorkTracker's concern" status from the earlier schema audit.
--
-- anon SELECT is also dropped on all four: the only anon-facing
-- feature (the public field-declaration form, deklaracija.js) goes
-- entirely through SECURITY DEFINER RPCs (get_field_declaration_form /
-- submit_field_declarations), never direct table reads — so anon
-- doesn't need row access to any of these tables either.

drop policy if exists "service role full access on customers" on public.customers;
drop policy if exists "service role full access on fields"    on public.fields;
drop policy if exists "service role full access on orders"    on public.orders;
drop policy if exists "service role full access on reports"   on public.reports;

drop policy if exists "anon can read customers" on public.customers;
drop policy if exists "anon can read fields"     on public.fields;
drop policy if exists "anon can read orders"     on public.orders;
drop policy if exists "anon can read reports"    on public.reports;

create policy "Authenticated users can view fields"
    on public.fields for select
    to authenticated
    using (true);
