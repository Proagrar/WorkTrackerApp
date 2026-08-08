-- ============================================================
-- WorkTracker — Tip LAB analize (gerk/field level) + a visibility gap
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================
--
-- tip_lab_analize: "basic" or "micro elements", one per GERK-on-this-
-- work-order (not per segment — a GERK can have several segments/
-- samples, but only one analysis type covering all of them). Admin-
-- write via the existing "Admins can manage work order fields" ALL
-- policy — no new policy needed for that part.
--
-- Separately: delovni_nalogi_gerki's only non-admin SELECT policy is
-- still scoped to status Plan/V delu — a leftover gap from widening
-- delovni_nalogi itself to all statuses a few migrations back. That
-- fix made a closed work order visible in the list, but its GERK/
-- segment list would still come back empty for non-admins opening it,
-- since this child table's own RLS never got the same treatment.
-- Same fix, same reasoning: one additional permissive policy so
-- Postgres OR's it with the existing one, nothing removed.

alter table public.delovni_nalogi_gerki
    add column if not exists tip_lab_analize text
        check (tip_lab_analize is null or tip_lab_analize in ('basic', 'micro elements'));

create policy "Authenticated users can view all work order fields"
    on public.delovni_nalogi_gerki for select
    to authenticated
    using (true);
