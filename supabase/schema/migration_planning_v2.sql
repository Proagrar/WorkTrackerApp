-- WorkTracker: tighten the planning tables (delovni_nalogi_planiranje /
-- delovni_nalogi_planiranje_gerki) that already exist and already hold real
-- data (4 plans, 26 linked GERKs) from an earlier, separate deploy of
-- migration_planning.sql against this project.
--
-- What this does, in order:
-- 1. delovni_nalogi_planiranje.delovni_nalog_id: was a loose `text` column
--    with no FK — retyped to `uuid` with a real foreign key + cascade delete
--    to delovni_nalogi.
-- 2. delovni_nalogi_planiranje_gerki: was keyed by `field_id text` (a raw
--    fields.id with no FK). Remapped to `delovni_nalog_gerk_id uuid`, a real
--    FK to delovni_nalogi_gerki(id) — i.e. keyed by GERK *line* on the order
--    instead of by field, so a compound "A+B+C" GERK line is one plannable
--    unit, same as everywhere else in the app. The remap was dry-run
--    verified first: all 26 existing rows resolve cleanly, zero orphans.
-- 3. RLS on both tables: was wide open to any authenticated user — replaced
--    with admin-only (matches "Admins can manage work orders").
--
-- gerk_lastnost / gerk_polygon / gerk_raba_id_slovar RLS is untouched here —
-- already granted to `authenticated` from the original migration_planning.sql,
-- shared with other tooling on this project, not this migration's concern.

-- 1. delovni_nalog_id: text -> real FK
alter table public.delovni_nalogi_planiranje
  alter column delovni_nalog_id type uuid using delovni_nalog_id::uuid;
alter table public.delovni_nalogi_planiranje
  add constraint delovni_nalogi_planiranje_delovni_nalog_id_fkey
  foreign key (delovni_nalog_id) references public.delovni_nalogi(id) on delete cascade;

-- 2. field_id -> delovni_nalog_gerk_id (GERK-line granularity)
alter table public.delovni_nalogi_planiranje_gerki add column dng_id uuid;

update public.delovni_nalogi_planiranje_gerki pg
   set dng_id = dng.id
  from public.delovni_nalogi_planiranje p,
       public.delovni_nalogi_gerki dng
 where pg.plan_id = p.id
   and dng.delovni_nalog_id = p.delovni_nalog_id
   and dng.field_id = pg.field_id::uuid;

-- Safety net: abort the whole migration if anything failed to remap, rather
-- than silently dropping data. (Already dry-run verified as clean — this is
-- just a guard in case something changed between the check and this run.)
do $$
begin
  if exists (select 1 from public.delovni_nalogi_planiranje_gerki where dng_id is null) then
    raise exception 'migration_planning_v2: some delovni_nalogi_planiranje_gerki rows did not remap to a delovni_nalogi_gerki id — aborting, nothing dropped';
  end if;
end $$;

alter table public.delovni_nalogi_planiranje_gerki drop constraint delovni_nalogi_planiranje_gerki_pkey;
alter table public.delovni_nalogi_planiranje_gerki drop column field_id;
alter table public.delovni_nalogi_planiranje_gerki rename column dng_id to delovni_nalog_gerk_id;
alter table public.delovni_nalogi_planiranje_gerki alter column delovni_nalog_gerk_id set not null;
alter table public.delovni_nalogi_planiranje_gerki
  add constraint delovni_nalogi_planiranje_gerki_dng_fkey
  foreign key (delovni_nalog_gerk_id) references public.delovni_nalogi_gerki(id) on delete cascade;
alter table public.delovni_nalogi_planiranje_gerki
  add primary key (plan_id, delovni_nalog_gerk_id);

-- 3. Admin-only RLS (was: any authenticated user, on both tables)
drop policy if exists "Authenticated users can read planning" on public.delovni_nalogi_planiranje;
drop policy if exists "Authenticated users can insert planning" on public.delovni_nalogi_planiranje;
drop policy if exists "Authenticated users can update planning" on public.delovni_nalogi_planiranje;
drop policy if exists "Authenticated users can delete planning" on public.delovni_nalogi_planiranje;
drop policy if exists "Authenticated users can read planned gerki" on public.delovni_nalogi_planiranje_gerki;
drop policy if exists "Authenticated users can insert planned gerki" on public.delovni_nalogi_planiranje_gerki;
drop policy if exists "Authenticated users can delete planned gerki" on public.delovni_nalogi_planiranje_gerki;

create policy "Admins can manage planning"
  on public.delovni_nalogi_planiranje for all to authenticated
  using (exists (select 1 from public.profiles where id = auth.uid() and role = 'admin'))
  with check (exists (select 1 from public.profiles where id = auth.uid() and role = 'admin'));

create policy "Admins can manage planned gerki"
  on public.delovni_nalogi_planiranje_gerki for all to authenticated
  using (exists (select 1 from public.profiles where id = auth.uid() and role = 'admin'))
  with check (exists (select 1 from public.profiles where id = auth.uid() and role = 'admin'));

-- Revoke from anon by name, not just PUBLIC (PUBLIC-only revoke is a no-op
-- on this project — see feedback_supabase_function_grants memory).
revoke all on public.delovni_nalogi_planiranje from anon;
revoke all on public.delovni_nalogi_planiranje_gerki from anon;
