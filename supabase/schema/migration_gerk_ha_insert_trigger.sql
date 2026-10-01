-- Same gap as the KML-import one (migration_import_gerk_segmentation_ha_backfill.sql),
-- different cause: a GERK added via the official registry -- a plain
-- single code that matches gerk_polygon but was never linked through
-- fields/field_id, or a compound "A+B+C" code (see
-- get_work_order_gerk_shapes) -- never gets kolicina_ha filled in at
-- all. There's no single chokepoint function for "insert a GERK line"
-- the way import_gerk_segmentation is for KML imports -- app.js inserts
-- delovni_nalogi_gerki rows from several different places -- so the only
-- way to guarantee this "every time" is a DB trigger, not another
-- client-side patch.
--
-- Only ever fills in a NULL kolicina_ha, never overwrites an existing
-- value (manually entered, registry-matched via fields.area_ha at
-- insert time, or already set by some other path). Checks already-
-- imported KML segmentation first (most precise, an actual
-- surveyed/drawn boundary), then falls back to the official registry,
-- summing each sub-code's polygon area so a compound code adds up
-- correctly, country-aware (SI/HR) via the order's customer -- same
-- logic as get_work_order_gerk_shapes/get_work_order_center_point.

create or replace function public.backfill_gerk_kolicina_ha()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
    v_drzava   text;
    v_total_ha numeric;
begin
    if new.kolicina_ha is not null then
        return new;
    end if;

    -- 1. Prefer already-imported KML zone geometry for this exact code.
    select sum(seg.area_ha) into v_total_ha
      from public.gerk_segmentation gs
      join public.gerk_segment seg on seg.segmentation_id = gs.id
     where gs.gerk_id = new.gerk_code;

    if v_total_ha > 0 then
        new.kolicina_ha := v_total_ha;
        return new;
    end if;

    -- 2. Fall back to the official registry.
    select case when upper(trim(cu.country)) in ('HRVAŠKA', 'HRVATSKA') then 'HR' else 'SI' end
      into v_drzava
      from public.delovni_nalogi dn
      left join public.customers cu on cu.id = dn.stranka_id
     where dn.id = new.delovni_nalog_id;
    v_drzava := coalesce(v_drzava, 'SI');

    with numeric_subcodes as (
        select trim(part)::int as gerk_int
          from unnest(string_to_array(new.gerk_code, '+')) as part
         where trim(part) ~ '^[0-9]+$'
    )
    select sum(ST_Area(coalesce(gpo.polygon_points, gp.polygon_points)::geography) / 10000)
      into v_total_ha
      from numeric_subcodes ns
      left join public.gerk_polygon_ours gpo on gpo.gerk_id = ns.gerk_int
      left join public.gerk_polygon gp on gp.gerk_id = ns.gerk_int and gp.drzava = v_drzava
     where coalesce(gpo.polygon_points, gp.polygon_points) is not null;

    if v_total_ha > 0 then
        new.kolicina_ha := v_total_ha;
    end if;

    return new;
end;
$function$;

drop trigger if exists trg_backfill_gerk_kolicina_ha on public.delovni_nalogi_gerki;
create trigger trg_backfill_gerk_kolicina_ha
before insert on public.delovni_nalogi_gerki
for each row
execute function public.backfill_gerk_kolicina_ha();
