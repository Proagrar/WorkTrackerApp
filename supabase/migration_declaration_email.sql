-- ============================================================
-- WorkTracker — Email a customer their field-declaration link
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================
--
-- Sends via Resend's HTTP API directly from Postgres using `pg_net`
-- (already installed and already used this way by
-- notify_mailerlite_on_customer_change) — not a Supabase Edge Function,
-- and not the SMTP config used for Auth emails. Supabase Auth's SMTP
-- settings (Project Settings → Auth) are wired into Supabase's own
-- auth-email templates only; there's no way to reuse that config to
-- send arbitrary custom emails from app code. Resend is still the same
-- underlying provider/account, just called via its REST API instead.
--
-- ⚠️ Before this works you must, once, in the SQL Editor:
--   select vault.create_secret('re_your_resend_api_key', 'resend_api_key');
-- (Vault is already installed on this project.) The key itself never
-- goes in this file or in git — only the secret's *name* is referenced
-- below. Get a Resend API key from https://resend.com/api-keys — it can
-- be the same account used for the Auth SMTP setup.
--
-- Sender: info@proagrar.si (confirmed by Matej 2026-07-31, verified domain in Resend).

alter table public.customer_links
    add column if not exists email_sent_at timestamptz;

create or replace function public.send_field_declaration_email(p_token text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    v_link     public.customer_links;
    v_customer public.customers;
    v_api_key  text;
    v_url      text;
    v_subject  text;
    v_html     text;
    v_name     text;
begin
    if not exists (select 1 from public.profiles where id = auth.uid() and role = 'admin') then
        raise exception 'Not authorized';
    end if;

    select * into v_link
      from public.customer_links
     where token = p_token and purpose = 'field_declarations';

    if v_link is null then
        raise exception 'Link not found';
    end if;

    select * into v_customer from public.customers where id = v_link.customer_id;

    if v_customer.email is null or btrim(v_customer.email) = '' then
        raise exception 'Customer has no email on file';
    end if;

    select decrypted_secret into v_api_key
      from vault.decrypted_secrets
     where name = 'resend_api_key';

    if v_api_key is null then
        raise exception 'resend_api_key not configured in Vault';
    end if;

    v_url  := 'https://app.proagrar.si/deklaracija.html?token=' || p_token;
    v_name := replace(replace(coalesce(v_customer.contact_name, v_customer.company_name, ''), '&', '&amp;'), '<', '&lt;');

    if v_link.lang = 'hr' then
        v_subject := 'Prijava kultura ' || v_link.year || ' — Proagrar';
        v_html := '<p>Poštovani ' || v_name || ',</p>'
               || '<p>Molimo ispunite podatke o kulturama za ' || v_link.year || '. godinu putem sljedeće poveznice:</p>'
               || '<p><a href="' || v_url || '">' || v_url || '</a></p>'
               || '<p>Hvala na suradnji.<br>Proagrar</p>';
    else
        v_subject := 'Napoved kultur ' || v_link.year || ' — Proagrar';
        v_html := '<p>Pozdravljeni ' || v_name || ',</p>'
               || '<p>Prosimo, izpolnite podatke o kulturah za leto ' || v_link.year || ' preko spodnje povezave:</p>'
               || '<p><a href="' || v_url || '">' || v_url || '</a></p>'
               || '<p>Hvala za sodelovanje.<br>Proagrar</p>';
    end if;

    perform net.http_post(
        url     := 'https://api.resend.com/emails',
        headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_api_key),
        body    := jsonb_build_object(
            'from', 'Proagrar <info@proagrar.si>',
            'to', jsonb_build_array(v_customer.email),
            'subject', v_subject,
            'html', v_html
        )
    );

    update public.customer_links set email_sent_at = now() where token = p_token;
end;
$$;

revoke execute on function public.send_field_declaration_email(text) from public, anon, authenticated;
grant execute on function public.send_field_declaration_email(text) to authenticated;
