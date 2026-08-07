-- ============================================================
-- WorkTracker App — Supabase Database Schema
-- Run this once in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================


-- ── 1. Profiles ──────────────────────────────────────────────
create table if not exists public.profiles (
    id         uuid primary key references auth.users(id) on delete cascade,
    full_name  text,
    role       text not null default 'operator',
    created_at timestamptz not null default now()
);


-- ── 2. Work Logs ─────────────────────────────────────────────
create table if not exists public.work_logs (
    id         uuid primary key default gen_random_uuid(),

    operator_id uuid not null references auth.users(id) on delete cascade,

    work_date  date not null default current_date,
    start_time time not null,
    end_time   time not null,

    gerk_number text not null,
    description text,

    latitude             numeric,
    longitude            numeric,
    location_accuracy    numeric,
    location_captured_at timestamptz,
    location_status      text,

    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),

    constraint chk_end_time_after_start_time
        check (end_time > start_time),

    constraint chk_start_time_15_min_interval
        check (
            extract(minute from start_time)::int in (0, 15, 30, 45)
            and extract(second from start_time)::int = 0
        ),

    constraint chk_end_time_15_min_interval
        check (
            extract(minute from end_time)::int in (0, 15, 30, 45)
            and extract(second from end_time)::int = 0
        )
);


-- ── 3. Audit Log ─────────────────────────────────────────────
create table if not exists public.work_log_audit (
    id          bigint generated always as identity primary key,

    work_log_id uuid,
    operator_id uuid,

    action      text not null,   -- INSERT | UPDATE | DELETE

    old_data    jsonb,
    new_data    jsonb,

    changed_at  timestamptz not null default now(),
    changed_by  uuid references auth.users(id)
);


-- ── 4. updated_at trigger ────────────────────────────────────
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

drop trigger if exists trg_work_logs_set_updated_at on public.work_logs;
create trigger trg_work_logs_set_updated_at
before update on public.work_logs
for each row execute function public.set_updated_at();


-- ── 5. Audit trigger ─────────────────────────────────────────
create or replace function public.audit_work_logs()
returns trigger
language plpgsql
security definer
as $$
begin
    if tg_op = 'INSERT' then
        insert into public.work_log_audit
            (work_log_id, operator_id, action, old_data, new_data, changed_by)
        values
            (new.id, new.operator_id, 'INSERT', null, to_jsonb(new), auth.uid());
        return new;

    elsif tg_op = 'UPDATE' then
        insert into public.work_log_audit
            (work_log_id, operator_id, action, old_data, new_data, changed_by)
        values
            (new.id, new.operator_id, 'UPDATE', to_jsonb(old), to_jsonb(new), auth.uid());
        return new;

    elsif tg_op = 'DELETE' then
        insert into public.work_log_audit
            (work_log_id, operator_id, action, old_data, new_data, changed_by)
        values
            (old.id, old.operator_id, 'DELETE', to_jsonb(old), null, auth.uid());
        return old;
    end if;

    return null;
end;
$$;

drop trigger if exists trg_work_logs_audit on public.work_logs;
create trigger trg_work_logs_audit
after insert or update or delete on public.work_logs
for each row execute function public.audit_work_logs();


-- ── 6. Row Level Security ────────────────────────────────────
alter table public.profiles      enable row level security;
alter table public.work_logs     enable row level security;
alter table public.work_log_audit enable row level security;


-- ── 7. Profiles RLS ──────────────────────────────────────────
drop policy if exists "Users can view own profile"   on public.profiles;
drop policy if exists "Users can update own profile" on public.profiles;
drop policy if exists "Users can insert own profile" on public.profiles;

create policy "Users can view own profile"
    on public.profiles for select
    using (id = auth.uid());

create policy "Users can update own profile"
    on public.profiles for update
    using (id = auth.uid()) with check (id = auth.uid());

create policy "Users can insert own profile"
    on public.profiles for insert
    with check (id = auth.uid());


-- ── 8. Work Logs RLS ─────────────────────────────────────────
drop policy if exists "Operators can view own work logs"   on public.work_logs;
drop policy if exists "Operators can insert own work logs" on public.work_logs;
drop policy if exists "Operators can update own work logs" on public.work_logs;
drop policy if exists "Operators can delete own work logs" on public.work_logs;

create policy "Operators can view own work logs"
    on public.work_logs for select
    using (operator_id = auth.uid());

create policy "Operators can insert own work logs"
    on public.work_logs for insert
    with check (operator_id = auth.uid());

create policy "Operators can update own work logs"
    on public.work_logs for update
    using (operator_id = auth.uid()) with check (operator_id = auth.uid());

create policy "Operators can delete own work logs"
    on public.work_logs for delete
    using (operator_id = auth.uid());


-- ── 9. Audit Log RLS (read-only for operators) ───────────────
drop policy if exists "Operators can view own audit records" on public.work_log_audit;

create policy "Operators can view own audit records"
    on public.work_log_audit for select
    using (operator_id = auth.uid());

-- No INSERT / UPDATE / DELETE policies for normal users.
-- Audit records are written exclusively by the database trigger (security definer).


-- ── 10. Helper: create operator profile on first login ───────
-- Call this from your admin panel or run manually:
--   insert into public.profiles (id, full_name, role)
--   values ('<user-uuid-from-auth.users>', 'Janez Novak', 'operator');
