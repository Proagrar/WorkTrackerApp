-- ============================================================
-- WorkTracker — let regular (non-admin) users write the segment/
-- sample comment field, not just admins
-- Run in: Supabase Dashboard -> SQL Editor -> New Query
-- ============================================================
--
-- Root cause: delovni_nalogi_vzorci has only two RLS policies —
-- "Admins can manage samples" (FOR ALL, admin-only) and "Authenticated
-- users can view samples of open work orders" (FOR SELECT only).
-- There has never been an UPDATE policy for regular users at all, so
-- even though the frontend also happened to render the comment field
-- as read-only for non-admins (renderSampleCommentCell), fixing just
-- that would still fail — the .update() call itself would be silently
-- rejected by RLS.
--
-- admin and regular users are the SAME Postgres role (authenticated) —
-- admin-ness is an app-level profiles.role check, not a separate
-- Postgres role — so a plain new RLS policy would open every column
-- on the table to regular users, not just comment (delovni_nalogi_vzorci
-- already has a blanket table-level UPDATE grant to authenticated,
-- confirmed via has_table_privilege). Routing through a narrow
-- SECURITY DEFINER RPC that only ever touches the comment column
-- avoids that — same reasoning as every other narrow-RPC-over-RLS
-- fix this session (e.g. set_operator_role_org).
--
-- Scope: regular users can comment on samples belonging to open work
-- orders (Plan/V delu) — the same scope they can already SELECT via
-- the existing view policy, so this isn't a new restriction, just
-- matching existing visibility. Admins keep their existing broader
-- reach (any status), matching "Admins can manage samples".

create or replace function public.update_sample_comment(p_sample_id uuid, p_comment text)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
    v_is_admin boolean;
begin
    if auth.uid() is null then
        raise exception 'Not authenticated';
    end if;

    select exists(select 1 from public.profiles where id = auth.uid() and role = 'admin') into v_is_admin;

    if not exists (
        select 1
          from public.delovni_nalogi_vzorci v
          join public.delovni_nalogi_gerki g on g.id = v.delovni_nalog_gerk_id
          join public.delovni_nalogi dn on dn.id = g.delovni_nalog_id
         where v.id = p_sample_id
           and (v_is_admin or dn.status in ('Plan', 'V delu'))
    ) then
        raise exception 'Vzorec ne obstaja ali ni več na voljo za urejanje';
    end if;

    update public.delovni_nalogi_vzorci
       set comment = nullif(trim(p_comment), '')
     where id = p_sample_id;
end;
$$;

revoke all on function public.update_sample_comment(uuid, text) from public, anon;
grant execute on function public.update_sample_comment(uuid, text) to authenticated;

select pg_notify('pgrst', 'reload schema');
