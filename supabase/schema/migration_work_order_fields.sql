-- ============================================================
-- WorkTracker — Delovni nalogi: field-level detail (multi-GERK per order)
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- Depends on: migration_work_orders.sql (must be applied first)
-- ============================================================


-- ── 1. Table ──────────────────────────────────────────────────
create table if not exists public.delovni_nalogi_gerki (
    id               uuid primary key default gen_random_uuid(),
    delovni_nalog_id uuid not null references public.delovni_nalogi(id) on delete cascade,
    gerk_code        text not null,
    kolicina_ha      numeric(10, 2),
    created_at       timestamptz not null default now()
);

create index if not exists idx_delovni_nalogi_gerki_delovni_nalog_id
    on public.delovni_nalogi_gerki (delovni_nalog_id);


-- ── 2. Drop the old single-total column ──────────────────────
-- Only the DN-LEGACY placeholder row exists at migration time, with
-- kolicina_ha null — nothing to backfill. Hectares now live per-field.
alter table public.delovni_nalogi drop column if exists kolicina_ha;


-- ── 3. Row Level Security ────────────────────────────────────
-- Mirrors the parent delovni_nalogi policies exactly (same roles, same
-- non-completed-status scoping for supervisors/operators), joined via
-- delovni_nalog_id since this table has no status/izvajalec of its own.
alter table public.delovni_nalogi_gerki enable row level security;

drop policy if exists "Admins can manage work order fields"      on public.delovni_nalogi_gerki;
drop policy if exists "Supervisors can view work order fields"    on public.delovni_nalogi_gerki;
drop policy if exists "Operators can view own work order fields"  on public.delovni_nalogi_gerki;

create policy "Admins can manage work order fields"
    on public.delovni_nalogi_gerki for all
    using (
        exists (select 1 from public.profiles where id = auth.uid() and role = 'admin')
    )
    with check (
        exists (select 1 from public.profiles where id = auth.uid() and role = 'admin')
    );

create policy "Supervisors can view work order fields"
    on public.delovni_nalogi_gerki for select
    to authenticated
    using (
        exists (
            select 1 from public.delovni_nalogi dn
            where dn.id = delovni_nalogi_gerki.delovni_nalog_id
              and dn.status in ('Plan', 'V delu')
              and exists (select 1 from public.profiles where id = auth.uid() and role = 'supervisor')
        )
    );

create policy "Operators can view own work order fields"
    on public.delovni_nalogi_gerki for select
    using (
        exists (
            select 1 from public.delovni_nalogi dn
            where dn.id = delovni_nalogi_gerki.delovni_nalog_id
              and dn.izvajalec = auth.uid()
              and dn.status in ('Plan', 'V delu')
        )
    );
