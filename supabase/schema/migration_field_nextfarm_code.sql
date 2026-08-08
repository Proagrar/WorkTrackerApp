-- ============================================================
-- WorkTracker — NextFarm GERK code on fields (MUST requirement)
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================
--
-- On WorkTracker's own fields table (the consolidated source of
-- truth, not the CRM's FIELD) — schema only for now, no UI yet, same
-- as customers.region. No data source for this identified yet either
-- (manual entry vs. a future NextFarm export/import is still open).

alter table public.fields add column if not exists sifra_gerka_nextfarm text;
