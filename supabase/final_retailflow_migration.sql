-- Final RetailFlow safe database migration
-- Purpose:
--   Upgrade the existing live Supabase database to the final RetailFlow architecture
--   without recreating existing tables, destroying data, or reintroducing banned
--   competition or automated task-generation features.
--
-- IMPORTANT:
--   - This is a migration, not a full setup script.
--   - It must be safe to run against an existing database with current data.
--   - It only adds missing final-state objects and removes stale competition/automation artifacts.

BEGIN;

-- -----------------------------------------------------------------------------
-- 0) Safety helpers
-- -----------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- -----------------------------------------------------------------------------
-- 1) Remove stale competition objects only if they exist
-- -----------------------------------------------------------------------------
-- Remove stale competition data tables and supporting functions. Do not touch
-- points/badges/task reward logic.
DO $$
DECLARE
  rec record;
BEGIN
  -- Drop competition-related table objects if present.
  DROP TABLE IF EXISTS public.branch_leaderboard_entries CASCADE;
  DROP TABLE IF EXISTS public.competition_products CASCADE;
  DROP TABLE IF EXISTS public.competition_branches CASCADE;
  DROP TABLE IF EXISTS public.competitions CASCADE;

  -- Drop competition / leaderboard-related functions if present.
  FOR rec IN
    SELECT p.oid, p.proname
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND (
        p.proname ILIKE '%competition%' OR
        p.proname ILIKE '%leaderboard%' OR
        p.proname ILIKE '%ranking%'
      )
  LOOP
    EXECUTE format(
      'DROP FUNCTION IF EXISTS public.%I(%s);',
      rec.proname,
      pg_get_function_identity_arguments(rec.oid)
    );
  END LOOP;
END $$;

-- Remove stale cron jobs for competition/leaderboard automation, if pg_cron is enabled.
-- This is intentionally guarded because cron.job is a privileged catalog table in many
-- Supabase environments and may be inaccessible to the current role.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    BEGIN
      DELETE FROM cron.job
      WHERE jobname ILIKE '%competition%'
         OR jobname ILIKE '%leaderboard%'
         OR jobname ILIKE '%ranking%';
    EXCEPTION WHEN insufficient_privilege THEN
      RAISE NOTICE 'Skipping competition cron cleanup: insufficient privileges for cron.job';
    END;
  END IF;
END $$;

-- -----------------------------------------------------------------------------
-- 2) Remove stale task automation database objects only if they exist
-- -----------------------------------------------------------------------------
-- Do NOT remove tasks, task_assignments, task_completions, or points system.
DO $$
DECLARE
  rec record;
BEGIN
  FOR rec IN
    SELECT p.oid, p.proname
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND (
        p.proname ILIKE '%task%' AND (
          p.proname ILIKE '%automation%' OR
          p.proname ILIKE '%generate%' OR
          p.proname ILIKE '%scheduler%' OR
          p.proname ILIKE '%schedule%' OR
          p.proname ILIKE '%recurr%' OR
          p.proname ILIKE '%cron%'
        )
      )
  LOOP
    EXECUTE format(
      'DROP FUNCTION IF EXISTS public.%I(%s);',
      rec.proname,
      pg_get_function_identity_arguments(rec.oid)
    );
  END LOOP;
END $$;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    BEGIN
      DELETE FROM cron.job
      WHERE jobname ILIKE '%task%'
         AND (
           jobname ILIKE '%automation%' OR
           jobname ILIKE '%generate%' OR
           jobname ILIKE '%schedule%' OR
           jobname ILIKE '%recurr%' OR
           jobname ILIKE '%cron%'
         );
    EXCEPTION WHEN insufficient_privilege THEN
      RAISE NOTICE 'Skipping task automation cron cleanup: insufficient privileges for cron.job';
    END;
  END IF;
END $$;

-- -----------------------------------------------------------------------------
-- 3) Shared trigger helper: safe for existing DBs
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.touch_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.retailflow_current_date()
RETURNS date
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT (now() AT TIME ZONE 'Asia/Dhaka')::date;
$$;

