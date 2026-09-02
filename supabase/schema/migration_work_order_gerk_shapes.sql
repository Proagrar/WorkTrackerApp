-- ============================================================
-- WorkTracker — GERK boundary shapes for the work-order detail map
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================
--
-- gerk_polygon has RLS enabled with zero policies (same situation as
-- get_work_order_center_point), so this has to be SECURITY DEFINER to
-- read it — narrowly scoped to return only GeoJSON for the calling
-- work order's own GERKs, never raw table rows. Only numeric-looking
-- gerk_codes are matched (suffixed codes like "1515325-1" are skipped,
-- same reasoning as the center-point RPC) — those GERKs just don't
-- get a shape, the client falls back to a plain marker for them.

create or replace function public.get_work_order_gerk_shapes(p_work_order_id uuid)
returns table (
    gerk_code text,
    geojson   jsonb
)
language plpgsql
security definer
set search_path = public
as $$
begin
    if auth.uid() is null then
        raise exception 'Not authenticated';
    end if;

    return query
    select dng.gerk_code, ST_AsGeoJSON(gp.polygon_points)::jsonb
      from public.delovni_nalogi_gerki dng
      join public.gerk_polygon gp on gp.gerk_id = dng.gerk_code::int
     where dng.delovni_nalog_id = p_work_order_id
       and dng.gerk_code ~ '^[0-9]+$';
end;
$$;

revoke execute on function public.get_work_order_gerk_shapes(uuid) from public, anon;
grant execute on function public.get_work_order_gerk_shapes(uuid) to authenticated;
