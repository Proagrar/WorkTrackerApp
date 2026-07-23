-- ============================================================
-- WorkTracker — One work_logs row per operator/order/day
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================

-- The live Start/Stop flow lazily creates today's work_logs row on
-- first use (check-then-insert from the client). Two GERK rows
-- started in quick succession could race and create two rows for the
-- same day before either insert resolves. A plain UNIQUE constraint
-- can't be added here: the 7 pre-work-order legacy rows were all
-- backfilled onto a single DN-LEGACY placeholder order, and two pairs
-- of them already share the same operator+date (from before work
-- orders existed). A partial unique index sidesteps that by only
-- enforcing uniqueness for real (non-legacy) work orders — which is
-- all that matters, since new orders can never collide with DN-LEGACY.
drop index if exists public.uq_work_logs_operator_order_date;

create unique index uq_work_logs_operator_order_date
    on public.work_logs (operator_id, work_order_id, work_date)
    where work_order_id <> '4f17ae46-3c22-49b8-b078-054575784e9f'; -- DN-LEGACY
