-- ============================================================
-- WorkTracker — soft-delete a customer, cascading to their fields
-- and work orders (archive, not hard delete — same reversible
-- pattern as work-order soft delete, migration_soft_delete_work_orders.sql)
-- Run in: Supabase Dashboard -> SQL Editor -> New Query
-- ============================================================
--
-- customers/fields currently have SELECT-only RLS for authenticated
-- (no write policy at all), unlike delovni_nalogi which has an admin
-- "FOR ALL" policy that lets softDeleteWorkOrders use a plain
-- .update(). Rather than opening up broad UPDATE policies on two
-- tables, this routes through a narrow SECURITY DEFINER RPC with its
-- own internal admin check — same pattern as set_operator_role_org.
--
-- fields.customer_id and delovni_nalogi.stranka_id have no enforced
-- FK constraints today (confirmed via information_schema), so the
-- cascade is done explicitly here rather than relying on
-- ON DELETE CASCADE.

alter table public.customers add column if not exists deleted_at timestamptz;
alter table public.fields    add column if not exists deleted_at timestamptz;

create or replace function public.soft_delete_customer(p_customer_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
begin
    if not exists (select 1 from public.profiles where id = auth.uid() and role = 'admin') then
        raise exception 'Not authorized';
    end if;

    update public.customers set deleted_at = now() where id = p_customer_id;
    update public.fields set deleted_at = now() where customer_id = p_customer_id;
    update public.delovni_nalogi set deleted_at = now() where stranka_id = p_customer_id;
end;
$$;

create or replace function public.restore_customer(p_customer_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
begin
    if not exists (select 1 from public.profiles where id = auth.uid() and role = 'admin') then
        raise exception 'Not authorized';
    end if;

    update public.customers set deleted_at = null where id = p_customer_id;
    update public.fields set deleted_at = null where customer_id = p_customer_id;
    update public.delovni_nalogi set deleted_at = null where stranka_id = p_customer_id;
end;
$$;

revoke all on function public.soft_delete_customer(uuid) from public, anon;
grant execute on function public.soft_delete_customer(uuid) to authenticated;

revoke all on function public.restore_customer(uuid) from public, anon;
grant execute on function public.restore_customer(uuid) to authenticated;

select pg_notify('pgrst', 'reload schema');
