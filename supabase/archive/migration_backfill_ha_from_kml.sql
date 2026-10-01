-- Retroactively backfills kolicina_ha for GERK lines whose KML
-- segmentation was already imported (real geometry, real computed area
-- sitting in gerk_segment.area_ha) but never got summed back into
-- kolicina_ha -- the live app only does this backfill at the moment of
-- import (see showWoDetailMap's KML import handler and the new-order
-- form's confirmNewKmlImport in app.js), never retroactively. The
-- v2.13 changelog entry already did this once for 21 GERKs; this
-- closes the larger backlog that's accumulated since (102 lines across
-- 13+ orders on the main screen alone, confirmed none have more than
-- one segmentation type, so summing a gerk_code's zone areas is
-- unambiguous -- no risk of double-counting the same physical parcel).
--
-- Scope: every delovni_nalogi_gerki row with kolicina_ha is null and a
-- matching gerk_segmentation, not just non-archived orders -- this is a
-- plain data-correctness fix, no reason to leave archived orders with a
-- stale zero when the real geometry is right there too.

with target as (
  select dng.id as dng_id, sum(seg.area_ha) as total_ha
    from delovni_nalogi_gerki dng
    join gerk_segmentation gs on gs.gerk_id = dng.gerk_code
    join gerk_segment seg on seg.segmentation_id = gs.id
   where dng.kolicina_ha is null
   group by dng.id
  having sum(seg.area_ha) > 0
)
update delovni_nalogi_gerki dng
   set kolicina_ha = target.total_ha
  from target
 where dng.id = target.dng_id;

-- Verify: should now be 2 or fewer (the compound "A+B+C" code and any
-- other line with genuinely no imported geometry to draw from).
select count(*) as still_null_with_no_fix_possible
  from delovni_nalogi_gerki
 where kolicina_ha is null;

-- Verify per order, matching the earlier main-screen check (should now
-- be empty or only show orders whose GERKs truly have no geometry at all).
select dn.stevilka, coalesce(sum(dng.kolicina_ha), 0) as total_ha
  from delovni_nalogi dn
  left join delovni_nalogi_gerki dng on dng.delovni_nalog_id = dn.id
 where dn.deleted_at is null
 group by dn.stevilka
having coalesce(sum(dng.kolicina_ha), 0) = 0
 order by dn.stevilka::int;
