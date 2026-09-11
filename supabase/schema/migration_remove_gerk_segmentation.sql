-- ============================================================
-- WorkTracker — Remove an imported KML segmentation from a GERK
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================
--
-- gerk_segment/gerk_segment_point cascade-delete fine when their
-- parent gerk_segmentation is removed. gerk_captured_point does NOT
-- (its segmentation_id/segment_id FKs have no ON DELETE action) —
-- those are real GPS readings an operator took in the field, so a
-- point that got auto-linked to a zone being removed is unlinked
-- (set to null, same as a point captured outside any known boundary)
-- rather than either blocking the delete or losing the reading.

create or replace function public.remove_gerk_segmentation(p_segmentation_id uuid)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $$
#variable_conflict use_column
begin
    if not exists (select 1 from public.profiles where id = auth.uid() and role = 'admin') then
        raise exception 'Not authorized';
    end if;

    update public.gerk_captured_point
       set segmentation_id = null, segment_id = null
     where segmentation_id = p_segmentation_id;

    delete from public.gerk_segmentation where id = p_segmentation_id;
    if not found then
        raise exception 'Segmentacija ne obstaja.';
    end if;
end;
$$;

revoke all on function public.remove_gerk_segmentation(uuid) from public, anon;
grant execute on function public.remove_gerk_segmentation(uuid) to authenticated;

select pg_notify('pgrst', 'reload schema');
