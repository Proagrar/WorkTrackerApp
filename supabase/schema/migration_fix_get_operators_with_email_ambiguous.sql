-- ============================================================
-- WorkTracker — Fix ambiguous "id" in get_operators_with_email
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================
--
-- Same bug as start_gerk/end_gerk/set_gerk_times (see
-- migration_fix_gerk_time_functions_ambiguous_column.sql): RETURNS
-- TABLE(id uuid, ...) implicitly declares "id" as an OUT-parameter
-- variable inside the function body, so the bare "id" in
-- "where id = auth.uid()" is ambiguous against profiles.id. Confirmed
-- via logs 2026-09-04: every call failed with 42702 ("column
-- reference \"id\" is ambiguous"), which is why the Izvajalci panel
-- rendered empty rather than erroring visibly.
--
-- Fix: #variable_conflict use_column, same pragma used for the other
-- three functions — makes every bare identifier prefer a real table
-- column over a same-named variable.

create or replace function public.get_operators_with_email()
returns table (
    id                  uuid,
    full_name           text,
    eligible_izvajalec  boolean,
    email               text
)
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_column
begin
    if not exists (select 1 from public.profiles where id = auth.uid() and role = 'admin') then
        raise exception 'Not authorized';
    end if;

    return query
    select p.id, p.full_name, p.eligible_izvajalec, u.email::text
      from public.profiles p
      join auth.users u on u.id = p.id
     order by p.full_name;
end;
$$;

revoke execute on function public.get_operators_with_email() from public, anon;
grant execute on function public.get_operators_with_email() to authenticated;