REVOKE EXECUTE ON FUNCTION public.retailflow_current_date() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.retailflow_current_date() TO authenticated;

-- -----------------------------------------------------------------------------
-- 4) Fix duplicate trigger problem safely
-- -----------------------------------------------------------------------------
DO $$
BEGIN
  IF to_regclass('public.issue_reports') IS NOT NULL THEN
    DROP TRIGGER IF EXISTS issue_reports_touch_updated_at ON public.issue_reports;
  END IF;

  IF to_regclass('public.leave_requests') IS NOT NULL THEN
    DROP TRIGGER IF EXISTS leave_requests_touch_updated_at ON public.leave_requests;
  END IF;
END $$;

CREATE TRIGGER issue_reports_touch_updated_at
BEFORE UPDATE ON public.issue_reports
FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

CREATE TRIGGER leave_requests_touch_updated_at
BEFORE UPDATE ON public.leave_requests
FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

-- -----------------------------------------------------------------------------
-- 4a) Repair issue report table privileges and role-scoped RLS
-- -----------------------------------------------------------------------------
ALTER TABLE public.issue_reports ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT, UPDATE ON public.issue_reports TO authenticated;
GRANT ALL ON public.issue_reports TO service_role;

DROP POLICY IF EXISTS "issue_reports_select_own" ON public.issue_reports;
DROP POLICY IF EXISTS "issue_reports_select_branch" ON public.issue_reports;
DROP POLICY IF EXISTS "issue_reports_select_admin" ON public.issue_reports;
DROP POLICY IF EXISTS "issue_reports_insert" ON public.issue_reports;
DROP POLICY IF EXISTS "issue_reports_update" ON public.issue_reports;

CREATE POLICY "issue_reports_select_own"
  ON public.issue_reports FOR SELECT
  USING (reported_by = auth.uid());

CREATE POLICY "issue_reports_select_branch"
  ON public.issue_reports FOR SELECT
  USING (
    public.get_my_role() = 'manager'
    AND branch_id = public.get_my_branch_id()
  );

CREATE POLICY "issue_reports_select_admin"
  ON public.issue_reports FOR SELECT
  USING (public.get_my_role() = 'admin');

CREATE POLICY "issue_reports_insert"
  ON public.issue_reports FOR INSERT
  WITH CHECK (
    reported_by = auth.uid()
    AND branch_id = public.get_my_branch_id()
  );

CREATE POLICY "issue_reports_update"
  ON public.issue_reports FOR UPDATE
  USING (
    reported_by = auth.uid()
    OR public.get_my_role() = 'admin'
    OR (
      public.get_my_role() = 'manager'
      AND branch_id = public.get_my_branch_id()
    )
  )
  WITH CHECK (
    (
      reported_by = auth.uid()
      AND branch_id = public.get_my_branch_id()
    )
    OR public.get_my_role() = 'admin'
    OR (
      public.get_my_role() = 'manager'
      AND branch_id = public.get_my_branch_id()
    )
  );

-- -----------------------------------------------------------------------------
-- 5) Normalize products for price management
-- -----------------------------------------------------------------------------
-- The live database may still be on the older schema where products do not have
-- a current_price column. Price management depends on this column existing.
ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS current_price numeric(14,2) NOT NULL DEFAULT 0;

ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS updated_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL;

ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS updated_at timestamptz;

ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS is_active boolean NOT NULL DEFAULT true;

ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now();

-- If an older legacy column exists, migrate it into current_price without data loss.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'products'
      AND column_name = 'unit_price'
  ) THEN
    UPDATE public.products
    SET current_price = COALESCE(current_price, unit_price, 0)
    WHERE current_price IS NULL OR current_price = 0;
  END IF;
END $$;

ALTER TABLE public.products DROP COLUMN IF EXISTS unit_price;
ALTER TABLE public.products ALTER COLUMN current_price SET DEFAULT 0;
ALTER TABLE public.products ALTER COLUMN current_price SET NOT NULL;

ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT, UPDATE ON public.products TO authenticated;

