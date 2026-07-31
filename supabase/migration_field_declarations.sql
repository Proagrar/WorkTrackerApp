-- ============================================================
-- WorkTracker — Customer field declarations (crop rotation form)
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================
--
-- Source: SampleDocs/TABELA KULTURE TEMPLATE - SLO.xlsx and - HRVAŠKA.xlsx.
-- Columns A-C (GERK/ARKOD code, area, field name) are just `fields` data,
-- already in the DB. Columns E-L (SLO) / D-K (HR) are the actual customer
-- input, unified into one schema here (the two templates' columns line up
-- 1:1 once "VZORČENJE" — soil sampling, SLO-only — is dropped per Matej,
-- and the straw/yield wording is reconciled — see column comments below).
--
-- Access model: no customer login. Each customer gets a unique link
-- (public.field_declaration_links.token) covering one year for all their
-- fields; the two RPCs below are the only way anon reaches this data —
-- there are no anon/authenticated RLS policies on the tables themselves.
--
-- Language: customers.country is free-text and inconsistent in practice
-- ("Hrvatska", "Hrvatska " with a trailing space, "Hrvaška", "SLO",
-- "Slovenija", "BIH"/"BiH" — a third country, not just SLO/HR). Rather
-- than guess a customer's language from that column, whoever generates
-- the link (via create_field_declaration_link) picks 'sl' or 'hr'
-- explicitly. Revisit if BiH customers need their own third variant.


-- ── 1. Table: one row per field per year ─────────────────────
create table if not exists public.field_declarations (
    id              uuid primary key default gen_random_uuid(),

    field_id        uuid not null references public.fields(id) on delete cascade,
    customer_id     uuid not null references public.customers(id) on delete cascade,
    year            integer not null check (year between 2000 and 2100),

    crop_current    text,     -- KULTURA <year>
    crop_next       text,     -- KULTURA <year + 1>

    green_cover     boolean,  -- ZELENA GNOJIDBA / OZELENITEV DA/NE
    straw_stays     boolean,  -- unified wording: "straw stays on the field" (HR template asked the opposite direction — reconciled per Matej)

    expected_yield_t_per_ha numeric(8, 2),  -- unified unit: T/ha (HR template was total T for the field — reconciled per Matej)

    organic_fertilizer_used   boolean,
    organic_fertilizer_type   text,
    organic_fertilizer_amount numeric(8, 2),
    organic_fertilizer_unit   text check (organic_fertilizer_unit in ('t/ha', 'm3/ha')),

    submitted_at    timestamptz not null default now(),
    updated_at      timestamptz not null default now(),

    constraint uq_field_declarations_field_year unique (field_id, year)
);

create index if not exists idx_field_declarations_customer_id on public.field_declarations (customer_id);
create index if not exists idx_field_declarations_field_id    on public.field_declarations (field_id);

drop trigger if exists trg_field_declarations_updated_at on public.field_declarations;
create trigger trg_field_declarations_updated_at
before update on public.field_declarations
for each row execute function public.set_updated_at();

alter table public.field_declarations enable row level security;

drop policy if exists "Admins can manage field declarations" on public.field_declarations;
create policy "Admins can manage field declarations"
    on public.field_declarations for all
    using (
        exists (select 1 from public.profiles where id = auth.uid() and role = 'admin')
    )
    with check (
        exists (select 1 from public.profiles where id = auth.uid() and role = 'admin')
    );
-- No anon/authenticated policy on purpose — the public form only ever
-- reaches this table through the SECURITY DEFINER RPCs below.


-- ── 2. Table: per-customer, per-year access links ────────────
create table if not exists public.field_declaration_links (
    token         text primary key,
    customer_id   uuid not null references public.customers(id) on delete cascade,
    year          integer not null check (year between 2000 and 2100),
    lang          text not null check (lang in ('sl', 'hr')),

    created_at    timestamptz not null default now(),
    created_by    uuid references public.profiles(id) on delete set null,
    expires_at    timestamptz,
    last_used_at  timestamptz
);

create index if not exists idx_field_declaration_links_customer_id on public.field_declaration_links (customer_id);

alter table public.field_declaration_links enable row level security;

drop policy if exists "Admins can manage declaration links" on public.field_declaration_links;
create policy "Admins can manage declaration links"
    on public.field_declaration_links for all
    using (
        exists (select 1 from public.profiles where id = auth.uid() and role = 'admin')
    )
    with check (
        exists (select 1 from public.profiles where id = auth.uid() and role = 'admin')
    );


-- ── 3. create_field_declaration_link — admin-only, generates a token ──
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

    insert into public.field_declaration_links (token, customer_id, year, lang, created_by, expires_at)
    values (
        v_token, p_customer_id, p_year, p_lang, auth.uid(),
        case when p_expires_in_days is null then null else now() + (p_expires_in_days || ' days')::interval end
    );

    return v_token;
end;
$$;


-- ── 4. get_field_declaration_form — one round trip to load the form ──
create or replace function public.get_field_declaration_form(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    v_link  public.field_declaration_links;
    v_result jsonb;
begin
    select * into v_link
      from public.field_declaration_links
     where token = p_token
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


-- ── 5. submit_field_declarations — one round trip to save the whole form ──
create or replace function public.submit_field_declarations(
    p_token text,
    p_declarations jsonb   -- array of the per-field objects shaped like get_field_declaration_form returns
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    v_link public.field_declaration_links;
    v_item jsonb;
begin
    select * into v_link
      from public.field_declaration_links
     where token = p_token
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

    update public.field_declaration_links
       set last_used_at = now()
     where token = p_token;
end;
$$;


-- ── 6. Grants ─────────────────────────────────────────────────
-- Supabase grants EXECUTE directly to anon/authenticated/service_role on
-- new functions (not via PUBLIC) — revoking from PUBLIC alone is a no-op
-- here. Must revoke from anon/authenticated by name, then grant back only
-- what each function actually needs. (Same lesson as create_operator et
-- al. and start_work_order — see docs/PROJECT_SNAPSHOT.md.)
revoke execute on function public.create_field_declaration_link(uuid, integer, text, integer) from public, anon, authenticated;
revoke execute on function public.get_field_declaration_form(text) from public, anon, authenticated;
revoke execute on function public.submit_field_declarations(text, jsonb) from public, anon, authenticated;

-- Admin-only (called from the logged-in operator/admin app).
grant execute on function public.create_field_declaration_link(uuid, integer, text, integer) to authenticated;

-- Public form — no login, so anon must be able to call these two. The
-- token is the only gate; both functions validate it before touching data.
grant execute on function public.get_field_declaration_form(text) to anon;
grant execute on function public.submit_field_declarations(text, jsonb) to anon;
