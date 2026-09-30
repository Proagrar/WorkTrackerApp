-- Order #99 is now under "Luka Boltiš - HR" (fix_luka_boltis_all_hr.sql),
-- making order #101 — created earlier to hold 5 of its GERK lines under
-- the Croatian entity — redundant duplication under the same customer.
-- Merge its 5 lines back into #99 and remove #101. Checked: #101 still has
-- no work_log_gerks or delovni_nalogi_planiranje rows, so this is a clean
-- move with nothing else to carry over.

update delovni_nalogi_gerki
   set delovni_nalog_id = '8c66f0bb-e110-462e-8288-388939b5a8c7' -- order #99
 where delovni_nalog_id = 'b3d1627f-b5b6-46ce-8525-9118c73aaa2b'; -- order #101

delete from delovni_nalogi
 where id = 'b3d1627f-b5b6-46ce-8525-9118c73aaa2b'; -- order #101, now empty

-- Verify: order #99 should have 32 GERK lines again, all under
-- "Luka Boltiš - HR", and #101 should no longer exist.
select dn.stevilka, count(dng.id) as gerk_count
  from delovni_nalogi dn
  left join delovni_nalogi_gerki dng on dng.delovni_nalog_id = dn.id
 where dn.stranka_id = '0a73a52a-05cf-445d-a89a-4249d9ae846e'
 group by dn.stevilka
 order by dn.stevilka::int;