DROP POLICY IF EXISTS "products_select" ON public.products;
DROP POLICY IF EXISTS "products_select_manager_admin" ON public.products;
DROP POLICY IF EXISTS "products_select_auth" ON public.products;
DROP POLICY IF EXISTS "products_modify_manager_admin" ON public.products;
DROP POLICY IF EXISTS "products_modify_manager_admin_final" ON public.products;
DROP POLICY IF EXISTS "products_insert_manager_admin" ON public.products;
DROP POLICY IF EXISTS "products_update_manager_admin" ON public.products;

CREATE POLICY "products_select_auth"
  ON public.products FOR SELECT
  USING (auth.uid() IS NOT NULL);

CREATE POLICY "products_insert_manager_admin"
  ON public.products FOR INSERT
  WITH CHECK (public.get_my_role() IN ('manager', 'admin'));

CREATE POLICY "products_update_manager_admin"
  ON public.products FOR UPDATE
  USING (public.get_my_role() IN ('manager', 'admin'))
  WITH CHECK (public.get_my_role() IN ('manager', 'admin'));

-- -----------------------------------------------------------------------------
-- 6) Create attendance table if it does not exist
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.attendance (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  branch_id uuid NOT NULL REFERENCES public.branches(id) ON DELETE CASCADE,
  attendance_date date NOT NULL,
  check_in_time timestamptz,
  check_out_time timestamptz,
  status text NOT NULL DEFAULT 'present'
    CHECK (status IN ('present', 'late', 'absent', 'half_day')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (employee_id, attendance_date)
);

-- Older project databases used date/time columns named date, check_in_time, and
-- check_out_time. Normalize them to the final attendance_date/timestamptz shape.
DO $$
DECLARE
  v_check_in_type text;
  v_check_out_type text;
BEGIN
  IF to_regclass('public.attendance') IS NOT NULL THEN
    IF EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name = 'attendance'
        AND column_name = 'date'
    ) AND NOT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name = 'attendance'
        AND column_name = 'attendance_date'
    ) THEN
      ALTER TABLE public.attendance RENAME COLUMN "date" TO attendance_date;
    ELSIF EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name = 'attendance'
        AND column_name = 'date'
    ) THEN
      UPDATE public.attendance
      SET attendance_date = "date"
      WHERE attendance_date IS NULL;
    END IF;

    IF NOT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name = 'attendance'
        AND column_name = 'attendance_date'
    ) THEN
      ALTER TABLE public.attendance ADD COLUMN attendance_date date;
    END IF;

    UPDATE public.attendance
    SET attendance_date = public.retailflow_current_date()
    WHERE attendance_date IS NULL;

    SELECT data_type INTO v_check_in_type
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'attendance'
      AND column_name = 'check_in_time';

    IF v_check_in_type = 'time without time zone' THEN
      ALTER TABLE public.attendance
        ALTER COLUMN check_in_time TYPE timestamptz
        USING CASE
          WHEN check_in_time IS NULL THEN NULL
          ELSE (attendance_date + check_in_time) AT TIME ZONE 'Asia/Dhaka'
        END;
    END IF;

    SELECT data_type INTO v_check_out_type
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'attendance'
      AND column_name = 'check_out_time';

    IF v_check_out_type = 'time without time zone' THEN
      ALTER TABLE public.attendance
        ALTER COLUMN check_out_time TYPE timestamptz
        USING CASE
          WHEN check_out_time IS NULL THEN NULL
          ELSE (attendance_date + check_out_time) AT TIME ZONE 'Asia/Dhaka'
        END;
    END IF;
  END IF;
END $$;

ALTER TABLE public.attendance
  ADD COLUMN IF NOT EXISTS attendance_date date;

UPDATE public.attendance
SET attendance_date = public.retailflow_current_date()
WHERE attendance_date IS NULL;

ALTER TABLE public.attendance
  ALTER COLUMN attendance_date SET NOT NULL;

CREATE INDEX IF NOT EXISTS idx_attendance_employee_date
  ON public.attendance(employee_id, attendance_date DESC);
