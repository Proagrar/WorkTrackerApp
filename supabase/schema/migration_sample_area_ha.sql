-- ============================================================
-- WorkTracker — Segment area (velikost ha) on samples
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================
--
-- Last missing piece of the segment MUST list that delovni_nalogi_vzorci
-- doesn't already cover (sample_no, sampling_note-as-action,
-- sampling_depth_cm). No RLS change needed — "Admins can manage
-- samples" already grants INSERT/UPDATE, which is what the new
-- "+ Dodaj segment" button and this column both need.

alter table public.delovni_nalogi_vzorci
    add column if not exists area_ha numeric;
