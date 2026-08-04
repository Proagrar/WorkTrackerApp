-- ============================================================
-- WorkTracker — Sampling/sending notes on delovni_nalogi_vzorci
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- Run BEFORE update_vzorci_notes.sql
-- ============================================================
--
-- The source Excel "Datum vzorčenja" / "Datum pošiljanja" columns are not
-- reliably dates — they're also used for handling instructions ("ne pobereš",
-- "združi"), crop names, and field-boundary notes ("parcela je večja"). These
-- columns hold that raw text verbatim, separate from the (best-effort, only
-- when unambiguous) parsed sampling_date/sending_date.

alter table public.delovni_nalogi_vzorci
    add column if not exists sampling_note text,
    add column if not exists sending_note  text;