CREATE INDEX IF NOT EXISTS idx_attendance_branch_date
  ON public.attendance(branch_id, attendance_date DESC);
CREATE UNIQUE INDEX IF NOT EXISTS idx_attendance_employee_attendance_date_unique
  ON public.attendance(employee_id, attendance_date);

ALTER TABLE public.attendance ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT, UPDATE ON public.attendance TO authenticated;

DROP POLICY IF EXISTS "attendance_select_own" ON public.attendance;
DROP POLICY IF EXISTS "attendance_select_branch" ON public.attendance;
DROP POLICY IF EXISTS "attendance_select_admin" ON public.attendance;
DROP POLICY IF EXISTS "attendance_insert_own" ON public.attendance;
DROP POLICY IF EXISTS "attendance_insert_employee_today" ON public.attendance;
DROP POLICY IF EXISTS "attendance_update_own" ON public.attendance;
DROP POLICY IF EXISTS "attendance_employee_checkout_today" ON public.attendance;
DROP POLICY IF EXISTS "attendance_admin_full" ON public.attendance;

CREATE POLICY "attendance_select_own"
  ON public.attendance FOR SELECT
  USING (employee_id = auth.uid());

CREATE POLICY "attendance_select_branch"
  ON public.attendance FOR SELECT
  USING (
    public.get_my_role() = 'manager'
    AND EXISTS (
      SELECT 1
      FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.is_active = true
        AND p.role = 'manager'
        AND p.branch_id = public.attendance.branch_id
    )
  );

CREATE POLICY "attendance_select_admin"
  ON public.attendance FOR SELECT
  USING (public.get_my_role() = 'admin');

CREATE POLICY "attendance_insert_employee_today"
  ON public.attendance FOR INSERT
  WITH CHECK (
    employee_id = auth.uid()
    AND attendance_date = public.retailflow_current_date()
    AND status IN ('present', 'late')
    AND check_out_time IS NULL
    AND EXISTS (
      SELECT 1
      FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.is_active = true
        AND p.role = 'employee'
        AND p.branch_id = public.attendance.branch_id
    )
  );

CREATE POLICY "attendance_employee_checkout_today"
  ON public.attendance FOR UPDATE
  USING (
    employee_id = auth.uid()
    AND attendance_date = public.retailflow_current_date()
  )
  WITH CHECK (
    employee_id = auth.uid()
    AND attendance_date = public.retailflow_current_date()
    AND status IN ('present', 'late')
    AND EXISTS (
      SELECT 1
      FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.is_active = true
        AND p.role = 'employee'
        AND p.branch_id = public.attendance.branch_id
    )
  );

CREATE OR REPLACE FUNCTION public.enforce_employee_attendance_write()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  caller_id uuid := auth.uid();
  caller_role text := public.get_my_role();
  caller_branch uuid;
BEGIN
  IF caller_id IS NULL OR caller_role <> 'employee' THEN
    RETURN NEW;
  END IF;

  SELECT branch_id INTO caller_branch
  FROM public.profiles
  WHERE id = caller_id
    AND role = 'employee'
    AND is_active = true;

  IF NEW.employee_id IS DISTINCT FROM caller_id
     OR NEW.branch_id IS DISTINCT FROM caller_branch
     OR NEW.attendance_date IS DISTINCT FROM public.retailflow_current_date() THEN
    RAISE EXCEPTION 'Employees can only write their own attendance for today';
  END IF;

  IF TG_OP = 'INSERT' THEN
    IF NEW.check_in_time IS NULL THEN
      RAISE EXCEPTION 'Check-in time is required';
    END IF;
    NEW.check_out_time := NULL;
    IF NEW.status NOT IN ('present', 'late') THEN
      NEW.status := 'present';
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.employee_id IS DISTINCT FROM OLD.employee_id
     OR NEW.branch_id IS DISTINCT FROM OLD.branch_id
     OR NEW.attendance_date IS DISTINCT FROM OLD.attendance_date THEN
    RAISE EXCEPTION 'Attendance identity fields cannot be changed';
  END IF;

  IF OLD.check_in_time IS NULL THEN
    IF NEW.check_in_time IS NULL THEN
      RAISE EXCEPTION 'Check-in time is required';
    END IF;
    IF NEW.check_out_time IS NOT NULL THEN
      RAISE EXCEPTION 'Check in before checking out';
    END IF;
    IF NEW.status NOT IN ('present', 'late') THEN
      NEW.status := 'present';
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.check_in_time IS DISTINCT FROM OLD.check_in_time THEN
    RAISE EXCEPTION 'Check-in time cannot be changed after it is recorded';
  END IF;

  IF OLD.check_out_time IS NOT NULL
     AND NEW.check_out_time IS DISTINCT FROM OLD.check_out_time THEN
    RAISE EXCEPTION 'Check-out time cannot be changed after it is recorded';
  END IF;

  NEW.status := OLD.status;
  RETURN NEW;
