-- ============================================================
-- WorkTracker — Operator management
-- Run this AFTER schema.sql in Supabase SQL Editor
-- ============================================================

-- Required for crypt() and gen_salt()
create extension if not exists pgcrypto schema extensions;


-- ── 1. Auto-create profile on user insert ─────────────────────
-- Fires every time a new row lands in auth.users.
-- Pulls full_name from raw_user_meta_data if provided.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    insert into public.profiles (id, full_name, role)
    values (
        new.id,
        coalesce(new.raw_user_meta_data->>'full_name', new.email),
        'operator'
    )
    on conflict (id) do nothing;
    return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
    after insert on auth.users
    for each row execute function public.handle_new_user();


-- ── 2. Helper function: create a new operator ─────────────────
-- Creates the auth user + profile in one call.
-- Returns the new user's UUID.
--
-- Usage:
--   select public.create_operator('janez@proagrar.si', 'geslo123', 'Janez Novak');
--
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
    insert into auth.users (
        instance_id,
        id,
        aud,
        role,
        email,
        encrypted_password,
        email_confirmed_at,
        raw_app_meta_data,
        raw_user_meta_data,
        is_sso_user,
        is_anonymous,
        created_at,
        updated_at,
        confirmation_token,
        email_change,
        email_change_token_new,
        recovery_token
    )
    values (
        '00000000-0000-0000-0000-000000000000',
        v_user_id,
        'authenticated',
        'authenticated',
        p_email,
        crypt(p_password, gen_salt('bf')),
        now(),
        '{"provider":"email","providers":["email"]}'::jsonb,
        json_build_object('full_name', p_full_name)::jsonb,
        false,
        false,
        now(),
        now(),
        '', '', '', ''
    );

    -- Required: Supabase resolves email sign-in via auth.identities,
    -- not auth.users alone. Without this row, signInWithPassword fails.
    insert into auth.identities (
        id,
        user_id,
        provider_id,
        identity_data,
        provider,
        last_sign_in_at,
        created_at,
        updated_at
    )
    values (
        v_user_id,
        v_user_id,
        p_email,
        json_build_object('sub', v_user_id::text, 'email', p_email)::jsonb,
        'email',
        now(),
        now(),
        now()
    );

    -- Profile is created automatically by the handle_new_user trigger.
    -- This explicit upsert ensures full_name is always set correctly.
    insert into public.profiles (id, full_name, role)
    values (v_user_id, p_full_name, 'operator')
    on conflict (id) do update set full_name = excluded.full_name;

    return v_user_id;
end;
$$;


-- ── 3. Helper function: change operator password ──────────────
-- Usage:
--   select public.set_operator_password('janez@proagrar.si', 'novogeslo456');
--
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
    update auth.users
    set
        encrypted_password = crypt(p_password, gen_salt('bf')),
        updated_at         = now()
    where email = p_email;

    if not found then
        raise exception 'Operator with email % not found', p_email;
    end if;
end;
$$;


-- ── 4. Helper function: delete an operator ────────────────────
-- Cascades to work_logs and profiles automatically.
-- Usage:
--   select public.delete_operator('janez@proagrar.si');
--
create or replace function public.delete_operator(p_email text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    delete from auth.users where email = p_email;

    if not found then
        raise exception 'Operator with email % not found', p_email;
    end if;
end;
$$;


-- ── 5. View: list all operators ───────────────────────────────
-- Quick overview without exposing password hashes.
create or replace view public.operators_view as
select
    u.id,
    u.email,
    p.full_name,
    p.role,
    u.last_sign_in_at,
    u.created_at
from auth.users u
left join public.profiles p on p.id = u.id
order by u.created_at;


-- ── Examples ──────────────────────────────────────────────────

-- Create operators:
--   select public.create_operator('janez@proagrar.si',  'geslo123', 'Janez Novak');
--   select public.create_operator('mojca@proagrar.si',  'geslo456', 'Mojca Kovač');
--   select public.create_operator('peter@proagrar.si',  'geslo789', 'Peter Horvat');

-- Change a password:
--   select public.set_operator_password('janez@proagrar.si', 'novogeslo');

-- Delete an operator:
--   select public.delete_operator('janez@proagrar.si');

-- List all operators:
--   select * from public.operators_view;
