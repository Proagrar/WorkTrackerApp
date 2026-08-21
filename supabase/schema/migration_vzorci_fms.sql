-- ============================================================
-- WorkTracker — FMS field on segments (delovni_nalogi_vzorci)
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================
--
-- New per-segment code from the lab's own paste format (column header
-- "FMS" in their Excel export). Stored as text, same as sample_no —
-- there's no guarantee it stays purely numeric long-term, and nothing
-- here does arithmetic on it.

alter table public.delovni_nalogi_vzorci
    add column if not exists fms text;