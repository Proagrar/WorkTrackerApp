-- ============================================================
-- WorkTracker — Remove unclear customer/field records pending re-import
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================
--
-- Three records flagged as unresolvable without more context (see chat):
--   1. "Žiga" @ HPG d.o.o (17 fields, 182.13 ha) — may be the same real
--      entity as the existing "HPG d.o.o." customer, or a different one.
--   2. "Žiga" @ Sadjarstvo Blanca d.o.o. (34 fields, 56.93 ha) — may be
--      the same real entity as the existing "Evrosad d.o.o." customer,
--      or a different one.
--   3. GERK 3411666 ("ŠTANGREB", 3.76 ha) currently under Drago Sinur —
--      contested by Janez Škrjanec's July 2026 work order (3.33 ha),
--      which is why it was excluded from that import to begin with.
--
-- Verified before writing this: none of the three have any linked work
-- orders, declarations, links, or reports, and no delovni_nalogi_gerki
-- row references gerk_code = '3411666' — safe to remove with no other
-- cleanup needed. Wrapped in a transaction.

begin;

-- 1 & 2: "Žiga" customers (fields first, then the customer rows)
delete from public.fields where customer_id in (
  '9031beeb-3d2b-4fc0-8e6a-a437d6e6eb15', -- Žiga @ HPG d.o.o
  'e98aa3e1-cc12-4c77-a866-8ce00af8bf7f'  -- Žiga @ Sadjarstvo Blanca d.o.o.
);
delete from public.customers where id in (
  '9031beeb-3d2b-4fc0-8e6a-a437d6e6eb15',
  'e98aa3e1-cc12-4c77-a866-8ce00af8bf7f'
);

-- 3: ŠTANGREB (base GERK 3411666) under Drago Sinur. Leaves the -1 and -2
-- suffixed sub-parcels alone — those were never part of the conflict.
delete from public.fields where id = 'c26b767f-78a2-4b0d-8f0e-f57bb01493c7';

commit;
