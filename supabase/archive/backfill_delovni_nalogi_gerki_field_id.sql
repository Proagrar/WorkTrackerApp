-- ============================================================
-- WorkTracker — Backfill delovni_nalogi_gerki.field_id
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- Run AFTER migration_delovni_nalogi_gerki_field_fk.sql
-- ============================================================
--
-- One-time backfill, matched by (customer + cadastre_id) — verified
-- 100% match rate (366/366) beforehand. Safe to re-run later (only
-- fills currently-null field_id) if it's ever needed again.

update public.delovni_nalogi_gerki dng
   set field_id = f.id
  from public.fields f, public.delovni_nalogi dn
 where dn.id = dng.delovni_nalog_id
   and f.customer_id = dn.stranka_id
   and f.cadastre_id = dng.gerk_code
   and dng.field_id is null;
