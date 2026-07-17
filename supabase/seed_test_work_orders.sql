-- ============================================================
-- Test seed data — delovni_nalogi (Work Orders)
-- Run AFTER migration_work_orders.sql, in Supabase SQL Editor
-- Safe to delete afterward: delete from public.delovni_nalogi
--   where stevilka like 'DN-TEST-%';
-- ============================================================

insert into public.delovni_nalogi
    (stevilka, stranka_id, izvajalec, kolicina_ha, tip_storitve, strosek_ocena, strosek, status)
values
    ('DN-TEST-001', null, null, 12.50, 'Gnojenje',    450.00, null,   'Plan'),
    ('DN-TEST-002', null, null,  8.00, 'Škropljenje', 200.00, 180.00, 'V delu');
