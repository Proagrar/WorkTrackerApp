-- ============================================================
-- WorkTracker — Shorten delovni_nalogi.stevilka to a bare number
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================

-- Was 'DN-' || lpad(nextval(...), 3, '0') (e.g. "DN-001") - too wide for
-- the now-narrow Št. column. New default is just the bare sequence value
-- as text (e.g. "1", "2", "3"). Existing rows (DN-LEGACY, DN-002) are
-- left untouched - DN-LEGACY's literal value is referenced by name in
-- other migrations/RLS, and DN-002 is real sample data, not a template
-- for the new format.
alter table public.delovni_nalogi
    alter column stevilka set default (nextval('public.delovni_nalogi_stevilka_seq')::text);
