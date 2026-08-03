-- ============================================================
-- WorkTracker — Samples (child of delovni_nalogi_gerki)
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================
--
-- One row per lab sample taken on a planned field within a work order —
-- a single GERK can carry multiple samples. Sourced from the manual
-- "Work order" Excel files (VZORČENJE/POPIS VZORCEV/Delovni nalogi),
-- which track this per-field detail that delovni_nalogi_gerki alone
-- doesn't capture.

create table if not exists public.delovni_nalogi_vzorci (
    id                     uuid primary key default gen_random_uuid(),
    delovni_nalog_gerk_id  uuid not null references public.delovni_nalogi_gerki(id) on delete cascade,
    sample_no              text not null,
    sampling_date          date,
    sending_date           date,
    created_at             timestamptz not null default now()
);

create index if not exists idx_delovni_nalogi_vzorci_gerk_id on public.delovni_nalogi_vzorci (delovni_nalog_gerk_id);

alter table public.delovni_nalogi_vzorci enable row level security;

drop policy if exists "Admins can manage samples" on public.delovni_nalogi_vzorci;
drop policy if exists "Authenticated users can view samples of open work orders" on public.delovni_nalogi_vzorci;

create policy "Admins can manage samples"
    on public.delovni_nalogi_vzorci for all
    using (
        exists (select 1 from public.profiles where id = auth.uid() and role = 'admin')
    )
    with check (
        exists (select 1 from public.profiles where id = auth.uid() and role = 'admin')
    );

-- Mirrors delovni_nalogi_gerki's own "open work orders only" read policy.
create policy "Authenticated users can view samples of open work orders"
    on public.delovni_nalogi_vzorci for select
    to authenticated
    using (
        exists (
            select 1
              from public.delovni_nalogi_gerki g
              join public.delovni_nalogi dn on dn.id = g.delovni_nalog_id
             where g.id = delovni_nalogi_vzorci.delovni_nalog_gerk_id
               and dn.status = any (array['Plan', 'V delu'])
        )
    );
