-- ============================================================
-- WorkTracker — Drop delovni_nalogi_vzorci.action, unused
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================
--
-- Wrong field: the "action" concept (ne pobereš / združi) already
-- lives in sampling_note — that's where "ne pobereš" already appears
-- 251 times from the original import. This column was created fresh
-- and empty, duplicating a concept that already had real data
-- elsewhere. The UI now edits sampling_note directly instead (see
-- app.js renderSamplingCell) — no schema constraint needed there,
-- since sampling_note has to stay free text for the ~258 rows that
-- hold raw date fragments / other notes the dropdown can't represent.

alter table public.delovni_nalogi_vzorci drop column if exists action;
