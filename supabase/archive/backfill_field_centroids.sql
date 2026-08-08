-- ============================================================
-- WorkTracker — Backfill field centroids from GERK_POLYGON
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- Run AFTER migration_field_centroid.sql
-- ============================================================
--
-- One-time backfill, but safe to re-run later (only fills currently-
-- null centroids) if new fields get imported down the line. Matches
-- GERK_POLYGON.GERK_ID (the raw GERK code as an integer, verified
-- this session) against fields.cadastre_id — 4,710 of 5,226 current
-- fields (90%) match; the rest are suffixed codes (xxx-1/xxx-2) or
-- codes GERK_POLYGON doesn't have, and are simply left null.

update public.fields f
   set centroid_lat = ST_Y(gp."CENTER_POINT"),
       centroid_lng = ST_X(gp."CENTER_POINT")
  from public."GERK_POLYGON" gp
 where f.cadastre_id ~ '^[0-9]+$'
   and gp."GERK_ID" = f.cadastre_id::int
   and f.centroid_lat is null;
