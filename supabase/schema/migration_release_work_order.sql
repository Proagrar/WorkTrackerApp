-- ============================================================
-- WorkTracker — Release a claimed work order (undo "Prevzemi nalog")
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================
--
-- Mirrors start_work_order's shape. SECURITY DEFINER because the
-- current izvajalec (not just an admin) needs to be able to release
-- their own claim, and the only UPDATE policy on delovni_nalogi is
-- admin-only — so this does its own authorization check inside
-- instead of relying on RLS.

create or replace function public.release_work_order(p_work_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    v_izvajalec uuid;
    v_is_admin  boolean;
begin
    if auth.uid() is null then
        raise exception 'Not authenticated';
    end if;

    select izvajalec into v_izvajalec
      from public.delovni_nalogi
     where id = p_work_order_id and status = 'V delu';

    if v_izvajalec is null then
        raise exception 'Nalog ni v stanju V delu';
    end if;

    select exists(select 1 from public.profiles where id = auth.uid() and role = 'admin') into v_is_admin;

    if v_izvajalec <> auth.uid() and not v_is_admin then
        raise exception 'Samo izvajalec ali administrator lahko sprosti nalog';
    end if;

    update public.delovni_nalogi
       set status = 'Plan', izvajalec = null
     where id = p_work_order_id;
end;
$$;

revoke all on function public.release_work_order(uuid) from public, anon;
grant execute on function public.release_work_order(uuid) to authenticated;
