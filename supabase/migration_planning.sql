-- WorkTracker: persistent planning state for delovni_nalogi
-- Run after the source tables delovni_nalogi and fields exist.

-- The planning screen reads gerk_lastnost with the authenticated Supabase user.
-- Without this policy, SQL Editor can read the table but the app receives no rows.
alter table public.gerk_lastnost enable row level security;
grant select on table public.gerk_lastnost to authenticated;

drop policy if exists "authenticated_read" on public.gerk_lastnost;
create policy "authenticated_read" on public.gerk_lastnost
    for select to authenticated using (true);

alter table public.gerk_raba_id_slovar enable row level security;
grant select on table public.gerk_raba_id_slovar to authenticated;
drop policy if exists "authenticated_read" on public.gerk_raba_id_slovar;
create policy "authenticated_read" on public.gerk_raba_id_slovar
    for select to authenticated using (true);

alter table public.gerk_polygon enable row level security;
grant select on table public.gerk_polygon to authenticated;
drop policy if exists "authenticated_read" on public.gerk_polygon;
create policy "authenticated_read" on public.gerk_polygon
    for select to authenticated using (true);

create table if not exists public.delovni_nalogi_planiranje (
    id uuid primary key default gen_random_uuid(),
    delovni_nalog_id text not null unique,
    plan_date date not null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

alter table public.delovni_nalogi_planiranje
    drop constraint if exists delovni_nalogi_planiranje_delovni_nalog_id_key;

create table if not exists public.delovni_nalogi_planiranje_gerki (
    plan_id uuid not null references public.delovni_nalogi_planiranje(id) on delete cascade,
    field_id text not null,
    primary key (plan_id, field_id)
);

create index if not exists idx_delovni_nalogi_planiranje_date
    on public.delovni_nalogi_planiranje(plan_date);

alter table public.delovni_nalogi_planiranje enable row level security;
alter table public.delovni_nalogi_planiranje_gerki enable row level security;

drop policy if exists "Authenticated users can read planning" on public.delovni_nalogi_planiranje;
drop policy if exists "Authenticated users can insert planning" on public.delovni_nalogi_planiranje;
drop policy if exists "Authenticated users can update planning" on public.delovni_nalogi_planiranje;
drop policy if exists "Authenticated users can delete planning" on public.delovni_nalogi_planiranje;
drop policy if exists "Authenticated users can read planned gerki" on public.delovni_nalogi_planiranje_gerki;
drop policy if exists "Authenticated users can insert planned gerki" on public.delovni_nalogi_planiranje_gerki;
drop policy if exists "Authenticated users can delete planned gerki" on public.delovni_nalogi_planiranje_gerki;

create policy "Authenticated users can read planning"
    on public.delovni_nalogi_planiranje for select to authenticated using (true);
create policy "Authenticated users can insert planning"
    on public.delovni_nalogi_planiranje for insert to authenticated with check (true);
create policy "Authenticated users can update planning"
    on public.delovni_nalogi_planiranje for update to authenticated using (true) with check (true);
create policy "Authenticated users can delete planning"
    on public.delovni_nalogi_planiranje for delete to authenticated using (true);

create policy "Authenticated users can read planned gerki"
    on public.delovni_nalogi_planiranje_gerki for select to authenticated using (true);
create policy "Authenticated users can insert planned gerki"
    on public.delovni_nalogi_planiranje_gerki for insert to authenticated with check (true);
create policy "Authenticated users can delete planned gerki"
    on public.delovni_nalogi_planiranje_gerki for delete to authenticated using (true);

create or replace function public.set_planning_updated_at()
returns trigger
language plpgsql
as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

drop trigger if exists trg_delovni_nalogi_planiranje_updated_at
    on public.delovni_nalogi_planiranje;
create trigger trg_delovni_nalogi_planiranje_updated_at
before update on public.delovni_nalogi_planiranje
for each row execute function public.set_planning_updated_at();
