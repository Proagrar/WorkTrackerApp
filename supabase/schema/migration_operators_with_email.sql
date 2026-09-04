-- ============================================================
-- WorkTracker — Show email in the Izvajalci (operators) panel
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================
--
-- profiles has no email column — it lives in auth.users, which isn't
-- exposed via the REST API (and shouldn't be broadly). Narrow admin-
-- only RPC joining the two, same SECURITY DEFINER + internal
-- role-check pattern as set_operator_eligibility.

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
