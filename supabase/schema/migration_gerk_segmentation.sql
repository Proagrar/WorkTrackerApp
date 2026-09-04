-- ============================================================
-- WorkTracker — GERK segmentation structure (segmentations + segments)
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================
--
-- A GERK can be divided into sub-zones in more than one way over time
-- — e.g. a soil-sampling grid redone each season, or an entirely
-- different segmentation method. gerk_segmentation is one such
-- "definition" (what kind, valid for what period); gerk_segment holds
-- the actual shapes belonging to one definition. The same GERK can
-- have several segmentations, and the shapes under each are entirely
-- independent — a later segmentation (new type, or a re-run of the
-- same type for a new period) can carve the GERK up completely
-- differently from an earlier one.
--
-- Same access model as gerk_polygon / gerk_polygon_ours: rows go in
-- directly via the database (Table Editor / SQL), not through the
-- app. RLS on, no policies — only a direct DB connection (or a future
-- SECURITY DEFINER RPC, if/when this needs to reach the UI) can read
-- or write it.
--
-- gerk_id is left as a plain integer with no FK to gerk_lastnost /
-- gerk_polygon — same reasoning as delovni_nalogi_gerki.gerk_code: a
-- segmentation should be insertable even for a GERK not yet in the
-- official registry. type is free text rather than a lookup table —
-- no fixed set of segmentation types exists yet, and this keeps a
-- direct-in-database insert a single statement.

create table public.gerk_segmentation (
    id         uuid primary key default gen_random_uuid(),
    gerk_id    integer not null,
    type       text not null,
    valid_from date not null,
    valid_to   date,                    -- null = still current / open-ended
    notes      text,
    created_at timestamptz not null default now(),
    check (valid_to is null or valid_to >= valid_from)
);

create index gerk_segmentation_gerk_id_idx      on public.gerk_segmentation (gerk_id);
create index gerk_segmentation_gerk_id_type_idx on public.gerk_segmentation (gerk_id, type);

alter table public.gerk_segmentation enable row level security;

create table public.gerk_segment (
    id              uuid primary key default gen_random_uuid(),
    segmentation_id uuid not null references public.gerk_segmentation(id) on delete cascade,
    label           text,                        -- identifies the piece within its segmentation, e.g. "1", "sever"
    polygon_points  geometry(MultiPolygon, 4326) not null,
    area_ha         numeric generated always as (ST_Area(polygon_points::geography) / 10000) stored,
    created_at      timestamptz not null default now()
);

create index gerk_segment_segmentation_id_idx on public.gerk_segment (segmentation_id);

alter table public.gerk_segment enable row level security;
