-- WorkTracker: bulk segment-count RPC for the Planiranje cards (number of
-- imported KML zones per work order, not the same as GERK count). One
-- round trip for every order instead of one call per card — same batching
-- reasoning as get_work_orders_center_points / get_work_orders_gerk_shapes.

create or replace function public.get_work_orders_segment_counts()
returns table(delovni_nalog_id uuid, segment_count bigint)
language plpgsql
security definer
set search_path to 'public'
as $$
#variable_conflict use_column
begin
    if auth.uid() is null then
        raise exception 'Not authenticated';
    end if;

    return query
    with split_gerks as (
        select dng.delovni_nalog_id, trim(part) as sub_code
          from public.delovni_nalogi_gerki dng,
               unnest(string_to_array(dng.gerk_code, '+')) as part
    )
    select sg.delovni_nalog_id, count(seg.id)
      from split_gerks sg
      join public.gerk_segmentation gs on gs.gerk_id = sg.sub_code
      join public.gerk_segment seg on seg.segmentation_id = gs.id
     group by sg.delovni_nalog_id;
end;
$$;

revoke all on function public.get_work_orders_segment_counts() from public;
revoke all on function public.get_work_orders_segment_counts() from anon;
grant execute on function public.get_work_orders_segment_counts() to authenticated;
