-- ============================================================
-- WorkTracker — Real FK: fields → gerk_lastnost
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================
--
-- gerk_lastnost already has a real primary key on gerk_id (and its
-- own FK to gerk_polygon), so this references it directly — no new
-- constraint needed on that side. Match rate verified beforehand:
-- fields.cadastre_id cast to int against gerk_lastnost.gerk_id —
-- 4,710 of 4,878 numeric-coded fields (96.6%, same rate as the
-- earlier GERK_POLYGON centroid work — same underlying GERK_ID
-- universe). Nullable: suffixed codes (xxx-1/xxx-2) and any code
-- gerk_lastnost doesn't have won't match, same as centroid_lat/lng.

alter table public.fields
    add column if not exists gerk_lastnost_id integer references public.gerk_lastnost(gerk_id);

create index if not exists idx_fields_gerk_lastnost_id on public.fields (gerk_lastnost_id);
