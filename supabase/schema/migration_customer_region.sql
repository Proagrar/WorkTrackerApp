-- ============================================================
-- WorkTracker — Customer region (kraj/regija MUST requirement)
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================
--
-- "kraj" reuses the existing customers.address_city rather than
-- adding a duplicate column — same mistake already made once this
-- session with a standalone "action" column that duplicated
-- sampling_note; not repeating it here.
--
-- "regija" is new: fixed list of Slovenia's 12 SURS statistical
-- regions, plus a single 'Croatia' value for Croatian customers
-- (no need for Croatian county-level granularity per requirement).

alter table public.customers
    add column if not exists region text
        check (region is null or region in (
            'Pomurska', 'Podravska', 'Koroška', 'Savinjska', 'Zasavska', 'Posavska',
            'Jugovzhodna Slovenija', 'Primorsko-notranjska', 'Osrednjeslovenska',
            'Gorenjska', 'Goriška', 'Obalno-kraška', 'Croatia'
        ));
