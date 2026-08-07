-- ============================================================
-- WorkTracker — Allow logged-in users to also open declaration links
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================
--
-- Bug: get_field_declaration_form/submit_field_declarations were only
-- granted to anon. Supabase's JS client auto-attaches the current
-- session's JWT to every request on the origin — so opening a
-- deklaracija.html link in the SAME browser where an admin is logged
-- into app.html sends the request as `authenticated`, not `anon`, and
-- gets rejected (403). A real customer with no session hits it as
-- anon and it works — which is why this only shows up when testing
-- while logged in.
--
-- Fix: grant authenticated too. Safe — both functions are gated by the
-- token itself, not by role; there's no reason a logged-in admin
-- shouldn't also be able to open/use the same public link.

grant execute on function public.get_field_declaration_form(text) to authenticated;
grant execute on function public.submit_field_declarations(text, jsonb) to authenticated;
