-- ============================================================
-- WorkTracker — Mark the CRM's unused tables for future deletion
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================
--
-- Purely cosmetic/organizational — no data changes, no access changes.
-- Prefixes every CRM table that WorkTracker doesn't use with zzz_old_
-- so they sort to the bottom of any alphabetical table list (Supabase
-- Studio, \dt, information_schema queries) and read as clearly
-- deprecated. zzz_ (not the more common _old_) specifically because a
-- leading underscore sorts BEFORE letters in most listings — the
-- opposite of what "push to the end" needs.
--
-- Verified safe beforehand: no views and no triggers reference any of
-- these tables, and none of them carry real FK constraints (this CRM
-- schema never declared any), so nothing else in the database can
-- break from the rename. Postgres tracks tables by internal OID, not
-- name, so each table's own RLS policies simply follow the rename.
--
-- Confirmed unreferenced anywhere in app.js/deklaracija.js/auth.js —
-- see the full-repo grep + FK audit earlier in this session.
--
-- NOT included: `orders` / `reports` (lowercase, WorkTracker's own,
-- already RLS-locked-down, but possibly an unbuilt feature rather
-- than cruft — worth a separate decision) and `spatial_ref_sys`
-- (PostGIS system table, not part of this project at all).
--
-- GERK_LASTNOST / GERK_POLYGON are also excluded from the zzz_old_
-- batch — unreferenced in this codebase, but confirmed still in use
-- elsewhere. Renamed to lowercase only, to match this project's
-- naming convention, without marking them for deletion.

alter table public."GERK_LASTNOST" rename to gerk_lastnost;
alter table public."GERK_POLYGON"  rename to gerk_polygon;

alter table public."B_FIELD_X_CUSTOMER"          rename to "zzz_old_B_FIELD_X_CUSTOMER";
alter table public."B_FIELD_X_FIELD_SEGMENT"      rename to "zzz_old_B_FIELD_X_FIELD_SEGMENT";
alter table public."B_ORDER_X_PRODUCT"            rename to "zzz_old_B_ORDER_X_PRODUCT";
alter table public."B_PRODUCT_X_PRODUCT"          rename to "zzz_old_B_PRODUCT_X_PRODUCT";
alter table public."CODE"                         rename to "zzz_old_CODE";
alter table public."CONSULTING_LOG"               rename to "zzz_old_CONSULTING_LOG";
alter table public."CUSTOMER"                     rename to "zzz_old_CUSTOMER";
alter table public."FERTILIZATION_LOG"            rename to "zzz_old_FERTILIZATION_LOG";
alter table public."FERTILIZER"                   rename to "zzz_old_FERTILIZER";
alter table public."FIELD"                        rename to "zzz_old_FIELD";
alter table public."FIELD_SEGMENT"                rename to "zzz_old_FIELD_SEGMENT";
alter table public."FIELD_SEGMENT_ACTIVITY_LOG"   rename to "zzz_old_FIELD_SEGMENT_ACTIVITY_LOG";
alter table public."GERK_POLYGON_POWER_BI_EXAMPLE" rename to "zzz_old_GERK_POLYGON_POWER_BI_EXAMPLE";
alter table public."HARVEST_LOG"                  rename to "zzz_old_HARVEST_LOG";
alter table public."OPPORTUNITY"                  rename to "zzz_old_OPPORTUNITY";
alter table public."OPPORTUNITY_ACTIVITY_LOG"     rename to "zzz_old_OPPORTUNITY_ACTIVITY_LOG";
alter table public."ORDER"                        rename to "zzz_old_ORDER";
alter table public."PLANT"                        rename to "zzz_old_PLANT";
alter table public."PLANT_LOG"                    rename to "zzz_old_PLANT_LOG";
alter table public."PRODUCT"                      rename to "zzz_old_PRODUCT";
alter table public."SEEDING_LOG"                  rename to "zzz_old_SEEDING_LOG";
alter table public."SOIL_LOG"                     rename to "zzz_old_SOIL_LOG";
