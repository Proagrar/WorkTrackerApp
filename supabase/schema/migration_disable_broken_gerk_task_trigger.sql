-- ============================================================
-- WorkTracker — Disable broken CRM sync trigger blocking GERK saves
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- URGENT: this is actively blocking every work-order/GERK save right now.
-- ============================================================
--
-- trg_insert_gerk_task_from_delovni_nalog fires on every INSERT into
-- delovni_nalogi_gerki (WorkTracker's own table) and calls
-- insert_gerk_task_from_delovni_nalog(), which is broken on BOTH ends:
--
--   1. Reads NEW.gerk_id — delovni_nalogi_gerki has no such column,
--      only gerk_code (text). This is what actually fails first:
--      "record \"new\" has no field \"gerk_id\"".
--   2. Even if #1 were fixed, its own INSERT into gerk_task references
--      gerk_task.delovni_nalog_id — but that column is actually named
--      delovni_nalog_uuid. Confirmed via information_schema on both
--      tables, live, 2026-09-03.
--
-- This means the CRM↔WorkTracker gerk_task sync this trigger was meant
-- to provide cannot have been working since gerk_task was last
-- restructured — it isn't a working integration being turned off, it's
-- dead code that happens to still be attached and firing. Not
-- rewritten here since the correct gerk_id/status/part_number mapping
-- is CRM-side business logic outside WorkTracker's own migrations —
-- disabling (not dropping) so it's fully recoverable once someone
-- who owns that mapping fixes it properly.

alter table public.delovni_nalogi_gerki
    disable trigger trg_insert_gerk_task_from_delovni_nalog;
