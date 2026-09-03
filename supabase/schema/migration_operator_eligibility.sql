-- ============================================================
-- WorkTracker — Izvajalec eligibility flag
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================
--
-- Not every user should be assignable as a work order's izvajalec —
-- e.g. an office/admin account, or an operator not certified for a
-- given job type. Defaults to true so nobody currently selectable
-- disappears from the dropdown the moment this migration runs; an
-- admin then opts specific people OUT via the new "Izvajalci" panel
-- (FAB menu), rather than everyone vanishing until manually re-added.

alter table public.profiles
    add column if not exists eligible_izvajalec boolean not null default true;

-- profiles only has "Users can update own profile" (id = auth.uid())
-- — no admin-can-update-anyone policy exists, so toggling someone
-- else's flag needs a SECURITY DEFINER RPC, same reasoning as every
-- other admin-only write this session went through an RPC for rather
-- than widening RLS.
create or replace function public.set_operator_eligibility(p_profile_id uuid, p_eligible boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    if not exists (select 1 from public.profiles where id = auth.uid() and role = 'admin') then
        raise exception 'Not authorized';
    end if;

    update public.profiles set eligible_izvajalec = p_eligible where id = p_profile_id;
end;
$$;

revoke execute on function public.set_operator_eligibility(uuid, boolean) from public, anon;
grant execute on function public.set_operator_eligibility(uuid, boolean) to authenticated;
