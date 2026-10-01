-- One-time catch-up for GERK lines that match the official registry
-- (plain code or compound "A+B+C") but were never linked through
-- fields/field_id, so kolicina_ha stayed null. Confirmed: 9 of the 18
-- lines still null after migration_backfill_ha_from_kml.sql resolve
-- this way (orders #12, #26, #73); the remaining 9 (orders #50, #51,
-- #57) genuinely have no registry match either and are left alone.
-- Country-aware (SI/HR) via each order's customer, same as
-- get_work_order_gerk_shapes. The new insert trigger
-- (migration_gerk_ha_insert_trigger.sql) prevents this gap for every
-- future GERK add -- this migration only covers what already exists.

with targets as (
  select dng.id, dng.gerk_code,
         case when upper(trim(cu.country)) in ('HRVAŠKA','HRVATSKA') then 'HR' else 'SI' end as drzava
    from delovni_nalogi_gerki dng
    join delovni_nalogi dn on dn.id = dng.delovni_nalog_id
    left join customers cu on cu.id = dn.stranka_id
   where dng.kolicina_ha is null
),
split_targets as (
  select t.id, t.drzava, trim(part) as sub_code
    from targets t, unnest(string_to_array(t.gerk_code, '+')) as part
),
numeric_targets as (
  select id, drzava, sub_code::int as gerk_int
    from split_targets
   where sub_code ~ '^[0-9]+$'
),
resolved as (
  select nt.id, sum(ST_Area(coalesce(gpo.polygon_points, gp.polygon_points)::geography)/10000) as total_ha
    from numeric_targets nt
    left join gerk_polygon_ours gpo on gpo.gerk_id = nt.gerk_int
    left join gerk_polygon gp on gp.gerk_id = nt.gerk_int and gp.drzava = nt.drzava
   group by nt.id
  having sum(ST_Area(coalesce(gpo.polygon_points, gp.polygon_points)::geography)/10000) > 0
)
update delovni_nalogi_gerki dng
   set kolicina_ha = resolved.total_ha
  from resolved
 where dng.id = resolved.id;

-- Verify: should now only list orders #50, #51, #57 (and any other
-- GERK that genuinely matches neither KML segmentation nor the registry).
select dn.stevilka, dng.gerk_code
  from delovni_nalogi_gerki dng
  join delovni_nalogi dn on dn.id = dng.delovni_nalog_id
 where dng.kolicina_ha is null
 order by dn.stevilka::int;
