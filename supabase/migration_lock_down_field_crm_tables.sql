-- ============================================================
-- WorkTracker — Close the anon_all hole on FIELD / B_FIELD_X_CUSTOMER
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================
--
-- Same class of issue as migration_fix_public_all_policies.sql, on
-- the CRM's own tables this time: FIELD and B_FIELD_X_CUSTOMER both
-- carry an "anon_all" policy (FOR ALL TO anon USING (true)) — any
-- unauthenticated request with just the published anon key can
-- select/insert/update/delete rows in either table.
--
-- Not dropping either table (see conversation) — FIELD_ID is still
-- referenced by convention (no enforced FKs anywhere in this schema)
-- from B_FIELD_X_FIELD_SEGMENT and FIELD_SEGMENT, and there's no way
-- to confirm nothing outside this repo still reads FIELD directly.
-- WorkTracker's own code no longer reads either table at all
-- (loadFields() was repointed to WorkTracker's own fields/customers,
-- and the 371 rows FIELD had that fields didn't have have already
-- been imported — see migration_import_field_only_rows.sql), so both
-- can simply be locked down as dormant data instead.
--
-- FIELD keeps its existing "authenticated_read" policy — harmless,
-- logged-in-only, left in place in case it's ever useful again.
-- B_FIELD_X_CUSTOMER had no other policy besides anon_all, so it ends
-- up fully locked (RLS enabled, zero policies — only postgres/
-- service_role can touch it), same end state as orders/reports.

drop policy if exists "anon_all" on public."FIELD";
drop policy if exists "anon_all" on public."B_FIELD_X_CUSTOMER";
