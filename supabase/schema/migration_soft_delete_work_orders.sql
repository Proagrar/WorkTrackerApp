-- ============================================================
-- WorkTracker — soft delete for delovni_nalogi (work orders)
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================
--
-- A work order can now be "archived" (deleted_at set) instead of
-- hard-deleted. Archived orders are excluded client-side from the
-- main work orders list and from Evidenca dela, but stay in the
-- database and can be restored. No RPC needed — "Admins can manage
-- work orders" is already an ALL-command policy, same as the existing
-- direct status update, so a plain update() from the client covers
-- both archiving (deleted_at = now()) and restoring (deleted_at = null).

alter table public.delovni_nalogi add column if not exists deleted_at timestamptz;

select pg_notify('pgrst', 'reload schema');
