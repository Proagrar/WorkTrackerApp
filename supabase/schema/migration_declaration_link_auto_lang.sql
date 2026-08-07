-- ============================================================
-- WorkTracker — Derive declaration-link language from customer country
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================
--
-- Per Matej: language should follow customers.country instead of being
-- picked manually per link. Live data for `country` is messy free text
-- ("Hrvatska", "Hrvatska " w/ trailing space, "Hrvaška", "SLO",
-- "Slovenija", "BIH"/"BiH"), so this matches loosely (substring, case-
-- insensitive) rather than exact values. Bosnia ("bosn"/"bih") maps to
-- 'hr' — there's no third language pack, and Croatian is the closer of
-- the two to Bosnian; revisit if that's wrong for how BiH customers are
-- actually communicated with. Anything unrecognized/blank defaults to
-- 'sl' (matches customers.country's own default of 'Slovenia').
--
-- Signature changes (drops p_lang) — must drop the old function first,
-- CREATE OR REPLACE won't do it since the argument list is different.

drop function if exists public.create_field_declaration_link(uuid, integer, text, integer);

create or replace function public.create_field_declaration_link(
    p_customer_id     uuid,
    p_year            integer,
    p_expires_in_days integer default 90
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
    v_token   text;
    v_country text;
    v_lang    text;
begin
    if not exists (select 1 from public.profiles where id = auth.uid() and role = 'admin') then
        raise exception 'Not authorized';
    end if;

    select lower(btrim(coalesce(country, ''))) into v_country
      from public.customers
     where id = p_customer_id;

    v_lang := case
        when v_country like '%hrva%' or v_country like '%croat%'
          or v_country like '%bosn%' or v_country = 'bih' or v_country = 'bh'
            then 'hr'
        else 'sl'
    end;

    v_token := replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');

    insert into public.customer_links (token, customer_id, purpose, year, lang, description, created_by, expires_at)
    values (
        v_token, p_customer_id, 'field_declarations', p_year, v_lang,
        'Napoved kultur ' || p_year, auth.uid(),
        case when p_expires_in_days is null then null else now() + (p_expires_in_days || ' days')::interval end
    );

    return v_token;
end;
$$;

revoke execute on function public.create_field_declaration_link(uuid, integer, integer) from public, anon, authenticated;
grant execute on function public.create_field_declaration_link(uuid, integer, integer) to authenticated;
