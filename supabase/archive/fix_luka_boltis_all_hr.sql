-- Follow-up correction to fix_luka_boltis_split_entities.sql (archived).
-- That fix only moved the 5 GERK codes that collided with a Slovenian
-- registry entry (i.e. existed under both drzava='SI' and drzava='HR').
-- Checking every remaining code individually shows that was wrong scope:
-- ALL 26 matched codes left on orders #98 and #99 are Croatia-only
-- (drzava='HR', no 'SI' row exists at all for them), and the one
-- unmatched code (3154616, a KML-imported zone with no registry polygon)
-- centroids in the same Koprivnica-area cluster as the rest. There is no
-- genuinely Slovenian land on either order — the whole "Luka Boltiš - SLO"
-- customer currently has no real orders, it just held the wrong ones.
--
-- Fix: reassign orders #98 and #99 to the Croatian entity
-- (0a73a52a-05cf-445d-a89a-4249d9ae846e). This is a plain customer
-- reassignment (stranka_id), not a GERK-line split like before — nothing
-- else about the orders needs to change.

update delovni_nalogi
   set stranka_id = '0a73a52a-05cf-445d-a89a-4249d9ae846e'
 where id in (
   'e4a1373c-7eb0-41c3-a340-d832fe722ba7', -- #98
   '8c66f0bb-e110-462e-8288-388939b5a8c7'  -- #99
 );

-- Verify: "Luka Boltiš - SLO" should now have zero orders, and
-- "Luka Boltiš - HR" should show #27, #98, #99, #101.
select dn.stevilka, cu.naziv, dn.status
  from delovni_nalogi dn
  join customers cu on cu.id = dn.stranka_id
 where cu.id in ('0a73a52a-05cf-445d-a89a-4249d9ae846e', '3b892d7e-9a1f-4678-868c-11f3c334c70f')
 order by cu.naziv, dn.stevilka::int;
