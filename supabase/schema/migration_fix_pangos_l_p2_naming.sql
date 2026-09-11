-- ============================================================
-- WorkTracker — one-off data fix: Pangos L P2 GERK naming + duplicates
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================
--
-- Three KML import attempts for this GERK used inconsistent text:
--   d56649f1-26e0-4bba-b0c6-6da5007bb9b8  gerk_id "Pangos L P2"   (12:44, oldest — dropped, duplicate)
--   e93d723f-58d6-4dc1-8c3b-4ef8955e270c  gerk_id "Pangos L P2"   (12:47 — kept, renamed target)
--   b1222056-4d3f-4c5a-be07-432200fa57d5  gerk_id "Pangos_L_P2"   (12:48, most recent — dropped, no
--                                                                   longer matches after the rename below)
-- delovni_nalogi_gerki currently has this GERK as "Pangos_L_P2"
-- (underscore), inconsistent with its siblings (Pangos L P1/P3,
-- Pangos L S1/S2/S3, all space-separated). Renaming it to match, then
-- keeping exactly one of the two "Pangos L P2" segmentations (they're
-- identical — same 4 zones, same geometry) and dropping the other two.

update public.delovni_nalogi_gerki
   set gerk_code = 'Pangos L P2'
 where id = 'd82befd4-eb50-4090-90fa-c0016b1248a8'
   and gerk_code = 'Pangos_L_P2';

-- gerk_captured_point unlink first (same as remove_gerk_segmentation
-- does) — a no-op here since nothing was captured against these yet,
-- but safe/correct either way.
update public.gerk_captured_point
   set segmentation_id = null, segment_id = null
 where segmentation_id in (
   'd56649f1-26e0-4bba-b0c6-6da5007bb9b8',
   'b1222056-4d3f-4c5a-be07-432200fa57d5'
 );

delete from public.gerk_segmentation
 where id in (
   'd56649f1-26e0-4bba-b0c6-6da5007bb9b8',  -- duplicate "Pangos L P2" import
   'b1222056-4d3f-4c5a-be07-432200fa57d5'   -- "Pangos_L_P2" — orphaned once the GERK is renamed above
 );