END;
$$;

DO $$
BEGIN
  IF to_regclass('public.attendance') IS NOT NULL THEN
    DROP TRIGGER IF EXISTS attendance_touch_updated_at ON public.attendance;
    DROP TRIGGER IF EXISTS attendance_employee_write_guard ON public.attendance;
  END IF;
END $$;

CREATE TRIGGER attendance_employee_write_guard
BEFORE INSERT OR UPDATE ON public.attendance
FOR EACH ROW EXECUTE FUNCTION public.enforce_employee_attendance_write();

CREATE TRIGGER attendance_touch_updated_at
BEFORE UPDATE ON public.attendance
FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

-- -----------------------------------------------------------------------------
-- 7) Create product_price_history if it does not exist
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.product_price_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  old_price numeric(14,2) NOT NULL DEFAULT 0,
  new_price numeric(14,2) NOT NULL DEFAULT 0,
  updated_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);

UPDATE public.product_price_history
SET old_price = 0
WHERE old_price IS NULL;

UPDATE public.product_price_history
SET new_price = 0
WHERE new_price IS NULL;

ALTER TABLE public.product_price_history
  ALTER COLUMN old_price SET DEFAULT 0,
  ALTER COLUMN old_price SET NOT NULL,
  ALTER COLUMN new_price SET DEFAULT 0,
  ALTER COLUMN new_price SET NOT NULL;

CREATE INDEX IF NOT EXISTS idx_product_price_history_product_id
  ON public.product_price_history(product_id, updated_at DESC);

CREATE OR REPLACE FUNCTION public.log_product_price_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.current_price IS DISTINCT FROM OLD.current_price THEN
    INSERT INTO public.product_price_history (
      product_id,
      old_price,
      new_price,
      updated_by,
      updated_at
    )
    VALUES (
      NEW.id,
      COALESCE(OLD.current_price, 0),
      COALESCE(NEW.current_price, 0),
      COALESCE(NEW.updated_by, auth.uid()),
      now()
    );
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS products_price_history_log ON public.products;
CREATE TRIGGER products_price_history_log
BEFORE UPDATE ON public.products
FOR EACH ROW
WHEN (NEW.current_price IS DISTINCT FROM OLD.current_price)
EXECUTE FUNCTION public.log_product_price_change();

ALTER TABLE public.product_price_history ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT ON public.product_price_history TO authenticated;
REVOKE UPDATE, DELETE ON public.product_price_history FROM authenticated;

DROP POLICY IF EXISTS "product_price_history_select_auth" ON public.product_price_history;
DROP POLICY IF EXISTS "product_price_history_insert_manager_admin" ON public.product_price_history;
DROP POLICY IF EXISTS "product_price_history_update_manager_admin" ON public.product_price_history;
DROP POLICY IF EXISTS "product_price_history_admin_full" ON public.product_price_history;

CREATE POLICY "product_price_history_select_auth"
  ON public.product_price_history FOR SELECT
  USING (auth.uid() IS NOT NULL);

