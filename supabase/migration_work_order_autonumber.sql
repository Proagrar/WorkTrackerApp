-- ============================================================
-- WorkTracker — Auto-number delovni_nalogi.stevilka (DN-001, DN-002, ...)
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================

create sequence if not exists public.delovni_nalogi_stevilka_seq;

alter table public.delovni_nalogi
    alter column stevilka set default ('DN-' || lpad(nextval('public.delovni_nalogi_stevilka_seq')::text, 3, '0'));

-- INSERTs from the client run as the "authenticated" role (RLS still
-- decides whether the row is allowed) — it needs USAGE on the sequence
-- for the DEFAULT expression to evaluate at all, otherwise the insert
-- errors before RLS even gets a say.
grant usage, select on sequence public.delovni_nalogi_stevilka_seq to authenticated;
