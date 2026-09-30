-- "Luka Boltiš" is actually two separate legal entities sharing a name:
--   - Slovenian entity: customers.id = 3b892d7e-9a1f-4678-868c-11f3c334c70f
--     (country already correctly "Slovenia")
--   - Croatian entity:  customers.id = 0a73a52a-05cf-445d-a89a-4249d9ae846e
--     (currently named "Boltiš L", country already correctly "Hrvatska",
--     has one prior order, #27, already completed/archived)
--
-- Order #99 (under the Slovenian entity) has 32 GERK lines; 5 of them
-- (1689101, 1689660, 1691729, 2580633, 3619201) are genuinely Croatian
-- parcels and need to belong to the Croatian entity instead. Checked: none
-- of the 5 have any work_log_gerks, delovni_nalogi_planiranje_gerki, or
-- gerk_captured_point rows yet, so this is a clean move — no historical
-- data needs to move with them.
--
-- 1. Rename both entities for clarity (they share a name in the UI today).
update customers
   set naziv = 'Luka Boltiš - HR', company_name = 'Luka Boltiš - HR'
 where id = '0a73a52a-05cf-445d-a89a-4249d9ae846e';

update customers
   set naziv = 'Luka Boltiš - SLO', company_name = 'Luka Boltiš - SLO'
 where id = '3b892d7e-9a1f-4678-868c-11f3c334c70f';

-- 2. Create a new order under the Croatian entity (stevilka auto-assigns
-- from delovni_nalogi_stevilka_seq, same as the app's own "+ Nov delovni
-- nalog" — not hardcoded here) and move the 5 Croatian GERK lines onto it
-- in the same statement, so there's no window where they'd be orphaned.
with new_order as (
  insert into delovni_nalogi (stranka_id, tip_storitve, status, confirmed)
  values ('0a73a52a-05cf-445d-a89a-4249d9ae846e', 'Vzorčenje', 'Plan', false)
  returning id
)
update delovni_nalogi_gerki
   set delovni_nalog_id = (select id from new_order)
 where id in (
   '9e7b171b-ea3d-477e-85a4-5514688a5c53', -- 1689101
   '4dbc4680-79ab-4c83-91a7-4b0fce19678b', -- 1689660
   'e0a7566f-c244-4d31-b1fb-cdaa60561513', -- 1691729
   'ccc429f0-a618-4775-9b20-3f7ad94015c5', -- 2580633
   '1785a464-9646-4065-b39a-8cd8ce5f0c13'  -- 3619201
 );

-- 3. Verify: new order should show under "Luka Boltiš - HR" with exactly
-- these 5 GERK codes; order #99 should now have 27 lines left, all
-- belonging to "Luka Boltiš - SLO".
select dn.stevilka, cu.naziv, dng.gerk_code
  from delovni_nalogi_gerki dng
  join delovni_nalogi dn on dn.id = dng.delovni_nalog_id
  join customers cu on cu.id = dn.stranka_id
 where dn.stranka_id in ('0a73a52a-05cf-445d-a89a-4249d9ae846e', '3b892d7e-9a1f-4678-868c-11f3c334c70f')
 order by cu.naziv, dng.gerk_code;