CREATE POLICY "product_price_history_insert_manager_admin"
  ON public.product_price_history FOR INSERT
  WITH CHECK (public.get_my_role() IN ('manager', 'admin'));

DO $$
BEGIN
  IF to_regclass('public.product_price_history') IS NOT NULL THEN
    DROP TRIGGER IF EXISTS product_price_history_touch_updated_at ON public.product_price_history;
  END IF;
END $$;

CREATE TRIGGER product_price_history_touch_updated_at
BEFORE UPDATE ON public.product_price_history
FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

-- -----------------------------------------------------------------------------
-- 8) Create task_templates only if missing
-- -----------------------------------------------------------------------------
-- Note: Task templates are reusable definitions only.
-- No automatic generation, scheduler, cron, or recurring task execution.
CREATE TABLE IF NOT EXISTS public.task_templates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL,
  description text,
  frequency text NOT NULL DEFAULT 'daily',
  points integer NOT NULL DEFAULT 10 CHECK (points >= 0),
  photo_required boolean NOT NULL DEFAULT false,
  branch_id uuid REFERENCES public.branches(id) ON DELETE SET NULL,
  created_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_task_templates_branch_active
  ON public.task_templates(branch_id, is_active, created_at DESC);

ALTER TABLE public.task_templates ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "task_templates_select_auth" ON public.task_templates;
DROP POLICY IF EXISTS "task_templates_insert_manager_admin" ON public.task_templates;
DROP POLICY IF EXISTS "task_templates_update_manager_admin" ON public.task_templates;
DROP POLICY IF EXISTS "task_templates_delete_manager_admin" ON public.task_templates;

CREATE POLICY "task_templates_select_auth"
  ON public.task_templates FOR SELECT
  USING (auth.uid() IS NOT NULL);

CREATE POLICY "task_templates_insert_manager_admin"
  ON public.task_templates FOR INSERT
  WITH CHECK (public.get_my_role() IN ('manager', 'admin'));

CREATE POLICY "task_templates_update_manager_admin"
  ON public.task_templates FOR UPDATE
  USING (public.get_my_role() IN ('manager', 'admin'))
  WITH CHECK (public.get_my_role() IN ('manager', 'admin'));

CREATE POLICY "task_templates_delete_manager_admin"
  ON public.task_templates FOR DELETE
  USING (public.get_my_role() IN ('manager', 'admin'));

DO $$
BEGIN
  IF to_regclass('public.task_templates') IS NOT NULL THEN
    DROP TRIGGER IF EXISTS task_templates_touch_updated_at ON public.task_templates;
  END IF;
END $$;

CREATE TRIGGER task_templates_touch_updated_at
BEFORE UPDATE ON public.task_templates
FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

-- -----------------------------------------------------------------------------
-- Leave request RLS: employees submit, managers review branch requests by RPC
-- -----------------------------------------------------------------------------
ALTER TABLE public.leave_requests ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT ON public.leave_requests TO authenticated;
REVOKE UPDATE, DELETE ON public.leave_requests FROM authenticated;

DROP POLICY IF EXISTS "leave_requests_select_own" ON public.leave_requests;
DROP POLICY IF EXISTS "leave_requests_select_branch" ON public.leave_requests;
DROP POLICY IF EXISTS "leave_requests_select_admin" ON public.leave_requests;
DROP POLICY IF EXISTS "leave_requests_insert" ON public.leave_requests;
DROP POLICY IF EXISTS "leave_requests_insert_employee_own" ON public.leave_requests;
DROP POLICY IF EXISTS "leave_requests_update" ON public.leave_requests;
DROP POLICY IF EXISTS "leave_requests_update_manager_admin" ON public.leave_requests;

CREATE POLICY "leave_requests_select_own"
  ON public.leave_requests FOR SELECT
  USING (employee_id = auth.uid());

CREATE POLICY "leave_requests_select_branch"
  ON public.leave_requests FOR SELECT
  USING (
    public.get_my_role() = 'manager'
    AND EXISTS (
      SELECT 1
      FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.is_active = true
        AND p.role = 'manager'
        AND p.branch_id = public.leave_requests.branch_id
    )
  );

