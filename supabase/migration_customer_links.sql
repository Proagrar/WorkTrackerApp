-- ============================================================
-- WorkTracker — Generalize field_declaration_links into customer_links
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================
--
-- Per Matej: don't make the link/token table single-purpose. Renames
-- field_declaration_links -> customer_links and adds `purpose` (what
-- this link is for) + `description` (human-readable label) so future
-- customer-facing links — e.g. the planned customer card/portal — can
-- reuse this same table instead of each feature growing its own.
--
-- Column note: kept the column named `token` (not `link`) — it's the
-- bare token, not a full URL; the app builds the actual link from it
-- (e.g. deklaracija.html?token=...). Flag if you'd rather store the
-- full URL instead.

alter table if exists public.field_declaration_links rename to customer_links;

alter table public.customer_links
    alter column year drop not null,
    alter column lang drop not null;

alter table public.customer_links
    add column if not exists purpose text,
    add column if not exists description text;

update public.customer_links set purpose = 'field_declarations' where purpose is null;

alter table public.customer_links
    alter column purpose set not null;

alter table public.customer_links
    drop constraint if exists chk_customer_links_field_declarations;

alter table public.customer_links
    add constraint chk_customer_links_field_declarations
    check (purpose <> 'field_declarations' or (year is not null and lang is not null));

create index if not exists idx_customer_links_purpose on public.customer_links (purpose);

-- Relabel the admin policy to match the new table name (idempotent —
-- only renames if it hasn't been renamed already).
do $$
begin
    if exists (
        select 1 from pg_policies
         where schemaname = 'public' and tablename = 'customer_links'
           and policyname = 'Admins can manage declaration links'
    ) then
        alter policy "Admins can manage declaration links" on public.customer_links
            rename to "Admins can manage customer links";
    end if;
end $$;


-- ── Recreate the three RPCs against the renamed/generalized table ──
-- Same signatures as before, so grants from migration_field_declarations.sql
-- carry over unchanged (CREATE OR REPLACE preserves ACLs when the
-- argument list is unchanged) — no new revoke/grant needed.

create or replace function public.create_field_declaration_link(
    p_customer_id     uuid,
    p_year            integer,
    p_lang            text,
    p_expires_in_days integer default 90
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
    v_token text;
begin
    if not exists (select 1 from public.profiles where id = auth.uid() and role = 'admin') then
        raise exception 'Not authorized';
    end if;

    if p_lang not in ('sl', 'hr') then
        raise exception 'lang must be sl or hr';
    end if;

    v_token := replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');

    insert into public.customer_links (token, customer_id, purpose, year, lang, description, created_by, expires_at)
    values (
        v_token, p_customer_id, 'field_declarations', p_year, p_lang,
        'Napoved kultur ' || p_year, auth.uid(),
        case when p_expires_in_days is null then null else now() + (p_expires_in_days || ' days')::interval end
    );

    return v_token;
end;
$$;


create or replace function public.get_field_declaration_form(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    v_link   public.customer_links;
    v_result jsonb;
begin
    select * into v_link
      from public.customer_links
     where token = p_token
       and purpose = 'field_declarations'
       and (expires_at is null or expires_at > now());

    if v_link is null then
        raise exception 'Invalid or expired link';
    end if;

    select jsonb_build_object(
        'customer_name', c.company_name,
        'year', v_link.year,
        'lang', v_link.lang,
        'fields', coalesce((
            select jsonb_agg(jsonb_build_object(
                'field_id', f.id,
                'name', f.name,
                'area_ha', f.area_ha,
                'cadastre_id', f.cadastre_id,
                'crop_current', d.crop_current,
                'crop_next', d.crop_next,
                'green_cover', d.green_cover,
                'straw_stays', d.straw_stays,
                'expected_yield_t_per_ha', d.expected_yield_t_per_ha,
                'organic_fertilizer_used', d.organic_fertilizer_used,
                'organic_fertilizer_type', d.organic_fertilizer_type,
                'organic_fertilizer_amount', d.organic_fertilizer_amount,
                'organic_fertilizer_unit', d.organic_fertilizer_unit
            ) order by f.name)
            from public.fields f
            left join public.field_declarations d
                   on d.field_id = f.id and d.year = v_link.year
           where f.customer_id = v_link.customer_id
        ), '[]'::jsonb)
    ) into v_result
      from public.customers c
     where c.id = v_link.customer_id;

    return v_result;
end;
$$;


create or replace function public.submit_field_declarations(
    p_token text,
    p_declarations jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    v_link public.customer_links;
    v_item jsonb;
begin
    select * into v_link
      from public.customer_links
     where token = p_token
       and purpose = 'field_declarations'
       and (expires_at is null or expires_at > now());

    if v_link is null then
        raise exception 'Invalid or expired link';
    end if;

    for v_item in select * from jsonb_array_elements(p_declarations)
    loop
        -- Defense in depth: only ever touch fields that belong to this
        -- link's customer, regardless of what field_id the client sends.
        if not exists (
            select 1 from public.fields
             where id = (v_item->>'field_id')::uuid
               and customer_id = v_link.customer_id
        ) then
            raise exception 'Field % does not belong to this customer', v_item->>'field_id';
        end if;

        insert into public.field_declarations (
            field_id, customer_id, year,
            crop_current, crop_next, green_cover, straw_stays,
            expected_yield_t_per_ha,
            organic_fertilizer_used, organic_fertilizer_type,
            organic_fertilizer_amount, organic_fertilizer_unit
        )
        values (
            (v_item->>'field_id')::uuid, v_link.customer_id, v_link.year,
            v_item->>'crop_current', v_item->>'crop_next',
            (v_item->>'green_cover')::boolean, (v_item->>'straw_stays')::boolean,
            (v_item->>'expected_yield_t_per_ha')::numeric,
            (v_item->>'organic_fertilizer_used')::boolean, v_item->>'organic_fertilizer_type',
            (v_item->>'organic_fertilizer_amount')::numeric, v_item->>'organic_fertilizer_unit'
        )
        on conflict (field_id, year) do update set
            crop_current = excluded.crop_current,
            crop_next = excluded.crop_next,
            green_cover = excluded.green_cover,
            straw_stays = excluded.straw_stays,
            expected_yield_t_per_ha = excluded.expected_yield_t_per_ha,
            organic_fertilizer_used = excluded.organic_fertilizer_used,
            organic_fertilizer_type = excluded.organic_fertilizer_type,
            organic_fertilizer_amount = excluded.organic_fertilizer_amount,
            organic_fertilizer_unit = excluded.organic_fertilizer_unit;
    end loop;

    update public.customer_links
       set last_used_at = now()
     where token = p_token;
end;
$$;
