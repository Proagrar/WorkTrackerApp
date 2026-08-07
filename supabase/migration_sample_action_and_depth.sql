-- ============================================================
-- WorkTracker — Editable sample action + sampling depth
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================
--
-- Formalizes what used to only be loose free-text in sampling_note
-- (things like "ne pobereš"/"združi" turned up as literal instruction
-- text during the original historical import) into a real dropdown
-- field, plus adds sampling depth as a separate structured field.
--
-- No RLS changes needed — "Admins can manage samples" already grants
-- ALL (including UPDATE) on this table to admins, and the existing
-- "Authenticated users can view samples of open work orders" SELECT
-- policy already covers reading these two new columns too.

alter table public.delovni_nalogi_vzorci
    add column if not exists action text
        check (action is null or action in ('ne pobereš', 'združi_1', 'združi_2', 'združi_3', 'združi_4', 'združi_5')),
    add column if not exists sampling_depth_cm integer
        check (sampling_depth_cm is null or sampling_depth_cm in (12, 20, 25, 30, 60, 90));
