-- ============================================================
-- WorkTracker — Field centroid (Google Maps link per field)
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================
--
-- Unlike the work-order center point (necessarily live — the set of
-- GERKs on an order varies), a field's location is a stable fact, so
-- this is stored directly on fields rather than computed per view.

alter table public.fields
    add column if not exists centroid_lat double precision,
    add column if not exists centroid_lng double precision;
