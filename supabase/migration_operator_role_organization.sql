-- ============================================================
-- WorkTracker — set role (admin/supervisor/operator) + organization
-- when creating a user, and let admin change either for existing users
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================
--
-- profiles has no admin-bypass UPDATE policy (only "update own
-- profile"), so changing someone ELSE's role/organization has to go
-- through a SECURITY DEFINER RPC with its own internal admin check —
-- same pattern as set_operator_eligibility.

create or replace function public.set_operator_role_org(
    p_profile_id   uuid,
    p_role         text,
    p_organization text default null
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
begin
    if not exists (select 1 from public.profiles where id = auth.uid() and role = 'admin') then
        raise exception 'Not authorized';
    end if;

    if p_role not in ('admin', 'supervisor', 'operator') then
        raise exception 'Neveljavna vloga';
    end if;

    if p_role = 'supervisor' and coalesce(trim(p_organization), '') = '' then
        raise exception 'Srednji nivo (vodja) mora imeti določeno organizacijo';
    end if;

    update public.profiles
       set role = p_role,
           organization = case when p_role = 'admin' then null else nullif(trim(p_organization), '') end
     where id = p_profile_id;
end;
$$;

revoke all on function public.set_operator_role_org(uuid, text, text) from public, anon;
grant execute on function public.set_operator_role_org(uuid, text, text) to authenticated;


-- create_operator previously always hardcoded role='operator' with no
-- organization — extending it, same admin check as before.
create or replace function public.create_operator(
    p_email        text,
    p_password     text,
    p_full_name    text,
    p_role         text default 'operator',
    p_organization text default null
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

    if p_role not in ('admin', 'supervisor', 'operator') then
        raise exception 'Neveljavna vloga';
    end if;

    if p_role = 'supervisor' and coalesce(trim(p_organization), '') = '' then
        raise exception 'Srednji nivo (vodja) mora imeti določeno organizacijo';
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

    insert into public.profiles (id, full_name, role, organization)
    values (
        v_user_id, p_full_name, p_role,
        case when p_role = 'admin' then null else nullif(trim(p_organization), '') end
    )
    on conflict (id) do update
        set full_name = excluded.full_name,
            role = excluded.role,
            organization = excluded.organization;

    return v_user_id;
end;
$$;

revoke all on function public.create_operator(text, text, text, text, text) from public, anon;
grant execute on function public.create_operator(text, text, text, text, text) to authenticated;

-- The old 3-arg signature is a separate overload in Postgres — drop it
-- so the app can't accidentally call the version with no role/org.
drop function if exists public.create_operator(text, text, text);

select pg_notify('pgrst', 'reload schema');
