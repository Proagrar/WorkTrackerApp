-- ============================================================
-- WorkTracker — Per-field duration + completion on work_log_gerks
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================

-- The operator now logs time per field within a work order (not one
-- lump duration per day), so duration and completion move down to the
-- GERK level. work_logs.work_duration stays as a computed sum of these
-- for backward-compat with existing stats rendering.
alter table public.work_log_gerks
    add column if not exists duration  integer,                    -- minutes spent on this field
    add column if not exists completed boolean not null default false;
