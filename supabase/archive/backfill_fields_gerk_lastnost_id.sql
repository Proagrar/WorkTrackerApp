-- ============================================================
-- WorkTracker — Backfill fields.gerk_lastnost_id
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- Run AFTER migration_fields_gerk_lastnost_fk.sql
-- ============================================================
--
-- One-time backfill. gerk_id is globally unique (not customer-scoped
-- like the field_id backfill was), so this is a direct cast + exists
-- check rather than a join. Safe to re-run later (only fills
-- currently-null gerk_lastnost_id).

update public.fields f
   set gerk_lastnost_id = f.cadastre_id::int
 where f.cadastre_id ~ '^[0-9]+$'
   and f.gerk_lastnost_id is null
   and exists (select 1 from public.gerk_lastnost gl where gl.gerk_id = f.cadastre_id::int);
