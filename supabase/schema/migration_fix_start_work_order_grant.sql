-- ============================================================
-- WorkTracker — Fix start_work_order() anon exposure
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================

-- migration_work_order_start_flow.sql only revoked from PUBLIC, but
-- Supabase's default privileges grant EXECUTE directly to anon /
-- authenticated / service_role on new functions (not via PUBLIC), so
-- that revoke did nothing — anon could call this with no login at
-- all and flip any Plan-status order to V delu (izvajalec would land
-- null, but the status change alone is real vandalism). Same class of
-- bug as the operators.sql fix earlier — this time on a fresh function.
revoke execute on function public.start_work_order(uuid) from public, anon;
grant execute on function public.start_work_order(uuid) to authenticated;
