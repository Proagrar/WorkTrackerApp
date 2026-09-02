-- ============================================================
-- WorkTracker — Capture GPS location per sample (segment)
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================
--
-- delovni_nalogi_vzorci is currently admin-write-only ("Admins can
-- manage samples"), but capturing the exact spot a sample was taken
-- is a field-operator action, not an admin desk-editing one. Rather
-- than widen table-level UPDATE access (which would also open every
-- other sample field — sampling_date, depth, etc. — to non-admins),
-- this is a narrow SECURITY DEFINER RPC that only ever touches
-- lat/lng, on the same set of samples the existing view policy
-- ("Authenticated users can view samples of open work orders")
-- already lets a non-admin see — same pattern as start_gerk/end_gerk.

alter table public.delovni_nalogi_vzorci
    add column if not exists lat double precision,
    add column if not exists lng double precision;

create or replace function public.capture_sample_location(
    p_sample_id uuid,
    p_lat       double precision,
    p_lng       double precision
)
returns table (id uuid, lat double precision, lng double precision)
language plpgsql
security definer
set search_path = public
as $$
begin
    if auth.uid() is null then
        raise exception 'Not authenticated';
    end if;

    if p_lat is null or p_lng is null or p_lat < -90 or p_lat > 90 or p_lng < -180 or p_lng > 180 then
        raise exception 'Neveljavne koordinate';
    end if;

    if not exists (
        select 1
          from public.delovni_nalogi_vzorci v
          join public.delovni_nalogi_gerki g on g.id = v.delovni_nalog_gerk_id
          join public.delovni_nalogi dn on dn.id = g.delovni_nalog_id
         where v.id = p_sample_id
           and dn.status = any (array['Plan', 'V delu'])
    ) then
        raise exception 'Vzorec ne obstaja ali ni več na voljo za urejanje';
    end if;

    update public.delovni_nalogi_vzorci
       set lat = p_lat, lng = p_lng
     where delovni_nalogi_vzorci.id = p_sample_id;

    return query select v.id, v.lat, v.lng from public.delovni_nalogi_vzorci v where v.id = p_sample_id;
end;
$$;

revoke execute on function public.capture_sample_location(uuid, double precision, double precision) from public, anon;
grant execute on function public.capture_sample_location(uuid, double precision, double precision) to authenticated;
