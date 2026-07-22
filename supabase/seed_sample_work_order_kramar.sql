-- ============================================================
-- Sample work order — Jure Kramar (from Excel import sample)
-- Requires migration_work_order_details.sql to be applied first
-- (podrobnosti + lokacija columns). Run in Supabase SQL Editor.
-- ============================================================

do $$
declare
    wo_id uuid;
begin
    insert into public.delovni_nalogi (stevilka, stranka_id, tip_storitve, status, podrobnosti)
    values (
        'DN-002',
        '2c2d4e25-b8f7-449c-a419-84985974acb3', -- Jure Kramar
        'Vzorčenje',
        'Plan',
        'Sampling depth: 25 cm'
    )
    returning id into wo_id;

    insert into public.delovni_nalogi_gerki (delovni_nalog_id, gerk_code, kolicina_ha, lokacija)
    values
        (wo_id, '4086091', 0.28,   '45 52 5.79, 15 16 24.38'),
        (wo_id, '4086060', 0.47,   null),
        (wo_id, '4086129', 0.2,    null),
        (wo_id, '4086025', 1.4,    null),
        (wo_id, '1623774', 3.1245, null),
        (wo_id, '1623775', 2.4512, null),
        (wo_id, '3649122', 2.1194, null),
        (wo_id, '1623778', 1.2028, null),
        (wo_id, '633371',  3.63,   null),
        (wo_id, '6082959', 3.13,   null),
        (wo_id, '350389',  2.56,   null),
        (wo_id, '378023',  0.9,    null),
        (wo_id, '350023',  0.87,   null),
        (wo_id, '4722077', 0.27,   null),
        (wo_id, '1665691', 2.16,   null),
        (wo_id, '127943',  0.86,   null),
        (wo_id, '3623028', 0.54,   null),
        (wo_id, '4592395', 0.49,   null),
        (wo_id, '3616093', 0.48,   null),
        (wo_id, '4883101', 0.26,   null);
end $$;
