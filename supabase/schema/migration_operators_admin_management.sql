-- ============================================================
-- WorkTracker — expose user management (add/delete/reset password)
-- through the Izvajalci panel, admin-only
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================
--
-- create_operator/set_operator_password/delete_operator already exist
-- but were deliberately locked to SQL-Editor-only use (no internal
-- auth check, revoked from anon+authenticated) — see operators.sql.
-- Adding the same internal admin check every other admin RPC in this
-- project already uses, then granting execute to authenticated (never
-- to anon — see feedback_supabase_function_grants memory) makes it
-- safe to call from the app.
--
-- delete_operator also gets a new safety guard: it previously cascaded
-- straight through to work_logs (deleting a user deleted all their
-- logged hours with it) with nothing stopping that. Fine when this was
-- a manual SQL-Editor-only action; too easy to trigger by accident
-- from a UI button. Now refuses if the user has any logged work.
--
-- get_operators_with_email gains role + organization columns for the
-- admin list view (dropped and recreated — Postgres won't let
-- CREATE OR REPLACE change a function's output columns).

drop function if exists public.get_operators_with_email();

create function public.get_operators_with_email()
returns table(id uuid, full_name text, eligible_izvajalec boolean, email text, role text, organization text)
language plpgsql
security definer
set search_path to 'public'
as $$
#variable_conflict use_column
begin
    if not exists (select 1 from public.profiles where id = auth.uid() and role = 'admin') then
        raise exception 'Not authorized';
    end if;

    return query
    select p.id, p.full_name, p.eligible_izvajalec, u.email::text, p.role, p.organization
      from public.profiles p
      join auth.users u on u.id = p.id
     order by p.full_name;
end;
$$;

revoke all on function public.get_operators_with_email() from public, anon;
grant execute on function public.get_operators_with_email() to authenticated;


create or replace function public.create_operator(
    p_email     text,
    p_password  text,
    p_full_name text
)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
    v_user_id uuid := gen_random_uuid();
begin
    if not exists (select 1 from public.profiles where id = auth.uid() and role = 'admin') then
        raise exception 'Not authorized';
    end if;

    insert into auth.users (
        instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
        raw_app_meta_data, raw_user_meta_data, is_sso_user, is_anonymous,
        created_at, updated_at, confirmation_token, email_change, email_change_token_new, recovery_token
    )
    values (
        '00000000-0000-0000-0000-000000000000', v_user_id, 'authenticated', 'authenticated',
        p_email, crypt(p_password, gen_salt('bf')), now(),
        '{"provider":"email","providers":["email"]}'::jsonb,
        json_build_object('full_name', p_full_name)::jsonb,
        false, false, now(), now(), '', '', '', ''
    );

    insert into auth.identities (
        id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at
    )
    values (
        v_user_id, v_user_id, p_email,
        json_build_object('sub', v_user_id::text, 'email', p_email)::jsonb,
        'email', now(), now(), now()
    );

    insert into public.profiles (id, full_name, role)
    values (v_user_id, p_full_name, 'operator')
    on conflict (id) do update set full_name = excluded.full_name;

    return v_user_id;
end;
$$;

revoke all on function public.create_operator(text, text, text) from public, anon;
grant execute on function public.create_operator(text, text, text) to authenticated;


create or replace function public.set_operator_password(
    p_email    text,
    p_password text
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
    if not exists (select 1 from public.profiles where id = auth.uid() and role = 'admin') then
        raise exception 'Not authorized';
    end if;

    update auth.users
       set encrypted_password = crypt(p_password, gen_salt('bf')),
           updated_at         = now()
     where email = p_email;

    if not found then
        raise exception 'Operator with email % not found', p_email;
    end if;
end;
$$;

revoke all on function public.set_operator_password(text, text) from public, anon;
grant execute on function public.set_operator_password(text, text) to authenticated;


create or replace function public.delete_operator(p_email text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    v_user_id uuid;
begin
    if not exists (select 1 from public.profiles where id = auth.uid() and role = 'admin') then
        raise exception 'Not authorized';
    end if;

    select id into v_user_id from auth.users where email = p_email;
    if v_user_id is null then
        raise exception 'Operator with email % not found', p_email;
    end if;

    if exists (select 1 from public.work_logs where operator_id = v_user_id) then
        raise exception 'Ni mogoče izbrisati — uporabnik ima zabeležene ure dela.';
    end if;

    delete from auth.users where id = v_user_id;
end;
$$;

revoke all on function public.delete_operator(text) from public, anon;
grant execute on function public.delete_operator(text) to authenticated;

select pg_notify('pgrst', 'reload schema');
