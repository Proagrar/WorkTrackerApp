-- ============================================================
-- WorkTracker — Second-pass customer merges
-- Found via a broader duplicate check after the first dedup pass:
-- these weren't caught before because the two records used different
-- contact-name spellings under the same company, not matching naziv
-- strings.
-- ============================================================
--
-- 1. OPG Ivan Marić — "Ivan Marić" and "Ante Marić" both attached to
--    company "OPG Ivan Marić", with all 6 fields identical between
--    them (same cadastre_id/name/area_ha) — an exact mirror, same
--    pattern as the Drago Sinur case in the first pass. "Ante" is
--    almost certainly a misread/typo of "Ivan" from one of the two
--    2026-04 import batches.
--
-- 2. Kmetijska šola Grm — "Luka Novak" (13 fields) and the existing
--    "GRM Novo mesto-center biotehnike in turizma" record (19 fields)
--    share the same company_name. 12 of Luka Novak's 13 fields exactly
--    match a GRM field (same cadastre_id/name/area); the 13th ("Stari
--    Grad", 1660650) matches GRM's copy to within 0.01 ha — treated as
--    the same duplicated parcel. GRM's record is kept as the fuller,
--    more complete one. Luka Novak had 4 rows in `reports` — repointed
--    to GRM before deletion, not dropped.
--
-- Left out: "Božić d.o.o." (Siniša Božić vs Božić d.o.o.) — company
-- name matches but the two hold completely different fields with no
-- overlap and no matching email. Same ambiguity class as "Žiga" —
-- not merged here, needs a manual call.

begin;

-- 1. OPG Ivan Marić — keep 32a5b8ae (Ivan Marić), remove e0c735c9 (Ante Marić)
delete from public.fields where customer_id = 'e0c735c9-952d-45e3-ab47-b82b82ef7b47'; -- all 6 are exact duplicates of Ivan Marić's
delete from public.customers where id = 'e0c735c9-952d-45e3-ab47-b82b82ef7b47';

-- 2. Kmetijska šola Grm — keep 64bd23f9 (GRM), remove 83afa7ab (Luka Novak)
update public.reports set customer_id = '64bd23f9-2d82-4ba3-936b-7e344bda33b2' where customer_id = '83afa7ab-4575-41a2-9499-2fc6b7a19a9e';
delete from public.fields where customer_id = '83afa7ab-4575-41a2-9499-2fc6b7a19a9e'; -- all 13 already exist under GRM
delete from public.customers where id = '83afa7ab-4575-41a2-9499-2fc6b7a19a9e';

commit;
