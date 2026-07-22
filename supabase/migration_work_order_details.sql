-- ============================================================
-- WorkTracker — Work order details: podrobnosti + per-field lokacija
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================

-- Order-level generic free-text details (e.g. "Sampling depth: 25 cm"
-- for Vzorcenje orders, or any other service-type-specific note) —
-- deliberately generic rather than a dedicated column per service type.
alter table public.delovni_nalogi
    add column if not exists podrobnosti text;

-- Per-field GPS/location (e.g. "46 33 29.31, 16 2 38.54") — fields
-- within the same order can be in different locations.
alter table public.delovni_nalogi_gerki
    add column if not exists lokacija text;
