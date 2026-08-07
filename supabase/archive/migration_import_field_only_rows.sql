-- ============================================================
-- WorkTracker — Import the CRM's FIELD-only rows into fields
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================
--
-- Step 1 of standardizing on WorkTracker's own `fields` table instead
-- of reading the CRM's `FIELD`/`B_FIELD_X_CUSTOMER` at all. FIELD
-- currently has 471 cadastre codes that `fields` doesn't have yet.
--
-- v2: the first version of this migration (CODE-based dedup only)
-- failed on fields_customer_name_area_unique — FIELD carries some
-- fields under two DIFFERENT codes (a re-issued/re-numbered GERK for
-- the same physical parcel), which a plain "is this CODE new" check
-- can't catch. Fixed by also matching on (customer, name, area_ha),
-- same as the table's own unique constraint: 21 candidates turned out
-- to already exist in `fields` under a different code entirely (e.g.
-- "Dolenja vas" 0.51ha for Borut Dragan already exists as 2126850;
-- FIELD also carries it as 2119713 — same field, dropped), and 2 more
-- were internal duplicates within FIELD itself under 3 different
-- codes, same customer/name (ROMANIJA, Dimnik Estate — null area, so
-- it wouldn't have errored, but would've created 3 duplicate rows).
-- Final count: 371 (was 394 before this fix).
--
-- This deliberately still leaves out:
--   * "Žiga" (51 codes) and "Siniša Božić" (1 code) — both customers
--     were removed from WorkTracker entirely earlier this session as
--     unresolvable duplicates (see remove_unclear_records.sql /
--     remove_unclear_records_bozic.sql). Re-importing their fields
--     here would silently undo that cleanup.
--   * GERK 3411666 (Drago Sinur) — the base code was deliberately
--     removed in favor of the already-split 3411666-1 / 3411666-2.
--   * "Megamarket 2/3/4" and "?" (4 codes) — not real cadastre codes
--     (no NAME, and WorkTracker already has a single "NA"/"NA" 31.68ha
--     placeholder field for this customer that may already cover this
--     ground). Needs a manual look, not an automated guess.
--
-- Customer matching: each CRM customer name matched exactly one
-- WorkTracker customer by contact_name/company_name/naziv (verified
-- beforehand — 0 unmatched, 0 ambiguous across all 30 names involved).

with field_only as (
    select distinct on (f."CODE")
        f."CODE", f."NAME", f."TOTAL_AREA", f."COMMENT", f."FIELD_ID"
      from public."FIELD" f
     where f."CODE" is not null
       and f."CODE" not in ('3411666', 'Megamarket 2', 'Megamarket 3', 'Megamarket 4', '?')
       and not exists (select 1 from public.fields wf where wf.cadastre_id = f."CODE")
     order by f."CODE", f."FIELD_ID"
),
active_link as (
    select b."FIELD_ID", c."FULL_NAME"
      from public."B_FIELD_X_CUSTOMER" b
      join public."CUSTOMER" c on c."CUSTOMER_ID" = b."CUSTOMER_ID"
     where (b."DATE_TO" is null or b."DATE_TO" >= current_date)
),
matched as (
    select fo."CODE", fo."NAME", fo."TOTAL_AREA", fo."COMMENT", wt.id as wt_customer_id
      from field_only fo
      join active_link al on al."FIELD_ID" = fo."FIELD_ID"
      join public.customers wt
        on lower(btrim(wt.contact_name)) = lower(btrim(al."FULL_NAME"))
        or lower(btrim(wt.company_name)) = lower(btrim(al."FULL_NAME"))
        or lower(btrim(wt.naziv))        = lower(btrim(al."FULL_NAME"))
     where al."FULL_NAME" not in ('Žiga', 'Siniša Božić')
),
-- Drop candidates that are the same physical field as one already in
-- `fields`, just under a different CRM code.
not_already_present as (
    select m.* from matched m
     where not exists (
         select 1 from public.fields ex
          where ex.customer_id = m.wt_customer_id
            and ex.name = m."NAME"
            and ex.area_ha is not distinct from m."TOTAL_AREA"
     )
),
-- Drop FIELD's own internal duplicates (same customer/name/area under
-- multiple codes) down to one row, deterministically by CODE.
deduped as (
    select *, row_number() over (
        partition by wt_customer_id, "NAME", "TOTAL_AREA" order by "CODE"
    ) as rn
    from not_already_present
)
insert into public.fields (customer_id, name, area_ha, cadastre_id, location_notes)
select
    wt_customer_id,
    coalesce(nullif(btrim("NAME"), ''), "CODE"),
    "TOTAL_AREA",
    "CODE",
    "COMMENT"
from deduped
where rn = 1;

-- Expect exactly 371 rows inserted.
