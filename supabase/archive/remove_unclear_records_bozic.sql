-- ============================================================
-- WorkTracker — Remove unclear "Božić" customer records
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================
--
-- Same ambiguity class as "Žiga" (removed earlier in remove_unclear_records.sql):
-- "Siniša Božić" (1 field, "Božić 4", 21.00 ha) and "Božić d.o.o." (1 field,
-- "VRBINA - PETRIČKO", 14.60 ha) share a company name but have zero field
-- overlap and no matching email — no way to confirm whether they're the same
-- real entity. Removing both pending re-import with clearer identity info.
--
-- Verified before writing this: neither has any linked work orders,
-- declarations, links, orders, or reports. Safe to remove with no other
-- cleanup needed. Wrapped in a transaction.

begin;

delete from public.fields where customer_id in (
  'a437b853-095e-41e0-b0f1-8ef7186b94bf', -- Siniša Božić
  '0661833b-e8b1-46e5-bdb7-98e77f4d0847'  -- Božić d.o.o.
);
delete from public.customers where id in (
  'a437b853-095e-41e0-b0f1-8ef7186b94bf',
  '0661833b-e8b1-46e5-bdb7-98e77f4d0847'
);

commit;
