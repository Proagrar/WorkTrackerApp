-- ============================================================
-- Migration: allow WorkTracker operators to read field/partner data
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================

-- WorkTracker operators are authenticated users.
-- FIELD and B_FIELD_X_CUSTOMER have no RLS enabled yet — enable and allow read.
-- CUSTOMER already has RLS but only for the anon role — add authenticated read.

ALTER TABLE "FIELD" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "authenticated_read" ON "FIELD"
  FOR SELECT TO authenticated USING (true);

ALTER TABLE "B_FIELD_X_CUSTOMER" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "authenticated_read" ON "B_FIELD_X_CUSTOMER"
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "authenticated_read" ON "CUSTOMER"
  FOR SELECT TO authenticated USING (true);
