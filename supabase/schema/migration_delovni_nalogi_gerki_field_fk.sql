-- ============================================================
-- WorkTracker — Real FK: delovni_nalogi_gerki → fields
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================
--
-- gerk_code has always been plain text — matched against fields at
-- render time in app.js, never enforced by the database. Verified
-- before adding this: matching on (customer + cadastre_id) resolves
-- 100% of existing rows (366/366), so this is safe to add as a real
-- constraint, not just a soft join.
--
-- gerk_code stays — it's still the record of what was actually
-- entered, and new GERK codes not yet in `fields` are a real,
-- supported case in the create-work-order form (see app.js: any
-- 7-digit code is accepted even if unknown). field_id is nullable for
-- exactly that reason — a code with no matching field row yet.

alter table public.delovni_nalogi_gerki
    add column if not exists field_id uuid references public.fields(id);

create index if not exists idx_delovni_nalogi_gerki_field_id on public.delovni_nalogi_gerki (field_id);
