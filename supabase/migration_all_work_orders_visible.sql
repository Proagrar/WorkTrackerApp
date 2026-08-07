-- ============================================================
-- WorkTracker — Every authenticated user sees every work order,
-- regardless of status
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================
--
-- Supersedes both prior SELECT policies with one blanket policy —
-- same "see everything, admin still gates the writes" approach the
-- Plan/V delu policy already took, just no longer limited by status.
-- Drops the narrower "own orders" policy from the previous migration
-- too, since it's now fully redundant under this one.
--
-- Admin's own "ALL" policy (insert/update/delete + select) is
-- untouched — this only widens what non-admin authenticated users
-- can read.

drop policy if exists "Authenticated users can view open work orders" on public.delovni_nalogi;
drop policy if exists "Operators can view own work orders regardless of status" on public.delovni_nalogi;

create policy "Authenticated users can view all work orders"
    on public.delovni_nalogi for select
    to authenticated
    using (true);
