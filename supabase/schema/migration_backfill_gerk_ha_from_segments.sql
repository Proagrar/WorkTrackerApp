-- ============================================================
-- WorkTracker — backfill missing GERK hectares from imported zone geometry
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================
--
-- delovni_nalogi_gerki.kolicina_ha only ever gets set at GERK-creation
-- time, from a registry lookup (fields.area_ha by cadastre_id). Custom
-- or sub-divided GERK codes (e.g. a large field split into KML sub-
-- fields like "1526437_CH1", "1526437_MO7"...) have no registry match
-- at all, so they show no Ha even though the imported zone geometry is
-- sitting right there — gerk_segment.area_ha is a generated column,
-- computed automatically from each zone's actual polygon (ST_Area).
-- This backfills every GERK still missing Ha with the sum of its
-- imported zones' area — 21 rows app-wide as of 2026-09-23, across
-- several customers, not just this one.
--
-- app.js (v2.13) now does this automatically for every future KML
-- import — this migration is only for GERKs that were already
-- imported before that fix shipped.

with computed as (
  select dng.id, sum(seg.area_ha) as computed_ha
  from delovni_nalogi_gerki dng
  join gerk_segmentation gs on gs.gerk_id = dng.gerk_code
  join gerk_segment seg on seg.segmentation_id = gs.id
  where dng.kolicina_ha is null
  group by dng.id
)
update delovni_nalogi_gerki dng
set kolicina_ha = computed.computed_ha
from computed
where dng.id = computed.id;