CREATE POLICY "leave_requests_select_admin"
  ON public.leave_requests FOR SELECT
  USING (public.get_my_role() = 'admin');

CREATE POLICY "leave_requests_insert_employee_own"
  ON public.leave_requests FOR INSERT
  WITH CHECK (
    employee_id = auth.uid()
    AND status = 'pending'
    AND EXISTS (
      SELECT 1
      FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.is_active = true
        AND p.role = 'employee'
        AND p.branch_id = public.leave_requests.branch_id
    )
  );

-- -----------------------------------------------------------------------------
-- Leave review RPC with employee notification
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.review_leave_request(
  p_leave_id uuid,
  p_status text,
  p_manager_comment text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  caller_id uuid := auth.uid();
  caller_role text;
  caller_branch uuid;
  v_leave public.leave_requests%ROWTYPE;
  v_status text := lower(trim(p_status));
  v_message text;
BEGIN
  SELECT role, branch_id INTO caller_role, caller_branch
  FROM public.profiles
  WHERE id = caller_id AND is_active = true;

  IF caller_id IS NULL OR caller_role NOT IN ('manager', 'admin') THEN
    RAISE EXCEPTION 'Only managers or admins can review leave requests';
  END IF;

  SELECT * INTO v_leave
  FROM public.leave_requests
  WHERE id = p_leave_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Leave request not found';
  END IF;

  IF v_leave.status <> 'pending' THEN
    RAISE EXCEPTION 'This leave request is not pending review';
  END IF;

  IF caller_role = 'manager'
     AND v_leave.branch_id IS DISTINCT FROM caller_branch THEN
    RAISE EXCEPTION 'Manager can only review leave requests in their branch';
  END IF;

  IF v_status NOT IN ('approved', 'rejected') THEN
    RAISE EXCEPTION 'Status must be approved or rejected';
  END IF;

  UPDATE public.leave_requests
  SET status = v_status,
      manager_comment = NULLIF(trim(COALESCE(p_manager_comment, v_leave.manager_comment)), ''),
      updated_at = now()
  WHERE id = p_leave_id;

  IF v_status = 'approved' THEN
    v_message := 'Your leave request from ' || to_char(v_leave.start_date, 'YYYY-MM-DD') || ' to ' || to_char(v_leave.end_date, 'YYYY-MM-DD') || ' was approved.';
    INSERT INTO public.notifications (user_id, type, title, message, data)
    VALUES (
      v_leave.employee_id,
      'leave_approved',
      'Leave Approved',
      v_message,
      jsonb_build_object('leave_id', p_leave_id, 'status', v_status)
    );
  ELSE
    v_message := 'Your leave request from ' || to_char(v_leave.start_date, 'YYYY-MM-DD') || ' to ' || to_char(v_leave.end_date, 'YYYY-MM-DD') || ' was rejected.';
    IF NULLIF(trim(COALESCE(p_manager_comment, '')), '') IS NOT NULL THEN
      v_message := v_message || ' Reason: ' || trim(p_manager_comment);
    END IF;

    INSERT INTO public.notifications (user_id, type, title, message, data)
    VALUES (
      v_leave.employee_id,
      'leave_rejected',
      'Leave Rejected',
      v_message,
      jsonb_build_object('leave_id', p_leave_id, 'status', v_status, 'manager_comment', NULLIF(trim(COALESCE(p_manager_comment, '')), ''))
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'leave_id', p_leave_id,
    'status', v_status
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.review_leave_request(uuid, text, text) TO authenticated;

-- -----------------------------------------------------------------------------
-- Issue status review RPC with reporter notification
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.update_issue_status(
  p_issue_id uuid,
  p_status text,
  p_resolution_note text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  caller_id uuid := auth.uid();
  caller_role text;
  caller_branch uuid;
  issue_row public.issue_reports%ROWTYPE;
  v_status text := lower(trim(p_status));
BEGIN
  SELECT role, branch_id INTO caller_role, caller_branch
  FROM public.profiles
  WHERE id = caller_id AND is_active = true;

  IF caller_id IS NULL OR caller_role NOT IN ('manager', 'admin') THEN
    RAISE EXCEPTION 'Only managers or admins can update issue status';
  END IF;

  SELECT * INTO issue_row
  FROM public.issue_reports
  WHERE id = p_issue_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Issue not found';
  END IF;

  IF caller_role = 'manager'
     AND issue_row.branch_id IS DISTINCT FROM caller_branch THEN
    RAISE EXCEPTION 'Manager can only update issues in their branch';
  END IF;

  IF v_status NOT IN ('open', 'in_progress', 'resolved', 'closed') THEN
    RAISE EXCEPTION 'Status is invalid';
  END IF;

  UPDATE public.issue_reports
  SET status = v_status,
      resolution_note = NULLIF(trim(COALESCE(p_resolution_note, issue_row.resolution_note)), ''),
      updated_at = now(),
      resolved_at = CASE
        WHEN v_status IN ('resolved', 'closed') THEN COALESCE(issue_row.resolved_at, now())
        ELSE NULL
      END
  WHERE id = p_issue_id;

  INSERT INTO public.notifications (user_id, type, title, message, data)
  VALUES (
    issue_row.reported_by,
    'issue_status_updated',
    'Issue Status Updated',
    'Your reported issue "' || issue_row.title || '" is now ' || v_status || '.',
    jsonb_build_object('issue_id', p_issue_id)
  );

  RETURN jsonb_build_object(
    'success', true,
    'issue_id', p_issue_id,
    'status', v_status
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_issue_status(uuid, text, text) TO authenticated;

-- -----------------------------------------------------------------------------
-- 9) Clean up legacy scheduler metadata if present
-- -----------------------------------------------------------------------------
-- The system uses manually created tasks; recurring execution is not part of the
-- final RetailFlow architecture.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    BEGIN
      DELETE FROM cron.job
      WHERE jobname ILIKE '%template%'
         OR jobname ILIKE '%automation%'
         OR jobname ILIKE '%generation%'
         OR jobname ILIKE '%scheduler%'
         OR jobname ILIKE '%recurr%';
    EXCEPTION WHEN insufficient_privilege THEN
      RAISE NOTICE 'Skipping legacy scheduler cleanup: insufficient privileges for cron.job';
    END;
  END IF;
END $$;

-- -----------------------------------------------------------------------------
-- 10) Verification queries
-- -----------------------------------------------------------------------------
-- Check tables.
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN ('attendance', 'issue_reports', 'leave_requests', 'products', 'product_price_history', 'task_templates')
ORDER BY table_name;

-- Check RLS state for all required tables.
SELECT schemaname, tablename, rowsecurity
FROM pg_tables
WHERE schemaname = 'public'
  AND tablename IN ('attendance', 'issue_reports', 'leave_requests', 'products', 'product_price_history', 'task_templates')
ORDER BY tablename;

-- Check policies for all required tables.
SELECT schemaname, tablename, policyname, cmd, roles, qual
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('attendance', 'issue_reports', 'leave_requests', 'products', 'product_price_history', 'task_templates')
ORDER BY tablename, policyname;

-- Check cron jobs if pg_cron is installed and the current role has access.
DO $$
DECLARE
  v_count integer := 0;
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    BEGIN
      SELECT COUNT(*) INTO v_count
      FROM cron.job
      WHERE jobname ILIKE '%competition%'
         OR jobname ILIKE '%leaderboard%'
         OR jobname ILIKE '%ranking%'
         OR jobname ILIKE '%template%'
         OR jobname ILIKE '%automation%'
         OR jobname ILIKE '%generate%'
         OR jobname ILIKE '%recurr%';

      RAISE NOTICE 'Matching cron jobs detected: %', v_count;
    EXCEPTION WHEN insufficient_privilege THEN
      RAISE NOTICE 'Skipping cron verification: insufficient privileges for cron.job';
    END;
  END IF;
END $$;

COMMIT;
