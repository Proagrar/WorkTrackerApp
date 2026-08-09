-- ============================================================
-- WorkTracker — Prevent duplicate segment numbers within a GERK
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================
--
-- The "+ Dodaj segment" button computes the next sample_no client-side
-- (highest existing + 1), but nothing in the database actually
-- enforced it stayed unique — two rapid clicks, or two admins working
-- the same GERK at once, could produce two segments with the same
-- number. Verified no existing duplicates before adding this (clean).

alter table public.delovni_nalogi_vzorci
    add constraint uq_delovni_nalogi_vzorci_gerk_sample unique (delovni_nalog_gerk_id, sample_no);
