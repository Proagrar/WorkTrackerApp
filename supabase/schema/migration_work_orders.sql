-- ============================================================
-- WorkTracker — Delovni nalogi (Work Orders)
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================


-- ── 1. Table ──────────────────────────────────────────────────
create table if not exists public.delovni_nalogi (
    id            uuid primary key default gen_random_uuid(),

    stevilka      text not null unique,                                  -- npr. DN-001
    stranka_id    uuid references public.customers(id) on delete set null,
    izvajalec     uuid references public.profiles(id) on delete set null,

    kolicina_ha   numeric(10, 2),                                        -- površina v ha
    tip_storitve  text,                                                  -- vzorčenje, gnojenje, ...
    strosek_ocena numeric(12, 2),                                        -- ocenjeni strošek €
    strosek       numeric(12, 2),                                        -- dejanski strošek €
    ure           numeric(6, 2),                                         -- sync iz mobilne app

    status        text not null default 'Plan',

    ustvarjen     timestamptz not null default now(),
    posodobljen   timestamptz not null default now(),

    constraint chk_status check (status in ('Plan', 'V delu', 'Izvedeno', 'Izdan Račun')),
    constraint chk_tip check (tip_storitve in ('Vzorčenje', 'Gnojenje', 'Setev', 'Škropljenje', 'Žetev'))
);


-- ── 2. Indexes ────────────────────────────────────────────────
create index if not exists idx_delovni_nalogi_stranka_id   on public.delovni_nalogi (stranka_id);
create index if not exists idx_delovni_nalogi_izvajalec    on public.delovni_nalogi (izvajalec);
create index if not exists idx_delovni_nalogi_status       on public.delovni_nalogi (status);
create index if not exists idx_delovni_nalogi_tip_storitve on public.delovni_nalogi (tip_storitve);


-- ── 3. Auto-update posodobljen timestamp ─────────────────────
create or replace function public.update_posodobljen()
returns trigger
language plpgsql
set search_path = public
as $$
begin
    new.posodobljen = now();
    return new;
end;
$$;

-- Not SECURITY DEFINER and only meaningful inside a trigger (references
-- NEW), but revoke direct API/RPC execute anyway — no legitimate caller
-- needs to invoke this outside the trigger context.
revoke execute on function public.update_posodobljen() from public, anon, authenticated;

drop trigger if exists trg_delovni_nalogi_posodobljen on public.delovni_nalogi;
create trigger trg_delovni_nalogi_posodobljen
before update on public.delovni_nalogi
for each row execute function public.update_posodobljen();


-- ── 4. Row Level Security ────────────────────────────────────
alter table public.delovni_nalogi enable row level security;

drop policy if exists "Admins can manage work orders"        on public.delovni_nalogi;
drop policy if exists "Supervisors can view work orders"      on public.delovni_nalogi;
drop policy if exists "Operators can view own work orders"    on public.delovni_nalogi;

-- Admins: full CRUD.
create policy "Admins can manage work orders"
    on public.delovni_nalogi for all
    using (
        exists (select 1 from public.profiles where id = auth.uid() and role = 'admin')
    )
    with check (
        exists (select 1 from public.profiles where id = auth.uid() and role = 'admin')
    );

-- Supervisors: read-only, only not-yet-completed work orders.
create policy "Supervisors can view work orders"
    on public.delovni_nalogi for select
    to authenticated
    using (
        status in ('Plan', 'V delu')
        and exists (select 1 from public.profiles where id = auth.uid() and role = 'supervisor')
    );

-- Operators: read-only, only their own not-yet-completed work orders.
create policy "Operators can view own work orders"
    on public.delovni_nalogi for select
    using (izvajalec = auth.uid() and status in ('Plan', 'V delu'));


-- ── 5. Customers read access (needed for stranka_id lookups/joins) ──
-- customers currently only has a service-role bypass policy — no
-- authenticated role can read it, which would silently break the
-- work-order UI's customer picker and the stranka_id embed/join.
drop policy if exists "Authenticated users can view customers" on public.customers;

create policy "Authenticated users can view customers"
    on public.customers for select
    to authenticated
    using (true);


-- ── 6. Link work_logs to work orders (mandatory) ─────────────
-- work_logs already has 7 real rows predating delovni_nalogi, so we
-- can't add a NOT NULL FK in one step. Add nullable, backfill existing
-- rows onto a single placeholder work order, then enforce NOT NULL.
alter table public.work_logs
    add column if not exists work_order_id uuid references public.delovni_nalogi(id);

do $$
declare
    legacy_id uuid;
begin
    select id into legacy_id from public.delovni_nalogi where stevilka = 'DN-LEGACY';

    if legacy_id is null then
        insert into public.delovni_nalogi (stevilka, status, tip_storitve)
        values ('DN-LEGACY', 'Izvedeno', null)
        returning id into legacy_id;
    end if;

    update public.work_logs
        set work_order_id = legacy_id
        where work_order_id is null;
end $$;

alter table public.work_logs
    alter column work_order_id set not null;

create index if not exists idx_work_logs_work_order_id on public.work_logs (work_order_id);
