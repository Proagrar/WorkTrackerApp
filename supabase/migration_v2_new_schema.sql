-- ============================================================
-- WorkTracker v2 — Schema migration
-- Run in Supabase Dashboard → SQL Editor
-- WARNING: drops start_time, end_time, gerk_number, location
--          columns. Existing work_logs rows lose that data.
-- ============================================================


-- ── 1. Drop old constraints on work_logs ─────────────────────
ALTER TABLE public.work_logs
  DROP CONSTRAINT IF EXISTS chk_end_time_after_start_time,
  DROP CONSTRAINT IF EXISTS chk_start_time_15_min_interval,
  DROP CONSTRAINT IF EXISTS chk_end_time_15_min_interval;


-- ── 2. Replace columns ────────────────────────────────────────
ALTER TABLE public.work_logs
  DROP COLUMN IF EXISTS start_time,
  DROP COLUMN IF EXISTS end_time,
  DROP COLUMN IF EXISTS gerk_number,
  DROP COLUMN IF EXISTS latitude,
  DROP COLUMN IF EXISTS longitude,
  DROP COLUMN IF EXISTS location_accuracy,
  DROP COLUMN IF EXISTS location_captured_at,
  DROP COLUMN IF EXISTS location_status,
  ADD COLUMN IF NOT EXISTS work_duration  INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS road_duration  INTEGER,
  ADD COLUMN IF NOT EXISTS tractor        TEXT;


-- ── 3. GERK lines per entry ───────────────────────────────────
CREATE TABLE IF NOT EXISTS public.work_log_gerks (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  work_log_id UUID NOT NULL REFERENCES public.work_logs(id) ON DELETE CASCADE,
  gerk_code   TEXT NOT NULL,
  hectares    NUMERIC(10, 4),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.work_log_gerks ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Operators can view own gerks"   ON public.work_log_gerks;
DROP POLICY IF EXISTS "Operators can insert own gerks" ON public.work_log_gerks;
DROP POLICY IF EXISTS "Operators can delete own gerks" ON public.work_log_gerks;

CREATE POLICY "Operators can view own gerks" ON public.work_log_gerks
  FOR SELECT USING (
    work_log_id IN (SELECT id FROM public.work_logs WHERE operator_id = auth.uid())
  );

CREATE POLICY "Operators can insert own gerks" ON public.work_log_gerks
  FOR INSERT WITH CHECK (
    work_log_id IN (SELECT id FROM public.work_logs WHERE operator_id = auth.uid())
  );

CREATE POLICY "Operators can delete own gerks" ON public.work_log_gerks
  FOR DELETE USING (
    work_log_id IN (SELECT id FROM public.work_logs WHERE operator_id = auth.uid())
  );


-- ── 4. Auto-create profile on first OAuth / email sign-in ─────
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, role)
  VALUES (
    NEW.id,
    COALESCE(
      NEW.raw_user_meta_data->>'full_name',
      NEW.raw_user_meta_data->>'name',
      NEW.email
    ),
    'operator'
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();
