-- Run in: Supabase Dashboard -> SQL Editor
-- =============================================================

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

CREATE TABLE IF NOT EXISTS public.badges (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL UNIQUE,
  min_points integer NOT NULL CHECK (min_points >= 0),
  description text,
  icon_name text NOT NULL DEFAULT 'military_tech',
  created_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO public.badges (name, min_points, description, icon_name) VALUES
  ('Bronze', 500, 'Earned 500 lifetime task points', 'workspace_premium'),
  ('Silver', 1500, 'Earned 1500 lifetime points', 'military_tech'),
  ('Gold', 3000, 'Earned 3000 lifetime task points', 'stars')
ON CONFLICT (name) DO UPDATE SET
  min_points = EXCLUDED.min_points,
  description = EXCLUDED.description;

DELETE FROM public.badges WHERE name = 'Platinum';

CREATE TABLE IF NOT EXISTS public.branches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  location text,
  manager_id uuid,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.company_profile (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  industry text NOT NULL DEFAULT 'Retail',
  headquarters text,
  region text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.profiles (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  name text NOT NULL,
  email text NOT NULL,
  role text NOT NULL DEFAULT 'employee'
    CHECK (role IN ('employee', 'manager', 'admin')),
  branch_id uuid REFERENCES public.branches(id) ON DELETE SET NULL,
  current_badge_id uuid REFERENCES public.badges(id) ON DELETE SET NULL,
  total_lifetime_points integer NOT NULL DEFAULT 0 CHECK (total_lifetime_points >= 0),
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_profiles_email_unique
  ON public.profiles (lower(email));
CREATE INDEX IF NOT EXISTS idx_profiles_branch_id ON public.profiles(branch_id);
CREATE INDEX IF NOT EXISTS idx_profiles_role ON public.profiles(role);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'branches_manager_id_fkey'
      AND conrelid = 'public.branches'::regclass
  ) THEN
    ALTER TABLE public.branches
      ADD CONSTRAINT branches_manager_id_fkey
      FOREIGN KEY (manager_id) REFERENCES public.profiles(id) ON DELETE SET NULL;
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.get_my_role()
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT role FROM public.profiles WHERE id = auth.uid() AND is_active = true;
$$;

CREATE OR REPLACE FUNCTION public.get_my_branch_id()
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT branch_id FROM public.profiles WHERE id = auth.uid() AND is_active = true;
$$;

CREATE OR REPLACE FUNCTION public.retailflow_current_date()
RETURNS date LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT (now() AT TIME ZONE 'Asia/Dhaka')::date;
$$;

CREATE OR REPLACE FUNCTION public.handle_new_retailflow_user()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE selected_branch uuid;
BEGIN
  BEGIN
    selected_branch := NULLIF(new.raw_user_meta_data ->> 'branch_id', '')::uuid;
  EXCEPTION WHEN invalid_text_representation THEN
    selected_branch := NULL;
  END;

  IF selected_branch IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.branches
    WHERE id = selected_branch AND is_active = true
  ) THEN
    selected_branch := NULL;
  END IF;

  -- Public registration is always employee-only. Admin-created users are
  -- promoted to manager/admin by the create-user Edge Function after Auth
  -- creates this initial profile row.
  INSERT INTO public.profiles (id, name, email, role, branch_id, is_active, total_lifetime_points)
  VALUES (
    new.id,
    COALESCE(NULLIF(trim(new.raw_user_meta_data ->> 'name'), ''), split_part(COALESCE(new.email, 'Employee'), '@', 1)),
    COALESCE(new.email, ''), 'employee', selected_branch, true, 0
  ) ON CONFLICT (id) DO NOTHING;
  RETURN new;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created_retailflow ON auth.users;
CREATE TRIGGER on_auth_user_created_retailflow
  AFTER INSERT ON auth.users FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_retailflow_user();

CREATE TABLE IF NOT EXISTS public.products (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  category text NOT NULL,
  current_price numeric(14,2) NOT NULL DEFAULT 0 CHECK (current_price >= 0),
  updated_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  updated_at timestamptz,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_products_is_active ON public.products(is_active);
ALTER TABLE public.products DROP COLUMN IF EXISTS unit_price;

CREATE TABLE IF NOT EXISTS public.product_price_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  old_price numeric(14,2) NOT NULL CHECK (old_price >= 0),
  new_price numeric(14,2) NOT NULL CHECK (new_price >= 0),
  updated_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);
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
CREATE INDEX IF NOT EXISTS idx_attendance_employee_date
  ON public.attendance(employee_id, attendance_date DESC);
CREATE INDEX IF NOT EXISTS idx_attendance_branch_date
  ON public.attendance(branch_id, attendance_date DESC);

CREATE TABLE IF NOT EXISTS public.shifts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  branch_id uuid REFERENCES public.branches(id) ON DELETE CASCADE,
  name text NOT NULL,
  start_time time NOT NULL,
  end_time time NOT NULL,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_shifts_branch_id ON public.shifts(branch_id);

CREATE TABLE IF NOT EXISTS public.employee_shifts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  shift_id uuid NOT NULL REFERENCES public.shifts(id) ON DELETE CASCADE,
  work_date date NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (employee_id, shift_id, work_date)
);
CREATE INDEX IF NOT EXISTS idx_employee_shifts_shift_id ON public.employee_shifts(shift_id);
CREATE INDEX IF NOT EXISTS idx_employee_shifts_work_date  ON public.employee_shifts(work_date);
CREATE INDEX IF NOT EXISTS idx_employee_shifts_employee   ON public.employee_shifts(employee_id);

-- ─────────────────────────────────────────────────────────────
-- 7. TASK TEMPLATES & ASSIGNMENTS
-- ─────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.tasks (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title              text NOT NULL,
  description        text,
  frequency          text NOT NULL DEFAULT 'daily'
                       CHECK (frequency IN ('daily', 'weekly', 'monthly')),
  branch_id          uuid REFERENCES public.branches(id) ON DELETE SET NULL,
  created_by         uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  base_points        integer NOT NULL DEFAULT 10 CHECK (base_points >= 0),
  photo_bonus_points integer NOT NULL DEFAULT 5 CHECK (photo_bonus_points >= 0),
  photo_required     boolean NOT NULL DEFAULT false,
  deadline_hours_after_assignment integer CHECK (deadline_hours_after_assignment IS NULL OR deadline_hours_after_assignment > 0),
  assigned_user_id   uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  schedule_weekday   smallint CHECK (schedule_weekday IS NULL OR schedule_weekday BETWEEN 0 AND 6),
  schedule_month_day smallint CHECK (schedule_month_day IS NULL OR schedule_month_day BETWEEN 1 AND 31),
  last_generated_date date,
  last_generated_at  timestamptz,
  is_active          boolean NOT NULL DEFAULT true,
  created_at         timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.tasks
  ADD COLUMN IF NOT EXISTS deadline_hours_after_assignment integer
  CHECK (deadline_hours_after_assignment IS NULL OR deadline_hours_after_assignment > 0);
ALTER TABLE public.tasks
  ADD COLUMN IF NOT EXISTS assigned_user_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS schedule_weekday smallint CHECK (schedule_weekday IS NULL OR schedule_weekday BETWEEN 0 AND 6),
  ADD COLUMN IF NOT EXISTS schedule_month_day smallint CHECK (schedule_month_day IS NULL OR schedule_month_day BETWEEN 1 AND 31),
  ADD COLUMN IF NOT EXISTS last_generated_date date,
  ADD COLUMN IF NOT EXISTS last_generated_at timestamptz;

CREATE INDEX IF NOT EXISTS idx_tasks_branch_id ON public.tasks(branch_id);
CREATE INDEX IF NOT EXISTS idx_tasks_is_active ON public.tasks(is_active);
CREATE INDEX IF NOT EXISTS idx_tasks_assigned_user_id ON public.tasks(assigned_user_id);
CREATE INDEX IF NOT EXISTS idx_tasks_last_generated_date ON public.tasks(last_generated_date);

CREATE TABLE IF NOT EXISTS public.task_assignments (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id        uuid NOT NULL REFERENCES public.tasks(id) ON DELETE RESTRICT,
  user_id        uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  scheduled_date date NOT NULL,
  due_at         timestamptz,
  status         text NOT NULL DEFAULT 'pending'
                   CHECK (status IN ('pending', 'completed', 'approved', 'rejected')),
  assigned_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (task_id, user_id, scheduled_date)
);

CREATE INDEX IF NOT EXISTS idx_task_assignments_user_id ON public.task_assignments(user_id);
CREATE INDEX IF NOT EXISTS idx_task_assignments_task_id ON public.task_assignments(task_id);
CREATE INDEX IF NOT EXISTS idx_task_assignments_scheduled_date ON public.task_assignments(scheduled_date);
CREATE INDEX IF NOT EXISTS idx_task_assignments_status ON public.task_assignments(status);
CREATE UNIQUE INDEX IF NOT EXISTS idx_task_assignments_template_employee_date_unique
  ON public.task_assignments(task_id, user_id, scheduled_date);

-- ─────────────────────────────────────────────────────────────
-- 8. TASK COMPLETIONS (SEPARATE MULTI-ATTEMPT HISTORY)
-- ─────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.task_completions (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  assignment_id   uuid NOT NULL REFERENCES public.task_assignments(id) ON DELETE CASCADE,
  attempt_number  integer NOT NULL DEFAULT 1 CHECK (attempt_number >= 1),
  submitted_by    uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  submitted_at    timestamptz NOT NULL DEFAULT now(),
  completion_note text,
  photo_url       text,
  reviewed_by     uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  reviewed_at     timestamptz,
  review_note     text,
  status          text NOT NULL DEFAULT 'submitted'
                    CHECK (status IN ('submitted', 'approved', 'rejected')),
  points_awarded  integer NOT NULL DEFAULT 0 CHECK (points_awarded >= 0),
  UNIQUE (assignment_id, attempt_number)
);

CREATE INDEX IF NOT EXISTS idx_task_completions_assignment ON public.task_completions(assignment_id);
CREATE INDEX IF NOT EXISTS idx_task_completions_submitted_by ON public.task_completions(submitted_by);
CREATE INDEX IF NOT EXISTS idx_task_completions_status ON public.task_completions(status);

-- ─────────────────────────────────────────────────────────────
-- 9. POINTS TRANSACTIONS LEDGER & BADGES LOGIC
-- ─────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.points_transactions (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id             uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  task_completion_id  uuid NOT NULL REFERENCES public.task_completions(id) ON DELETE CASCADE,
  points              integer NOT NULL CHECK (points >= 0),
  base_points         integer NOT NULL DEFAULT 0 CHECK (base_points >= 0),
  bonus_points        integer NOT NULL DEFAULT 0 CHECK (bonus_points >= 0),
  awarded_at          timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uq_points_task_completion UNIQUE (task_completion_id)
);

CREATE INDEX IF NOT EXISTS idx_points_transactions_user_id ON public.points_transactions(user_id);

CREATE TABLE IF NOT EXISTS public.audit_log (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_id    uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  actor_role  text,
  action      text NOT NULL,
  entity_type text NOT NULL,
  entity_id   uuid,
  branch_id   uuid REFERENCES public.branches(id) ON DELETE SET NULL,
  metadata    jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_audit_log_actor_id ON public.audit_log(actor_id);
CREATE INDEX IF NOT EXISTS idx_audit_log_branch_id ON public.audit_log(branch_id);
CREATE INDEX IF NOT EXISTS idx_audit_log_action_created
  ON public.audit_log(action, created_at DESC);

CREATE OR REPLACE FUNCTION public.write_audit_log(
  p_action text,
  p_entity_type text,
  p_entity_id uuid DEFAULT NULL,
  p_branch_id uuid DEFAULT NULL,
  p_metadata jsonb DEFAULT '{}'::jsonb,
  p_actor_id uuid DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor_id uuid := COALESCE(p_actor_id, auth.uid());
  v_actor_role text;
BEGIN
  IF v_actor_id IS NOT NULL THEN
    SELECT role INTO v_actor_role
    FROM public.profiles
    WHERE id = v_actor_id;
  END IF;

  INSERT INTO public.audit_log(
    actor_id,
    actor_role,
    action,
    entity_type,
    entity_id,
    branch_id,
    metadata
  )
  VALUES (
    v_actor_id,
    v_actor_role,
    p_action,
    p_entity_type,
    p_entity_id,
    p_branch_id,
    COALESCE(p_metadata, '{}'::jsonb)
  );
END;
$$;
REVOKE ALL ON FUNCTION public.write_audit_log(text, text, uuid, uuid, jsonb, uuid)
  FROM PUBLIC, anon, authenticated;

-- Function to recalculate employee badge tier from total points
CREATE OR REPLACE FUNCTION public.recalculate_user_badge(p_user_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_total_points integer;
  v_new_badge_id uuid;
  v_old_badge_id uuid;
  v_badge_name   text;
  v_user_branch  uuid;
BEGIN
  SELECT total_lifetime_points, current_badge_id, branch_id
  INTO v_total_points, v_old_badge_id, v_user_branch
  FROM public.profiles
  WHERE id = p_user_id;

  SELECT id, name
  INTO v_new_badge_id, v_badge_name
  FROM public.badges
  WHERE min_points <= COALESCE(v_total_points, 0)
  ORDER BY min_points DESC
  LIMIT 1;

  IF v_new_badge_id IS DISTINCT FROM v_old_badge_id THEN
    UPDATE public.profiles
    SET current_badge_id = v_new_badge_id
    WHERE id = p_user_id;

    -- Create notification if badge upgraded
    IF v_new_badge_id IS NOT NULL THEN
      INSERT INTO public.notifications (user_id, type, title, message)
      VALUES (
        p_user_id,
        'badge_unlocked',
        'New Badge Unlocked!',
        'Congratulations! You have unlocked the ' || v_badge_name || ' Badge with ' || v_total_points || ' lifetime points.'
      );
    END IF;

    PERFORM public.write_audit_log(
      'badge_updated',
      'profile',
      p_user_id,
      v_user_branch,
      jsonb_build_object(
        'total_lifetime_points', v_total_points,
        'badge_id', v_new_badge_id,
        'badge_name', v_badge_name
      )
    );
  END IF;

  RETURN v_new_badge_id;
END;
$$;

-- Atomic task approval & point awarding function
CREATE OR REPLACE FUNCTION public.approve_task_completion(
  p_completion_id uuid,
  p_reviewer_id   uuid,
  p_review_note   text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id     uuid := auth.uid();
  v_caller_role   text;
  v_caller_branch uuid;
  v_employee_branch uuid;
  v_comp          public.task_completions%ROWTYPE;
  v_assign        public.task_assignments%ROWTYPE;
  v_task          public.tasks%ROWTYPE;
  v_base_pts      integer;
  v_bonus_pts     integer := 0;
  v_total_pts     integer;
  v_points_inserted integer;
BEGIN
  SELECT role, branch_id INTO v_caller_role, v_caller_branch
  FROM public.profiles
  WHERE id = v_caller_id AND is_active = true;
  IF v_caller_id IS NULL OR v_caller_role NOT IN ('manager', 'admin')
     OR p_reviewer_id IS DISTINCT FROM v_caller_id THEN
    RAISE EXCEPTION 'Only the authenticated manager or admin can approve completions';
  END IF;

  -- Fetch completion record
  SELECT * INTO v_comp
  FROM public.task_completions
  WHERE id = p_completion_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Completion record not found';
  END IF;

  IF v_comp.status <> 'submitted' THEN
    RAISE EXCEPTION 'This completion is not available for approval';
  END IF;

  -- Fetch assignment & task template
  SELECT * INTO v_assign
  FROM public.task_assignments
  WHERE id = v_comp.assignment_id;

  SELECT * INTO v_task
  FROM public.tasks
  WHERE id = v_assign.task_id;

  SELECT branch_id INTO v_employee_branch
  FROM public.profiles
  WHERE id = v_assign.user_id AND is_active = true;
  IF v_caller_role = 'manager'
     AND v_employee_branch IS DISTINCT FROM v_caller_branch THEN
    RAISE EXCEPTION 'Manager can only approve completions in their branch';
  END IF;
  IF v_task.photo_required
     AND NULLIF(trim(v_comp.photo_url), '') IS NULL THEN
    RAISE EXCEPTION 'Photo proof is required';
  END IF;

  v_base_pts := CASE v_task.frequency
    WHEN 'weekly' THEN 30
    WHEN 'monthly' THEN 60
    ELSE 10
  END;

  -- Award photo bonus if photo URL was submitted
  IF v_comp.photo_url IS NOT NULL AND length(trim(v_comp.photo_url)) > 0 THEN
    v_bonus_pts := 5;
  END IF;

  v_total_pts := v_base_pts + v_bonus_pts;

  -- Update completion record
  UPDATE public.task_completions
  SET status = 'approved',
      reviewed_by = p_reviewer_id,
      reviewed_at = now(),
      review_note = p_review_note,
      points_awarded = v_total_pts
  WHERE id = p_completion_id;

  -- Update parent assignment status to approved
  UPDATE public.task_assignments
  SET status = 'approved'
  WHERE id = v_comp.assignment_id;

  -- Insert points transaction (idempotent due to UNIQUE constraint)
  INSERT INTO public.points_transactions (
    user_id,
    task_completion_id,
    points,
    base_points,
    bonus_points
  )
  VALUES (
    v_assign.user_id,
    p_completion_id,
    v_total_pts,
    v_base_pts,
    v_bonus_pts
  )
  ON CONFLICT (task_completion_id) DO NOTHING;
  GET DIAGNOSTICS v_points_inserted = ROW_COUNT;

  -- Update user total lifetime points
  IF v_points_inserted = 1 THEN
    UPDATE public.profiles
    SET total_lifetime_points = total_lifetime_points + v_total_pts
    WHERE id = v_assign.user_id;

    -- Check & recalculate badge tier
    PERFORM public.recalculate_user_badge(v_assign.user_id);

    -- Send notification to employee
    INSERT INTO public.notifications (user_id, type, title, message)
    VALUES (
      v_assign.user_id,
      'task_approved',
      'Task Approved! +' || v_total_pts || ' pts',
      'Your task "' || v_task.title || '" was approved by your manager.'
    );

    PERFORM public.write_audit_log(
      'task_completion_approved',
      'task_completion',
      p_completion_id,
      v_employee_branch,
      jsonb_build_object(
        'assignment_id', v_comp.assignment_id,
        'task_id', v_assign.task_id,
        'employee_id', v_assign.user_id,
        'base_points', v_base_pts,
        'bonus_points', v_bonus_pts,
        'points_awarded', v_total_pts
      ),
      p_reviewer_id
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'points_awarded', v_total_pts,
    'base_points', v_base_pts,
    'bonus_points', v_bonus_pts
  );
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- 10. SALES TARGETS & CSV SALES IMPORTS (BRANCH/SHIFT LEVEL)
-- ─────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.sales_targets (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  branch_id      uuid NOT NULL REFERENCES public.branches(id) ON DELETE CASCADE,
  shift_id       uuid REFERENCES public.shifts(id) ON DELETE SET NULL,
  target_date    date NOT NULL,
  target_amount  numeric(14,2) NOT NULL CHECK (target_amount >= 0),
  created_by     uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at     timestamptz NOT NULL DEFAULT now(),
  UNIQUE (branch_id, shift_id, target_date)
);

CREATE INDEX IF NOT EXISTS idx_sales_targets_branch_date
  ON public.sales_targets(branch_id, target_date);

-- PostgreSQL UNIQUE constraints treat NULL shift_id values as distinct.
-- If an older deployment already created duplicate all-shifts targets, keep
-- the most recently created row before applying the unique guard.
WITH ranked_targets AS (
  SELECT id,
         row_number() OVER (
           PARTITION BY branch_id, target_date
           ORDER BY created_at DESC, id DESC
         ) AS rn
  FROM public.sales_targets
  WHERE shift_id IS NULL
)
DELETE FROM public.sales_targets st
USING ranked_targets rt
WHERE st.id = rt.id AND rt.rn > 1;

-- These partial indexes ensure one all-shifts target per branch/date and one
-- target per concrete branch/shift/date.
CREATE UNIQUE INDEX IF NOT EXISTS idx_sales_targets_no_shift_unique
  ON public.sales_targets (branch_id, target_date)
  WHERE shift_id IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_sales_targets_with_shift_unique
  ON public.sales_targets (branch_id, shift_id, target_date)
  WHERE shift_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS public.sales_entries (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  branch_id     uuid NOT NULL REFERENCES public.branches(id) ON DELETE CASCADE,
  shift_id      uuid REFERENCES public.shifts(id) ON DELETE SET NULL,
  sale_date     date NOT NULL,
  recorded_by   uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  product_id    uuid NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
  quantity      integer NOT NULL CHECK (quantity > 0),
  unit_price    numeric(10,2) NOT NULL CHECK (unit_price > 0),
  total_amount  numeric(14,2) GENERATED ALWAYS AS (quantity * unit_price) STORED,
  recorded_at   timestamptz NOT NULL DEFAULT now()
);

-- Legacy compatibility table only. New RetailFlow sales data must use
-- sales_imports/sales_import_items via import_sales_data().

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'sales_entries'
      AND column_name = 'employee_id'
  ) AND NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'sales_entries'
      AND column_name = 'recorded_by'
  ) THEN
    ALTER TABLE public.sales_entries RENAME COLUMN employee_id TO recorded_by;
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE table_schema = 'public'
      AND table_name = 'sales_entries'
      AND constraint_name = 'sales_entries_employee_id_fkey'
  ) AND NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE table_schema = 'public'
      AND table_name = 'sales_entries'
      AND constraint_name = 'sales_entries_recorded_by_fkey'
  ) THEN
    ALTER TABLE public.sales_entries
      RENAME CONSTRAINT sales_entries_employee_id_fkey
      TO sales_entries_recorded_by_fkey;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_sales_entries_branch_date
  ON public.sales_entries(branch_id, sale_date);
CREATE INDEX IF NOT EXISTS idx_sales_entries_product
  ON public.sales_entries(product_id);
CREATE INDEX IF NOT EXISTS idx_sales_entries_recorded_by
  ON public.sales_entries(recorded_by);

CREATE TABLE IF NOT EXISTS public.sales_imports (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  branch_id          uuid NOT NULL REFERENCES public.branches(id) ON DELETE CASCADE,
  shift_id           uuid REFERENCES public.shifts(id) ON DELETE SET NULL,
  sale_date          date NOT NULL,
  source             text NOT NULL DEFAULT 'csv_upload'
                       CHECK (source = 'csv_upload'),
  sales_source       text NOT NULL DEFAULT 'csv_upload'
                       CHECK (sales_source IN ('csv_upload', 'pos_api', 'external_api')),
  total_amount       numeric(14,2) NOT NULL CHECK (total_amount >= 0),
  imported_by        uuid NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  imported_at        timestamptz NOT NULL DEFAULT now(),
  external_reference text NOT NULL,
  UNIQUE (branch_id, shift_id, sale_date, source, external_reference)
);

CREATE INDEX IF NOT EXISTS idx_sales_imports_branch_date
  ON public.sales_imports(branch_id, sale_date);
CREATE INDEX IF NOT EXISTS idx_sales_imports_imported_by
  ON public.sales_imports(imported_by);

CREATE TABLE IF NOT EXISTS public.sales_import_items (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sales_import_id uuid NOT NULL REFERENCES public.sales_imports(id) ON DELETE CASCADE,
  product_id      uuid NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
  quantity        integer NOT NULL CHECK (quantity > 0),
  unit_price      numeric(10,2) NOT NULL CHECK (unit_price >= 0),
  created_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (sales_import_id, product_id)
);

CREATE INDEX IF NOT EXISTS idx_sales_import_items_import
  ON public.sales_import_items(sales_import_id);
CREATE INDEX IF NOT EXISTS idx_sales_import_items_product
  ON public.sales_import_items(product_id);

UPDATE public.sales_imports
SET source = 'csv_upload'
WHERE source <> 'csv_upload';
UPDATE public.sales_imports
SET external_reference = 'LEGACY-' || id::text
WHERE NULLIF(trim(COALESCE(external_reference, '')), '') IS NULL;
UPDATE public.sales_imports
SET external_reference = trim(external_reference)
WHERE external_reference IS DISTINCT FROM trim(external_reference);

ALTER TABLE public.sales_imports
  DROP CONSTRAINT IF EXISTS sales_imports_source_check;
ALTER TABLE public.sales_imports
  ADD CONSTRAINT sales_imports_source_check CHECK (source = 'csv_upload');
ALTER TABLE public.sales_imports
  ALTER COLUMN external_reference SET NOT NULL;
ALTER TABLE public.sales_imports
  DROP CONSTRAINT IF EXISTS sales_imports_external_reference_not_blank;
ALTER TABLE public.sales_imports
  ADD CONSTRAINT sales_imports_external_reference_not_blank
  CHECK (external_reference = trim(external_reference) AND external_reference <> '');
ALTER TABLE public.sales_imports
  ADD COLUMN IF NOT EXISTS sales_source text NOT NULL DEFAULT 'csv_upload';
ALTER TABLE public.sales_imports
  DROP CONSTRAINT IF EXISTS sales_imports_sales_source_check;
ALTER TABLE public.sales_imports
  ADD CONSTRAINT sales_imports_sales_source_check
  CHECK (sales_source IN ('csv_upload', 'pos_api', 'external_api'));
CREATE INDEX IF NOT EXISTS idx_sales_imports_sales_source
  ON public.sales_imports(sales_source);
CREATE UNIQUE INDEX IF NOT EXISTS idx_sales_imports_batch_reference_unique
  ON public.sales_imports (
    branch_id,
    COALESCE(shift_id, '00000000-0000-0000-0000-000000000000'::uuid),
    sale_date,
    source,
    external_reference
  );

CREATE TABLE IF NOT EXISTS public.sales_import_failures (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  branch_id     uuid,
  shift_id      uuid,
  sale_date     date,
  source        text NOT NULL DEFAULT 'csv_upload',
  sales_source  text NOT NULL DEFAULT 'csv_upload'
                 CHECK (sales_source IN ('csv_upload', 'pos_api', 'external_api')),
  error_message text NOT NULL,
  raw_payload   jsonb,
  attempted_by  uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  attempted_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_sales_import_failures_branch_date
  ON public.sales_import_failures(branch_id, sale_date);
CREATE INDEX IF NOT EXISTS idx_sales_import_failures_attempted_by
  ON public.sales_import_failures(attempted_by);
ALTER TABLE public.sales_import_failures
  ADD COLUMN IF NOT EXISTS sales_source text NOT NULL DEFAULT 'csv_upload';
ALTER TABLE public.sales_import_failures
  DROP CONSTRAINT IF EXISTS sales_import_failures_sales_source_check;
ALTER TABLE public.sales_import_failures
  ADD CONSTRAINT sales_import_failures_sales_source_check
  CHECK (sales_source IN ('csv_upload', 'pos_api', 'external_api'));
CREATE INDEX IF NOT EXISTS idx_sales_import_failures_sales_source
  ON public.sales_import_failures(sales_source);

-- ─────────────────────────────────────────────────────────────
-- 11. NOTIFICATIONS & OPERATIONS TRACKING
-- ─────────────────────────────────────────────────────────────
-- ─────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.notifications (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  type        text NOT NULL,
  title       text NOT NULL,
  message     text NOT NULL,
  data        jsonb,
  is_read     boolean NOT NULL DEFAULT false,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.issue_reports (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  branch_id      uuid NOT NULL REFERENCES public.branches(id) ON DELETE CASCADE,
  reported_by    uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  title          text NOT NULL,
  description    text NOT NULL,
  priority       text NOT NULL DEFAULT 'medium'
                 CHECK (priority IN ('low', 'medium', 'high', 'critical')),
  status         text NOT NULL DEFAULT 'open'
                 CHECK (status IN ('open', 'in_progress', 'resolved', 'closed')),
  resolution_note text,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now(),
  resolved_at    timestamptz
);

CREATE TABLE IF NOT EXISTS public.leave_requests (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  branch_id      uuid NOT NULL REFERENCES public.branches(id) ON DELETE CASCADE,
  employee_id    uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  start_date     date NOT NULL,
  end_date       date NOT NULL,
  reason         text NOT NULL,
  status         text NOT NULL DEFAULT 'pending'
                 CHECK (status IN ('pending', 'approved', 'rejected')),
  manager_comment text,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_notifications_user_unread
  ON public.notifications(user_id, is_read);
CREATE INDEX IF NOT EXISTS idx_issue_reports_branch_status
  ON public.issue_reports(branch_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_leave_requests_branch_status
  ON public.leave_requests(branch_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_leave_requests_employee
  ON public.leave_requests(employee_id, created_at DESC);

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

CREATE TRIGGER issue_reports_touch_updated_at
BEFORE UPDATE ON public.issue_reports
FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

CREATE TRIGGER leave_requests_touch_updated_at
BEFORE UPDATE ON public.leave_requests
FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

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

DROP TRIGGER IF EXISTS attendance_employee_write_guard ON public.attendance;
CREATE TRIGGER attendance_employee_write_guard
BEFORE INSERT OR UPDATE ON public.attendance
FOR EACH ROW EXECUTE FUNCTION public.enforce_employee_attendance_write();

DROP TRIGGER IF EXISTS attendance_touch_updated_at ON public.attendance;
CREATE TRIGGER attendance_touch_updated_at
BEFORE UPDATE ON public.attendance
FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

DROP POLICY IF EXISTS "issue_reports_select_own" ON public.issue_reports;
DROP POLICY IF EXISTS "issue_reports_select_branch" ON public.issue_reports;
DROP POLICY IF EXISTS "issue_reports_select_admin" ON public.issue_reports;
DROP POLICY IF EXISTS "issue_reports_insert" ON public.issue_reports;
DROP POLICY IF EXISTS "issue_reports_update" ON public.issue_reports;
CREATE POLICY "issue_reports_select_own" ON public.issue_reports FOR SELECT USING (reported_by = auth.uid());
CREATE POLICY "issue_reports_select_branch" ON public.issue_reports FOR SELECT USING (
  public.get_my_role() = 'manager'
  AND branch_id = public.get_my_branch_id()
);
CREATE POLICY "issue_reports_select_admin" ON public.issue_reports FOR SELECT USING (
  public.get_my_role() = 'admin'
);
CREATE POLICY "issue_reports_insert" ON public.issue_reports FOR INSERT WITH CHECK (
  reported_by = auth.uid() AND branch_id = public.get_my_branch_id()
);
CREATE POLICY "issue_reports_update" ON public.issue_reports FOR UPDATE USING (
  reported_by = auth.uid()
  OR public.get_my_role() = 'admin'
  OR (public.get_my_role() = 'manager' AND branch_id = public.get_my_branch_id())
) WITH CHECK (
  (reported_by = auth.uid() AND branch_id = public.get_my_branch_id())
  OR public.get_my_role() = 'admin'
  OR (public.get_my_role() = 'manager' AND branch_id = public.get_my_branch_id())
);

DROP POLICY IF EXISTS "leave_requests_select_own" ON public.leave_requests;
DROP POLICY IF EXISTS "leave_requests_select_branch" ON public.leave_requests;
DROP POLICY IF EXISTS "leave_requests_insert" ON public.leave_requests;
DROP POLICY IF EXISTS "leave_requests_update" ON public.leave_requests;
CREATE POLICY "leave_requests_select_own" ON public.leave_requests FOR SELECT USING (employee_id = auth.uid());
CREATE POLICY "leave_requests_select_branch" ON public.leave_requests FOR SELECT USING (
  public.get_my_role() = 'admin'
  OR (public.get_my_role() = 'manager' AND EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid()
      AND p.is_active = true
      AND p.role = 'manager'
      AND p.branch_id = public.leave_requests.branch_id
  ))
);
CREATE POLICY "leave_requests_insert" ON public.leave_requests FOR INSERT WITH CHECK (
  employee_id = auth.uid()
  AND status = 'pending'
  AND EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid()
      AND p.is_active = true
      AND p.role = 'employee'
      AND p.branch_id = public.leave_requests.branch_id
  )
);

CREATE OR REPLACE FUNCTION public.audit_business_row_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row jsonb;
  v_entity_id uuid;
  v_branch_id uuid;
BEGIN
  v_row := CASE WHEN TG_OP = 'DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(NEW) END;
  v_entity_id := NULLIF(v_row ->> 'id', '')::uuid;

  IF NULLIF(v_row ->> 'branch_id', '') IS NOT NULL THEN
    v_branch_id := (v_row ->> 'branch_id')::uuid;
  END IF;

  PERFORM public.write_audit_log(
    lower(TG_TABLE_NAME || '_' || TG_OP),
    TG_TABLE_NAME,
    v_entity_id,
    v_branch_id,
    jsonb_build_object('operation', TG_OP)
  );

  RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$;
REVOKE ALL ON FUNCTION public.audit_business_row_change()
  FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS audit_sales_targets_changes ON public.sales_targets;
CREATE TRIGGER audit_sales_targets_changes
  AFTER INSERT OR UPDATE OR DELETE ON public.sales_targets
  FOR EACH ROW EXECUTE FUNCTION public.audit_business_row_change();

DROP TRIGGER IF EXISTS audit_products_changes ON public.products;
CREATE TRIGGER audit_products_changes
  AFTER INSERT OR UPDATE OR DELETE ON public.products
  FOR EACH ROW EXECUTE FUNCTION public.audit_business_row_change();

-- ─────────────────────────────────────────────────────────────
-- Tasks (Templates) Policies
DROP POLICY IF EXISTS "tasks_select" ON public.tasks;
DROP POLICY IF EXISTS "tasks_modify" ON public.tasks;
CREATE POLICY "tasks_select" ON public.tasks FOR SELECT USING (auth.uid() IS NOT NULL);
CREATE POLICY "tasks_modify" ON public.tasks FOR ALL USING (public.get_my_role() IN ('manager', 'admin'));

-- Task Assignments Policies
DROP POLICY IF EXISTS "task_assignments_select" ON public.task_assignments;
DROP POLICY IF EXISTS "task_assignments_insert_manager" ON public.task_assignments;
DROP POLICY IF EXISTS "task_assignments_update" ON public.task_assignments;
CREATE POLICY "task_assignments_select" ON public.task_assignments FOR SELECT USING (
  user_id = auth.uid() OR public.get_my_role() IN ('manager', 'admin')
);
CREATE POLICY "task_assignments_insert_manager" ON public.task_assignments FOR INSERT WITH CHECK (
  public.get_my_role() IN ('manager', 'admin')
);
CREATE POLICY "task_assignments_update" ON public.task_assignments FOR UPDATE USING (
  user_id = auth.uid() OR public.get_my_role() IN ('manager', 'admin')
);

-- Task Completions Policies (Separate Attempt History)
DROP POLICY IF EXISTS "task_completions_select" ON public.task_completions;
DROP POLICY IF EXISTS "task_completions_insert" ON public.task_completions;
DROP POLICY IF EXISTS "task_completions_update" ON public.task_completions;
CREATE POLICY "task_completions_select" ON public.task_completions FOR SELECT USING (
  submitted_by = auth.uid() OR public.get_my_role() IN ('manager', 'admin')
);
-- Employees can ONLY insert completions for tasks assigned to them
CREATE POLICY "task_completions_insert" ON public.task_completions FOR INSERT WITH CHECK (
  submitted_by = auth.uid()
  AND EXISTS (
    SELECT 1 FROM public.task_assignments ta
    WHERE ta.id = task_completions.assignment_id
      AND ta.user_id = auth.uid()
  )
);
-- Only Managers or Admins can review/update completions
CREATE POLICY "task_completions_update" ON public.task_completions FOR UPDATE USING (
  public.get_my_role() IN ('manager', 'admin')
);

-- Points Transactions Policies
DROP POLICY IF EXISTS "points_transactions_select" ON public.points_transactions;
CREATE POLICY "points_transactions_select" ON public.points_transactions FOR SELECT USING (
  user_id = auth.uid() OR public.get_my_role() IN ('manager', 'admin')
);

-- Audit Log Policies
DROP POLICY IF EXISTS "audit_log_select_admin" ON public.audit_log;
CREATE POLICY "audit_log_select_admin" ON public.audit_log FOR SELECT USING (
  public.get_my_role() = 'admin'
);

-- Sales Targets Policies
DROP POLICY IF EXISTS "sales_targets_select" ON public.sales_targets;
DROP POLICY IF EXISTS "sales_targets_modify" ON public.sales_targets;
DROP POLICY IF EXISTS "sales_targets_select_scoped" ON public.sales_targets;
DROP POLICY IF EXISTS "sales_targets_modify_scoped" ON public.sales_targets;
CREATE POLICY "sales_targets_select_scoped" ON public.sales_targets FOR SELECT USING (
  public.get_my_role() = 'admin'
  OR (public.get_my_role() = 'manager' AND branch_id = public.get_my_branch_id())
);
CREATE POLICY "sales_targets_modify_scoped" ON public.sales_targets FOR ALL USING (
  public.get_my_role() = 'admin'
  OR (public.get_my_role() = 'manager' AND branch_id = public.get_my_branch_id())
) WITH CHECK (
  public.get_my_role() = 'admin'
  OR (public.get_my_role() = 'manager' AND branch_id = public.get_my_branch_id())
);

-- Sales Entries Policies
DROP POLICY IF EXISTS "sales_entries_select" ON public.sales_entries;
DROP POLICY IF EXISTS "sales_entries_insert" ON public.sales_entries;
CREATE POLICY "sales_entries_select" ON public.sales_entries FOR SELECT USING (
  public.get_my_role() IN ('manager', 'admin')
);

-- Sales Imports Policies
DROP POLICY IF EXISTS "sales_imports_select" ON public.sales_imports;
DROP POLICY IF EXISTS "sales_imports_insert" ON public.sales_imports;
CREATE POLICY "sales_imports_select" ON public.sales_imports FOR SELECT USING (
  auth.uid() IS NOT NULL
);
CREATE POLICY "sales_imports_insert" ON public.sales_imports FOR INSERT WITH CHECK (
  public.get_my_role() = 'admin' AND imported_by = auth.uid()
);

DROP POLICY IF EXISTS "sales_import_items_select" ON public.sales_import_items;
DROP POLICY IF EXISTS "sales_import_items_insert" ON public.sales_import_items;
CREATE POLICY "sales_import_items_select" ON public.sales_import_items FOR SELECT USING (
  auth.uid() IS NOT NULL
);
CREATE POLICY "sales_import_items_insert" ON public.sales_import_items FOR INSERT WITH CHECK (
  public.get_my_role() = 'admin'
);

DROP POLICY IF EXISTS "sales_import_failures_select" ON public.sales_import_failures;
CREATE POLICY "sales_import_failures_select" ON public.sales_import_failures FOR SELECT USING (
  public.get_my_role() = 'admin'
);

-- Notifications Policies
DROP POLICY IF EXISTS "notifications_select_own" ON public.notifications;
DROP POLICY IF EXISTS "notifications_update_own" ON public.notifications;
DROP POLICY IF EXISTS "notifications_insert_all" ON public.notifications;
CREATE POLICY "notifications_select_own" ON public.notifications FOR SELECT USING (user_id = auth.uid());
CREATE POLICY "notifications_update_own" ON public.notifications FOR UPDATE USING (user_id = auth.uid());
CREATE POLICY "notifications_insert_all" ON public.notifications FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);

-- ─────────────────────────────────────────────────────────────
-- 15. SEED DATA (BRANCHES, PRODUCTS, TASKS)
-- ─────────────────────────────────────────────────────────────

INSERT INTO public.branches (id, name, location) VALUES
  ('11111111-1111-1111-1111-111111111111', 'Dhanmondi Branch', 'Dhanmondi, Dhaka'),
  ('22222222-2222-2222-2222-222222222222', 'Mirpur Branch',    'Mirpur, Dhaka'),
  ('33333333-3333-3333-3333-333333333333', 'Uttara Branch',    'Uttara, Dhaka')
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  location = EXCLUDED.location,
  is_active = true;

INSERT INTO public.company_profile (id, name, industry, headquarters, region)
VALUES (
  '99999999-9999-9999-9999-999999999999',
  'RetailFlow Demo Retail Group',
  'Convenience Retail',
  'Dhaka',
  'Bangladesh'
)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  industry = EXCLUDED.industry,
  headquarters = EXCLUDED.headquarters,
  region = EXCLUDED.region;

INSERT INTO public.products (name, category)
SELECT v.name, v.category
FROM (VALUES
  ('Coca-Cola'::text,     'Beverage'::text),
  ('Pepsi'::text,         'Beverage'::text),
  ('Chips'::text,         'Snacks'::text),
  ('7-Up'::text,          'Beverage'::text),
  ('Mineral Water'::text, 'Beverage'::text)
) AS v(name, category)
WHERE NOT EXISTS (
  SELECT 1 FROM public.products p
  WHERE lower(p.name) = lower(v.name)
    AND lower(p.category) = lower(v.category)
);

INSERT INTO public.tasks (title, description, frequency, branch_id, base_points, photo_bonus_points, photo_required)
SELECT v.title, v.description, v.frequency, v.branch_id, v.base_points, v.photo_bonus_points, v.photo_required
FROM (VALUES
  ('Shelf Restocking',    'Restock all beverage shelves to full capacity.',   'daily',  '11111111-1111-1111-1111-111111111111'::uuid, 10, 5, true),
  ('Store Cleaning',      'Clean store entrance, checkout, and aisles.',      'daily',  '11111111-1111-1111-1111-111111111111'::uuid, 10, 5, true),
  ('Inventory Audit',     'Count physical stock vs recorded inventory.',       'weekly', '11111111-1111-1111-1111-111111111111'::uuid, 30, 10, false),
  ('Display Setup',       'Set up promotional banner and end-cap displays.',   'weekly', '11111111-1111-1111-1111-111111111111'::uuid, 20, 5, true)
) AS v(title, description, frequency, branch_id, base_points, photo_bonus_points, photo_required)
WHERE NOT EXISTS (
  SELECT 1 FROM public.tasks t
  WHERE t.title = v.title AND t.branch_id = v.branch_id
);

-- =============================================================
-- SQL VERIFICATION EXAMPLES & TEST QUERIES
-- =============================================================

-- =============================================================
-- FINAL CLIENT API DEFINITIONS
-- These definitions must remain after all tables, functions, and policies.
-- =============================================================

DROP FUNCTION IF EXISTS public.record_sale(uuid, uuid, date, uuid, integer);

CREATE OR REPLACE FUNCTION public.import_sales_data(
  p_branch_id uuid,
  p_shift_id uuid,
  p_sale_date date,
  p_source text,
  p_total_amount numeric,
  p_external_reference text DEFAULT NULL,
  p_items jsonb DEFAULT '[]'::jsonb
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  caller_id uuid := auth.uid();
  caller_branch uuid;
  caller_role text;
  import_id uuid;
  item jsonb;
  product_row public.products%ROWTYPE;
  previous_sales numeric;
  target_amount numeric;
  failure_id uuid;
BEGIN
  SELECT role, branch_id INTO caller_role, caller_branch
  FROM public.profiles
  WHERE id = caller_id AND is_active = true;

  IF caller_id IS NULL OR caller_role <> 'admin' THEN
    RAISE EXCEPTION 'Only admins can import CSV sales data';
  END IF;

  IF p_total_amount IS NULL OR p_total_amount < 0
     OR p_sale_date IS NULL
     OR p_sale_date > CURRENT_DATE + 30 THEN
    RAISE EXCEPTION 'Invalid sales import';
  END IF;

  IF NULLIF(trim(COALESCE(p_external_reference, '')), '') IS NULL THEN
    RAISE EXCEPTION 'CSV batch reference is required';
  END IF;

  IF COALESCE(p_source, '') <> 'csv_upload' THEN
    RAISE EXCEPTION 'Only CSV sales imports are supported';
  END IF;

  IF p_shift_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.shifts
    WHERE id = p_shift_id AND branch_id = p_branch_id AND is_active
  ) THEN
    RAISE EXCEPTION 'Invalid branch shift';
  END IF;

  SELECT COALESCE(SUM(total_amount), 0) INTO previous_sales
  FROM public.sales_imports
  WHERE branch_id = p_branch_id
    AND shift_id IS NOT DISTINCT FROM p_shift_id
    AND sale_date = p_sale_date;

  IF EXISTS (
    SELECT 1
    FROM public.sales_imports si
    WHERE si.branch_id = p_branch_id
      AND si.shift_id IS NOT DISTINCT FROM p_shift_id
      AND si.sale_date = p_sale_date
      AND si.source = 'csv_upload'
      AND si.external_reference IS NOT DISTINCT FROM NULLIF(trim(COALESCE(p_external_reference, '')), '')
  ) THEN
    RAISE EXCEPTION 'Duplicate CSV import for this branch, shift, date, and batch reference';
  END IF;

  INSERT INTO public.sales_imports(
    branch_id,
    shift_id,
    sale_date,
    source,
    sales_source,
    total_amount,
    imported_by,
    external_reference
  )
  VALUES (
    p_branch_id,
    p_shift_id,
    p_sale_date,
    'csv_upload',
    'csv_upload',
    p_total_amount,
    caller_id,
    NULLIF(trim(COALESCE(p_external_reference, '')), '')
  )
  RETURNING id INTO import_id;

  FOR item IN SELECT * FROM jsonb_array_elements(COALESCE(p_items, '[]'::jsonb))
  LOOP
    IF NULLIF(item ->> 'product_id', '') IS NULL THEN
      RAISE EXCEPTION 'Product item is missing product_id';
    END IF;
    SELECT * INTO product_row
    FROM public.products
    WHERE id = (item ->> 'product_id')::uuid AND is_active;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Product is inactive or missing';
    END IF;
    IF COALESCE((item ->> 'quantity')::integer, 0) <= 0 THEN
      RAISE EXCEPTION 'Imported product quantity must be positive';
    END IF;
    INSERT INTO public.sales_import_items(
      sales_import_id,
      product_id,
      quantity,
      unit_price
    )
    VALUES (
      import_id,
      product_row.id,
      (item ->> 'quantity')::integer,
      0
    );
  END LOOP;

  SELECT st.target_amount INTO target_amount
  FROM public.sales_targets st
  WHERE st.branch_id = p_branch_id
    AND st.shift_id IS NOT DISTINCT FROM p_shift_id
    AND st.target_date = p_sale_date;

  IF target_amount IS NOT NULL
     AND previous_sales < target_amount
     AND previous_sales + p_total_amount >= target_amount THEN
    INSERT INTO public.notifications (user_id, type, title, message, data)
    SELECT b.manager_id, 'target_achieved', 'Sales Target Achieved',
      'Your branch achieved its sales target for ' || p_sale_date || '.',
      jsonb_build_object(
        'branch_id', p_branch_id,
        'shift_id', p_shift_id,
        'sale_date', p_sale_date,
        'actual', previous_sales + p_total_amount,
        'target', target_amount
      )
    FROM public.branches b
    WHERE b.id = p_branch_id AND b.manager_id IS NOT NULL;
  END IF;

  PERFORM public.write_audit_log(
    'sales_import_created',
    'sales_import',
    import_id,
    p_branch_id,
    jsonb_build_object(
      'shift_id', p_shift_id,
      'sale_date', p_sale_date,
      'source', 'csv_upload',
      'sales_source', 'csv_upload',
      'total_amount', p_total_amount,
      'external_reference', NULLIF(trim(COALESCE(p_external_reference, '')), '')
    ),
    caller_id
  );

  RETURN jsonb_build_object('success', true, 'id', import_id);
EXCEPTION WHEN others THEN
  IF caller_id IS NOT NULL
     AND EXISTS (SELECT 1 FROM public.profiles WHERE id = caller_id) THEN
    INSERT INTO public.sales_import_failures(
      branch_id,
      shift_id,
      sale_date,
      source,
      sales_source,
      error_message,
      raw_payload,
      attempted_by
    )
    VALUES (
      p_branch_id,
      p_shift_id,
      p_sale_date,
      'csv_upload',
      'csv_upload',
      SQLERRM,
      jsonb_build_object(
        'total_amount', p_total_amount,
        'external_reference', p_external_reference,
        'items', COALESCE(p_items, '[]'::jsonb)
      ),
      caller_id
    )
    RETURNING id INTO failure_id;

    PERFORM public.write_audit_log(
      'sales_import_failed',
      'sales_import_failure',
      failure_id,
      p_branch_id,
      jsonb_build_object(
        'shift_id', p_shift_id,
        'sale_date', p_sale_date,
        'source', 'csv_upload',
        'sales_source', 'csv_upload',
        'error', SQLERRM,
        'external_reference', p_external_reference
      ),
      caller_id
    );
  END IF;

  RETURN jsonb_build_object(
    'success', false,
    'error', SQLERRM,
    'failure_id', failure_id
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.assign_employee_to_shift(
  p_employee_id uuid, p_shift_id uuid, p_work_date date
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE caller_role text; caller_branch uuid; employee_branch uuid; shift_branch uuid; assignment_id uuid;
BEGIN
  SELECT role, branch_id INTO caller_role, caller_branch FROM public.profiles
  WHERE id = auth.uid() AND is_active = true;
  SELECT branch_id INTO employee_branch FROM public.profiles
  WHERE id = p_employee_id AND role = 'employee' AND is_active = true;
  SELECT branch_id INTO shift_branch FROM public.shifts WHERE id = p_shift_id AND is_active = true;
  IF caller_role NOT IN ('manager', 'admin') OR p_work_date IS NULL
     OR employee_branch IS NULL OR shift_branch IS NULL
     OR employee_branch IS DISTINCT FROM shift_branch
     OR (caller_role = 'manager' AND shift_branch IS DISTINCT FROM caller_branch) THEN
    RAISE EXCEPTION 'Assignment is outside the caller scope';
  END IF;
  INSERT INTO public.employee_shifts(employee_id, shift_id, work_date)
  VALUES (p_employee_id, p_shift_id, p_work_date)
  RETURNING id INTO assignment_id;
  INSERT INTO public.notifications (user_id, type, title, message, data)
  VALUES (p_employee_id, 'shift_assigned', 'Shift Assigned',
    'You have been assigned to a shift on ' || p_work_date || '.',
    jsonb_build_object('employee_shift_id', assignment_id, 'shift_id', p_shift_id, 'work_date', p_work_date));
  PERFORM public.write_audit_log(
    'shift_assigned',
    'employee_shift',
    assignment_id,
    shift_branch,
    jsonb_build_object(
      'employee_id', p_employee_id,
      'shift_id', p_shift_id,
      'work_date', p_work_date
    )
  );
  RETURN jsonb_build_object('id', assignment_id);
END;
$$;
GRANT EXECUTE ON FUNCTION public.assign_employee_to_shift(uuid, uuid, date) TO authenticated;

DROP FUNCTION IF EXISTS public.assign_task(uuid, uuid, date);
CREATE OR REPLACE FUNCTION public.assign_task(
  p_task_id uuid,
  p_user_id uuid,
  p_scheduled_date date,
  p_due_at timestamptz DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE caller_role text; caller_branch uuid; task_row public.tasks%ROWTYPE;
  employee_branch uuid; assignment_id uuid;
BEGIN
  SELECT role, branch_id INTO caller_role, caller_branch FROM public.profiles
  WHERE id = auth.uid() AND is_active = true;
  SELECT * INTO task_row FROM public.tasks WHERE id = p_task_id AND is_active = true;
  SELECT branch_id INTO employee_branch FROM public.profiles
  WHERE id = p_user_id AND role = 'employee' AND is_active = true;
  IF caller_role NOT IN ('manager', 'admin') OR task_row.id IS NULL OR employee_branch IS NULL
     OR (caller_role = 'manager' AND COALESCE(task_row.branch_id, employee_branch) IS DISTINCT FROM caller_branch)
     OR (task_row.branch_id IS NOT NULL AND task_row.branch_id IS DISTINCT FROM employee_branch) THEN
    RAISE EXCEPTION 'Task assignment is outside the caller scope';
  END IF;
  INSERT INTO public.task_assignments(task_id, user_id, scheduled_date, due_at, status)
  VALUES (p_task_id, p_user_id, p_scheduled_date,
    COALESCE(
      p_due_at,
      CASE WHEN task_row.deadline_hours_after_assignment IS NULL THEN NULL
        ELSE now() + (task_row.deadline_hours_after_assignment || ' hours')::interval END
    ),
    'pending')
  RETURNING id INTO assignment_id;
  INSERT INTO public.notifications (user_id, type, title, message, data)
  VALUES (p_user_id, 'task_assigned', 'New Task Assigned',
    'You have been assigned "' || task_row.title || '" for ' || p_scheduled_date || '.',
    jsonb_build_object('assignment_id', assignment_id));
  PERFORM public.write_audit_log(
    'task_assigned',
    'task_assignment',
    assignment_id,
    employee_branch,
    jsonb_build_object(
      'task_id', p_task_id,
      'employee_id', p_user_id,
      'scheduled_date', p_scheduled_date,
      'due_at', COALESCE(
        p_due_at,
        CASE WHEN task_row.deadline_hours_after_assignment IS NULL THEN NULL
          ELSE now() + (task_row.deadline_hours_after_assignment || ' hours')::interval END
      )
    )
  );
  RETURN jsonb_build_object('id', assignment_id);
END;
$$;
GRANT EXECUTE ON FUNCTION public.assign_task(uuid, uuid, date, timestamptz) TO authenticated;

CREATE OR REPLACE FUNCTION public.submit_task_completion(
  p_assignment_id uuid, p_completion_note text DEFAULT NULL, p_photo_url text DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE caller_id uuid := auth.uid(); assignment_row public.task_assignments%ROWTYPE;
  next_attempt integer; completion_id uuid; task_title text; employee_branch uuid;
BEGIN
  SELECT * INTO assignment_row FROM public.task_assignments
  WHERE id = p_assignment_id AND user_id = caller_id
  FOR UPDATE;
  IF caller_id IS NULL OR assignment_row.id IS NULL
     OR assignment_row.status IN ('approved', 'completed') THEN
    RAISE EXCEPTION 'Assignment is not available for submission';
  END IF;
  SELECT COALESCE(MAX(attempt_number), 0) + 1 INTO next_attempt
  FROM public.task_completions WHERE assignment_id = p_assignment_id;
  INSERT INTO public.task_completions(
    assignment_id, attempt_number, submitted_by, completion_note, photo_url, status, points_awarded
  ) VALUES (
    p_assignment_id, next_attempt, caller_id, p_completion_note, p_photo_url, 'submitted', 0
  ) RETURNING id INTO completion_id;
  UPDATE public.task_assignments SET status = 'completed' WHERE id = p_assignment_id;

  SELECT t.title INTO task_title
  FROM public.tasks t
  WHERE t.id = assignment_row.task_id;

  SELECT branch_id INTO employee_branch
  FROM public.profiles
  WHERE id = caller_id;

  INSERT INTO public.notifications (user_id, type, title, message, data)
  SELECT b.manager_id,
    'pending_approval',
    'Task Pending Approval',
    'A completion for "' || COALESCE(task_title, 'Task') || '" is ready for review.',
    jsonb_build_object('assignment_id', p_assignment_id, 'completion_id', completion_id)
  FROM public.profiles p
  JOIN public.branches b ON b.id = p.branch_id
  WHERE p.id = caller_id AND b.manager_id IS NOT NULL;

  PERFORM public.write_audit_log(
    'task_completion_submitted',
    'task_completion',
    completion_id,
    employee_branch,
    jsonb_build_object(
      'assignment_id', p_assignment_id,
      'task_id', assignment_row.task_id,
      'attempt_number', next_attempt,
      'has_photo', NULLIF(trim(COALESCE(p_photo_url, '')), '') IS NOT NULL
    ),
    caller_id
  );

  RETURN jsonb_build_object('id', completion_id);
END;
$$;
GRANT EXECUTE ON FUNCTION public.submit_task_completion(uuid, text, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_shift_sales_performance(
  p_branch_id uuid, p_shift_id uuid, p_date date
)
RETURNS TABLE(actual numeric, target numeric, achievement_rate numeric)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE((SELECT SUM(si.total_amount) FROM public.sales_imports si
    WHERE si.branch_id = p_branch_id AND si.shift_id IS NOT DISTINCT FROM p_shift_id AND si.sale_date = p_date), 0),
    COALESCE((SELECT st.target_amount FROM public.sales_targets st
      WHERE st.branch_id = p_branch_id AND st.shift_id IS NOT DISTINCT FROM p_shift_id AND st.target_date = p_date), 0),
    CASE WHEN COALESCE((SELECT st.target_amount FROM public.sales_targets st
      WHERE st.branch_id = p_branch_id AND st.shift_id IS NOT DISTINCT FROM p_shift_id AND st.target_date = p_date), 0) > 0
      THEN COALESCE((SELECT SUM(si.total_amount) FROM public.sales_imports si
        WHERE si.branch_id = p_branch_id AND si.shift_id IS NOT DISTINCT FROM p_shift_id AND si.sale_date = p_date), 0)
        / (SELECT st.target_amount FROM public.sales_targets st
          WHERE st.branch_id = p_branch_id AND st.shift_id IS NOT DISTINCT FROM p_shift_id AND st.target_date = p_date) * 100
      ELSE 0 END
  WHERE public.get_my_role() = 'admin'
     OR (public.get_my_role() = 'manager' AND public.get_my_branch_id() = p_branch_id);
$$;
GRANT EXECUTE ON FUNCTION public.get_shift_sales_performance(uuid, uuid, date) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_branch_shift_sales_performance(
  p_branch_id uuid, p_from date, p_to date
)
RETURNS TABLE(shift_id uuid, shift_name text, sale_date date, actual numeric, target numeric, achievement_rate numeric)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  WITH keys AS (
    SELECT si.shift_id, si.sale_date FROM public.sales_imports si
    WHERE si.branch_id = p_branch_id AND si.sale_date BETWEEN p_from AND p_to
    UNION
    SELECT st.shift_id, st.target_date FROM public.sales_targets st
    WHERE st.branch_id = p_branch_id AND st.target_date BETWEEN p_from AND p_to
  ), totals AS (
    SELECT k.shift_id, k.sale_date,
      COALESCE((SELECT SUM(si.total_amount) FROM public.sales_imports si WHERE si.branch_id = p_branch_id
        AND si.shift_id IS NOT DISTINCT FROM k.shift_id AND si.sale_date = k.sale_date), 0) AS actual,
      COALESCE((SELECT st.target_amount FROM public.sales_targets st WHERE st.branch_id = p_branch_id
        AND st.shift_id IS NOT DISTINCT FROM k.shift_id AND st.target_date = k.sale_date), 0) AS target
    FROM keys k
  )
  SELECT t.shift_id, COALESCE(s.name, 'No Shift'), t.sale_date, t.actual, t.target,
    CASE WHEN t.target > 0 THEN t.actual / t.target * 100 ELSE 0 END
  FROM totals t LEFT JOIN public.shifts s ON s.id = t.shift_id
  WHERE public.get_my_role() = 'admin'
     OR (public.get_my_role() = 'manager' AND public.get_my_branch_id() = p_branch_id)
  ORDER BY t.sale_date, COALESCE(s.name, 'No Shift');
$$;
GRANT EXECUTE ON FUNCTION public.get_branch_shift_sales_performance(uuid, date, date) TO authenticated;

CREATE OR REPLACE FUNCTION public.create_deadline_reminders()
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE reminder_count integer := 0;
BEGIN
  IF auth.uid() IS NOT NULL AND COALESCE(public.get_my_role(), '') NOT IN ('manager', 'admin') THEN
    RAISE EXCEPTION 'Only managers, admins, or the scheduler can create deadline reminders';
  END IF;

  INSERT INTO public.notifications (user_id, type, title, message, data)
  SELECT
    ta.user_id,
    'deadline_reminder',
    'Task Deadline Approaching',
    'Your task "' || COALESCE(t.title, 'Task') || '" is due soon.',
    jsonb_build_object('assignment_id', ta.id, 'due_at', ta.due_at)
  FROM public.task_assignments ta
  JOIN public.tasks t ON t.id = ta.task_id
  WHERE ta.status = 'pending'
    AND ta.due_at IS NOT NULL
    AND ta.due_at > now()
    AND ta.due_at <= now() + interval '4 hours'
    AND NOT EXISTS (
      SELECT 1
      FROM public.notifications n
      WHERE n.user_id = ta.user_id
        AND n.type = 'deadline_reminder'
        AND n.data ->> 'assignment_id' = ta.id::text
    );

  GET DIAGNOSTICS reminder_count = ROW_COUNT;
  RETURN reminder_count;
END;
$$;
GRANT EXECUTE ON FUNCTION public.create_deadline_reminders() TO authenticated;

CREATE OR REPLACE FUNCTION public.mark_absent_employees()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_inserted_count integer := 0;
BEGIN
  IF auth.uid() IS NOT NULL AND COALESCE(public.get_my_role(), '') NOT IN ('manager', 'admin') THEN
    RAISE EXCEPTION 'Only managers, admins, or the scheduler can mark absent employees';
  END IF;

  IF (now() AT TIME ZONE 'Asia/Dhaka')::time < '09:30:00' THEN
    RETURN 0;
  END IF;

  INSERT INTO public.attendance (employee_id, branch_id, attendance_date, status)
  SELECT p.id, p.branch_id, public.retailflow_current_date(), 'absent'
  FROM public.profiles p
  WHERE p.is_active = true
    AND p.role = 'employee'
    AND p.branch_id IS NOT NULL
    AND NOT EXISTS (
      SELECT 1
      FROM public.attendance a
      WHERE a.employee_id = p.id
        AND a.attendance_date = public.retailflow_current_date()
    )
  ON CONFLICT (employee_id, attendance_date) DO NOTHING;

  GET DIAGNOSTICS v_inserted_count = ROW_COUNT;
  RETURN v_inserted_count;
END;
$$;
GRANT EXECUTE ON FUNCTION public.mark_absent_employees() TO authenticated;

-- Enable pg_cron in the Supabase dashboard, then run this block once as a privileged role.
-- This keeps only the operational deadline reminders and daily absence marking needed by the retail flow.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'retailflow-deadline-reminders') THEN
      PERFORM cron.schedule('retailflow-deadline-reminders', '*/30 * * * *',
        'SELECT public.create_deadline_reminders();');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'retailflow-mark-absent-employees') THEN
      PERFORM cron.schedule('retailflow-mark-absent-employees', '30 9 * * *',
        'SELECT public.mark_absent_employees();');
    END IF;
  END IF;
EXCEPTION WHEN undefined_table OR undefined_function THEN
  NULL;
END;
$$;

DROP POLICY IF EXISTS "profiles_update_admin_or_self" ON public.profiles;
DROP POLICY IF EXISTS "profiles_update_admin_only" ON public.profiles;
CREATE POLICY "profiles_update_admin_only" ON public.profiles FOR UPDATE
  USING (public.get_my_role() = 'admin') WITH CHECK (public.get_my_role() = 'admin');
DROP POLICY IF EXISTS "notifications_insert_all" ON public.notifications;
DROP POLICY IF EXISTS "notifications_insert_own" ON public.notifications;
CREATE POLICY "notifications_insert_own" ON public.notifications FOR INSERT
  WITH CHECK (user_id = auth.uid());
DROP FUNCTION IF EXISTS public.record_sale(uuid, uuid, date, uuid, integer);
GRANT EXECUTE ON FUNCTION public.import_sales_data(uuid, uuid, date, text, numeric, text, jsonb)
  TO authenticated;
CREATE OR REPLACE FUNCTION public.approve_task_completion(
  p_completion_id uuid, p_review_note text DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE caller_id uuid := auth.uid(); caller_role text; caller_branch uuid;
  employee_branch uuid; assignment_user uuid;
BEGIN
  SELECT role, branch_id INTO caller_role, caller_branch FROM public.profiles WHERE id = caller_id;
  IF caller_id IS NULL OR caller_role NOT IN ('manager', 'admin') THEN
    RAISE EXCEPTION 'Only managers or admins can approve completions';
  END IF;
  SELECT ta.user_id, p.branch_id INTO assignment_user, employee_branch
  FROM public.task_completions tc
  JOIN public.task_assignments ta ON ta.id = tc.assignment_id
  JOIN public.profiles p ON p.id = ta.user_id
  WHERE tc.id = p_completion_id;
  IF assignment_user IS NULL OR
     (caller_role = 'manager' AND employee_branch IS DISTINCT FROM caller_branch) THEN
    RAISE EXCEPTION 'Completion is outside the reviewer scope';
  END IF;
  PERFORM public.approve_task_completion(p_completion_id, caller_id, p_review_note);
  RETURN jsonb_build_object('success', true);
END;
$$;
GRANT EXECUTE ON FUNCTION public.approve_task_completion(uuid, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.reject_task_completion(p_completion_id uuid, p_review_note text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE caller_id uuid := auth.uid(); caller_role text; caller_branch uuid;
  employee_branch uuid; assignment_user uuid; task_title text;
BEGIN
  SELECT role, branch_id INTO caller_role, caller_branch FROM public.profiles WHERE id = caller_id AND is_active = true;
  SELECT ta.user_id, p.branch_id, t.title INTO assignment_user, employee_branch, task_title
  FROM public.task_completions tc
  JOIN public.task_assignments ta ON ta.id = tc.assignment_id
  JOIN public.profiles p ON p.id = ta.user_id
  JOIN public.tasks t ON t.id = ta.task_id
  WHERE tc.id = p_completion_id;
  IF caller_id IS NULL OR caller_role NOT IN ('manager', 'admin')
     OR assignment_user IS NULL
     OR (caller_role = 'manager' AND employee_branch IS DISTINCT FROM caller_branch)
     OR NULLIF(trim(p_review_note), '') IS NULL THEN
    RAISE EXCEPTION 'Authorized reviewer and reason are required';
  END IF;
  UPDATE public.task_completions SET status = 'rejected', reviewed_by = caller_id,
    reviewed_at = now(), review_note = trim(p_review_note)
  WHERE id = p_completion_id AND status = 'submitted';
  IF NOT FOUND THEN RAISE EXCEPTION 'Completion is not available'; END IF;
  UPDATE public.task_assignments ta SET status = 'rejected'
  WHERE ta.id = (SELECT assignment_id FROM public.task_completions WHERE id = p_completion_id);
  INSERT INTO public.notifications (user_id, type, title, message, data)
  VALUES (assignment_user, 'task_rejected', 'Task Needs Attention',
    'Your task "' || task_title || '" was rejected: ' || trim(p_review_note),
    jsonb_build_object('completion_id', p_completion_id, 'review_note', trim(p_review_note)));
  PERFORM public.write_audit_log(
    'task_completion_rejected',
    'task_completion',
    p_completion_id,
    employee_branch,
    jsonb_build_object(
      'employee_id', assignment_user,
      'review_note', trim(p_review_note),
      'task_title', task_title
    ),
    caller_id
  );
  RETURN jsonb_build_object('success', true);
END;
$$;
GRANT EXECUTE ON FUNCTION public.reject_task_completion(uuid, text) TO authenticated;

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

INSERT INTO storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
VALUES ('task-photos', 'task-photos', false, 5242880,
  ARRAY['image/jpeg','image/png','image/webp','image/heic','image/gif'])
ON CONFLICT (id) DO UPDATE SET public = false, file_size_limit = 5242880;

DROP POLICY IF EXISTS "task_photos_upload_own" ON storage.objects;
CREATE POLICY "task_photos_upload_own" ON storage.objects FOR INSERT
  WITH CHECK (bucket_id = 'task-photos' AND (storage.foldername(name))[1] = auth.uid()::text);

-- Final branch-scoped access rules. These replace the permissive baseline rules.
DROP POLICY IF EXISTS "profiles_select_all_authenticated" ON public.profiles;
DROP POLICY IF EXISTS "profiles_select_scoped" ON public.profiles;
CREATE POLICY "profiles_select_scoped" ON public.profiles FOR SELECT USING (
  id = auth.uid()
  OR public.get_my_role() = 'admin'
  OR (public.get_my_role() = 'manager' AND branch_id = public.get_my_branch_id())
);

DROP POLICY IF EXISTS "shifts_select" ON public.shifts;
DROP POLICY IF EXISTS "shifts_modify" ON public.shifts;
DROP POLICY IF EXISTS "shifts_select_scoped" ON public.shifts;
DROP POLICY IF EXISTS "shifts_modify_scoped" ON public.shifts;
CREATE POLICY "shifts_select_scoped" ON public.shifts FOR SELECT USING (
  public.get_my_role() = 'admin' OR branch_id = public.get_my_branch_id()
);
CREATE POLICY "shifts_modify_scoped" ON public.shifts FOR ALL USING (
  public.get_my_role() = 'admin'
  OR (public.get_my_role() = 'manager' AND branch_id = public.get_my_branch_id())
) WITH CHECK (
  public.get_my_role() = 'admin'
  OR (public.get_my_role() = 'manager' AND branch_id = public.get_my_branch_id())
);

DROP POLICY IF EXISTS "employee_shifts_select" ON public.employee_shifts;
DROP POLICY IF EXISTS "employee_shifts_modify" ON public.employee_shifts;
DROP POLICY IF EXISTS "employee_shifts_modify_scoped" ON public.employee_shifts;
DROP POLICY IF EXISTS "employee_shifts_select_scoped" ON public.employee_shifts;
DROP POLICY IF EXISTS "employee_shifts_update_scoped" ON public.employee_shifts;
DROP POLICY IF EXISTS "employee_shifts_delete_scoped" ON public.employee_shifts;
CREATE POLICY "employee_shifts_select_scoped" ON public.employee_shifts FOR SELECT USING (
  employee_id = auth.uid()
  OR public.get_my_role() = 'admin'
  OR (public.get_my_role() = 'manager' AND EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = employee_shifts.employee_id AND p.branch_id = public.get_my_branch_id()
  ))
);
CREATE POLICY "employee_shifts_update_scoped" ON public.employee_shifts FOR UPDATE USING (
  public.get_my_role() = 'admin'
  OR (public.get_my_role() = 'manager' AND EXISTS (
    SELECT 1 FROM public.profiles p
    JOIN public.shifts s ON s.id = employee_shifts.shift_id
    WHERE p.id = employee_shifts.employee_id
      AND p.branch_id = public.get_my_branch_id()
      AND s.branch_id = public.get_my_branch_id()
  ))
) WITH CHECK (
  public.get_my_role() = 'admin'
  OR (public.get_my_role() = 'manager' AND EXISTS (
    SELECT 1 FROM public.profiles p JOIN public.shifts s ON s.id = employee_shifts.shift_id
    WHERE p.id = employee_shifts.employee_id
      AND p.branch_id = public.get_my_branch_id() AND s.branch_id = public.get_my_branch_id()
  ))
);
CREATE POLICY "employee_shifts_delete_scoped" ON public.employee_shifts FOR DELETE USING (
  public.get_my_role() = 'admin'
  OR (public.get_my_role() = 'manager' AND EXISTS (
    SELECT 1 FROM public.profiles p
    JOIN public.shifts s ON s.id = employee_shifts.shift_id
    WHERE p.id = employee_shifts.employee_id
      AND p.branch_id = public.get_my_branch_id()
      AND s.branch_id = public.get_my_branch_id()
  ))
);

DROP POLICY IF EXISTS "tasks_select" ON public.tasks;
DROP POLICY IF EXISTS "tasks_modify" ON public.tasks;
DROP POLICY IF EXISTS "tasks_select_scoped" ON public.tasks;
DROP POLICY IF EXISTS "tasks_modify_scoped" ON public.tasks;
CREATE POLICY "tasks_select_scoped" ON public.tasks FOR SELECT USING (
  public.get_my_role() = 'admin'
  OR (public.get_my_role() = 'manager'
      AND (branch_id IS NULL OR branch_id = public.get_my_branch_id()))
  OR (public.get_my_role() = 'employee' AND EXISTS (
    SELECT 1
    FROM public.task_assignments ta
    WHERE ta.task_id = tasks.id
      AND ta.user_id = auth.uid()
  ))
);
CREATE POLICY "tasks_modify_scoped" ON public.tasks FOR ALL USING (
  public.get_my_role() = 'admin'
  OR (public.get_my_role() = 'manager' AND branch_id = public.get_my_branch_id())
) WITH CHECK (
  (
    public.get_my_role() = 'admin'
    OR (public.get_my_role() = 'manager' AND branch_id = public.get_my_branch_id())
  )
  AND (
    assigned_user_id IS NULL
    OR EXISTS (
      SELECT 1
      FROM public.profiles p
      WHERE p.id = tasks.assigned_user_id
        AND p.role = 'employee'
        AND p.is_active = true
        AND (tasks.branch_id IS NULL OR p.branch_id = tasks.branch_id)
    )
  )
);

DROP POLICY IF EXISTS "products_select" ON public.products;
DROP POLICY IF EXISTS "products_modify_manager_admin" ON public.products;
DROP POLICY IF EXISTS "products_select_manager_admin" ON public.products;
DROP POLICY IF EXISTS "products_select_auth" ON public.products;
DROP POLICY IF EXISTS "products_modify_manager_admin_final" ON public.products;
DROP POLICY IF EXISTS "products_insert_manager_admin" ON public.products;
DROP POLICY IF EXISTS "products_update_manager_admin" ON public.products;
CREATE POLICY "products_select_auth" ON public.products FOR SELECT USING (
  auth.uid() IS NOT NULL
);
CREATE POLICY "products_insert_manager_admin" ON public.products FOR INSERT WITH CHECK (
  public.get_my_role() IN ('manager', 'admin')
);
CREATE POLICY "products_update_manager_admin" ON public.products FOR UPDATE USING (
  public.get_my_role() IN ('manager', 'admin')
) WITH CHECK (
  public.get_my_role() IN ('manager', 'admin')
);

DROP POLICY IF EXISTS "task_completions_select" ON public.task_completions;
DROP POLICY IF EXISTS "task_completions_select_scoped" ON public.task_completions;
CREATE POLICY "task_completions_select_scoped" ON public.task_completions FOR SELECT USING (
  submitted_by = auth.uid()
  OR public.get_my_role() = 'admin'
  OR (public.get_my_role() = 'manager' AND EXISTS (
    SELECT 1
    FROM public.task_assignments ta
    JOIN public.profiles p ON p.id = ta.user_id
    WHERE ta.id = task_completions.assignment_id
      AND p.branch_id = public.get_my_branch_id()
  ))
);

DROP POLICY IF EXISTS "points_transactions_select" ON public.points_transactions;
DROP POLICY IF EXISTS "points_transactions_select_scoped" ON public.points_transactions;
CREATE POLICY "points_transactions_select_scoped" ON public.points_transactions FOR SELECT USING (
  user_id = auth.uid()
  OR public.get_my_role() = 'admin'
  OR (public.get_my_role() = 'manager' AND EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = points_transactions.user_id
      AND p.branch_id = public.get_my_branch_id()
  ))
);

DROP POLICY IF EXISTS "task_assignments_select" ON public.task_assignments;
DROP POLICY IF EXISTS "task_assignments_insert_manager" ON public.task_assignments;
DROP POLICY IF EXISTS "task_assignments_update" ON public.task_assignments;
DROP POLICY IF EXISTS "task_assignments_insert_scoped" ON public.task_assignments;
DROP POLICY IF EXISTS "task_assignments_select_scoped" ON public.task_assignments;
DROP POLICY IF EXISTS "task_assignments_update_scoped" ON public.task_assignments;
CREATE POLICY "task_assignments_select_scoped" ON public.task_assignments FOR SELECT USING (
  user_id = auth.uid() OR public.get_my_role() = 'admin'
  OR (public.get_my_role() = 'manager' AND EXISTS (
    SELECT 1 FROM public.profiles p WHERE p.id = task_assignments.user_id
      AND p.branch_id = public.get_my_branch_id()
  ))
);
CREATE POLICY "task_assignments_update_scoped" ON public.task_assignments FOR UPDATE USING (
  user_id = auth.uid() OR public.get_my_role() = 'admin'
  OR (public.get_my_role() = 'manager' AND EXISTS (
    SELECT 1 FROM public.profiles p WHERE p.id = task_assignments.user_id
      AND p.branch_id = public.get_my_branch_id()
  ))
);

DROP POLICY IF EXISTS "sales_targets_select" ON public.sales_targets;
DROP POLICY IF EXISTS "sales_targets_modify" ON public.sales_targets;
DROP POLICY IF EXISTS "sales_targets_select_scoped" ON public.sales_targets;
DROP POLICY IF EXISTS "sales_targets_modify_scoped" ON public.sales_targets;
CREATE POLICY "sales_targets_select_scoped" ON public.sales_targets FOR SELECT USING (
  public.get_my_role() = 'admin' OR branch_id = public.get_my_branch_id()
);
CREATE POLICY "sales_targets_modify_scoped" ON public.sales_targets FOR ALL USING (
  public.get_my_role() = 'admin'
) WITH CHECK (
  public.get_my_role() = 'admin'
);

DROP POLICY IF EXISTS "sales_entries_select" ON public.sales_entries;
DROP POLICY IF EXISTS "sales_entries_insert" ON public.sales_entries;
DROP POLICY IF EXISTS "sales_entries_select_scoped" ON public.sales_entries;
CREATE POLICY "sales_entries_select_scoped" ON public.sales_entries FOR SELECT USING (
  public.get_my_role() = 'admin'
  OR (public.get_my_role() = 'manager' AND branch_id = public.get_my_branch_id())
);

DROP POLICY IF EXISTS "sales_imports_select" ON public.sales_imports;
DROP POLICY IF EXISTS "sales_imports_insert" ON public.sales_imports;
DROP POLICY IF EXISTS "sales_imports_select_scoped" ON public.sales_imports;
CREATE POLICY "sales_imports_select_scoped" ON public.sales_imports FOR SELECT USING (
  public.get_my_role() = 'admin'
  OR (public.get_my_role() = 'manager' AND branch_id = public.get_my_branch_id())
);

DROP POLICY IF EXISTS "sales_import_items_select" ON public.sales_import_items;
DROP POLICY IF EXISTS "sales_import_items_insert" ON public.sales_import_items;
DROP POLICY IF EXISTS "sales_import_items_select_scoped" ON public.sales_import_items;
CREATE POLICY "sales_import_items_select_scoped" ON public.sales_import_items FOR SELECT USING (
  public.get_my_role() = 'admin'
  OR (public.get_my_role() = 'manager' AND EXISTS (
    SELECT 1 FROM public.sales_imports si
    WHERE si.id = sales_import_items.sales_import_id
      AND si.branch_id = public.get_my_branch_id()
  ))
);

DROP POLICY IF EXISTS "sales_import_failures_select" ON public.sales_import_failures;
DROP POLICY IF EXISTS "sales_import_failures_select_scoped" ON public.sales_import_failures;
CREATE POLICY "sales_import_failures_select_scoped" ON public.sales_import_failures FOR SELECT USING (
  public.get_my_role() = 'admin'
);

REVOKE INSERT, UPDATE, DELETE ON public.audit_log FROM authenticated;
REVOKE INSERT ON public.sales_entries FROM authenticated;
REVOKE INSERT ON public.sales_imports FROM authenticated;
REVOKE INSERT ON public.sales_import_items FROM authenticated;
REVOKE INSERT ON public.task_assignments FROM authenticated;
REVOKE INSERT ON public.employee_shifts FROM authenticated;
REVOKE UPDATE ON public.task_assignments FROM authenticated;
REVOKE INSERT, UPDATE ON public.task_completions FROM authenticated;

DROP POLICY IF EXISTS "branches_select" ON public.branches;
DROP POLICY IF EXISTS "branches_select_active_public" ON public.branches;
DROP POLICY IF EXISTS "branches_select_admin" ON public.branches;
CREATE POLICY "branches_select_active_public"
  ON public.branches FOR SELECT
  TO anon, authenticated
  USING (is_active);
CREATE POLICY "branches_select_admin"
  ON public.branches FOR SELECT
  TO authenticated
  USING (public.get_my_role() = 'admin');

-- Completion review mutations must go through the authorized RPCs.
DROP POLICY IF EXISTS "task_completions_update" ON public.task_completions;
REVOKE UPDATE ON public.task_completions FROM authenticated;

REVOKE EXECUTE ON FUNCTION public.approve_task_completion(uuid, uuid, text)
  FROM PUBLIC, anon, authenticated;

-- =============================================================
-- DEMO ACCOUNT PROFILE SEED
-- =============================================================
-- Auth users must be created in Supabase Authentication first. SQL cannot
-- safely create Supabase Auth password hashes from a plaintext password.
-- After creating the accounts, run: SELECT public.seed_demo_account_profiles();

CREATE OR REPLACE FUNCTION public.seed_demo_account_profiles()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  seeded_count integer := 0;
BEGIN
  INSERT INTO public.profiles (id, name, email, role, branch_id, is_active)
  SELECT
    u.id,
    account.name,
    lower(u.email),
    account.role,
    account.branch_id,
    true
  FROM auth.users u
  JOIN (VALUES
    ('admin@retailflow.com',             'RetailFlow Admin',       'admin',    NULL::uuid),
    ('manager.dhanmondi@retailflow.com', 'Dhanmondi Manager', 'manager', '11111111-1111-1111-1111-111111111111'::uuid),
    ('manager.mirpur@retailflow.com', 'Mirpur Manager', 'manager', '22222222-2222-2222-2222-222222222222'::uuid),
    ('manager.uttara@retailflow.com', 'Uttara Manager', 'manager', '33333333-3333-3333-3333-333333333333'::uuid),
    ('employee.dhanmondi.1@retailflow.com', 'Dhanmondi Employee 1', 'employee', '11111111-1111-1111-1111-111111111111'::uuid),
    ('employee.dhanmondi.2@retailflow.com', 'Dhanmondi Employee 2', 'employee', '11111111-1111-1111-1111-111111111111'::uuid),
    ('employee.mirpur.1@retailflow.com', 'Mirpur Employee 1', 'employee', '22222222-2222-2222-2222-222222222222'::uuid),
    ('employee.mirpur.2@retailflow.com', 'Mirpur Employee 2', 'employee', '22222222-2222-2222-2222-222222222222'::uuid),
    ('employee.uttara.1@retailflow.com', 'Uttara Employee 1', 'employee', '33333333-3333-3333-3333-333333333333'::uuid),
    ('employee.uttara.2@retailflow.com', 'Uttara Employee 2', 'employee', '33333333-3333-3333-3333-333333333333'::uuid)
  ) AS account(email, name, role, branch_id) ON lower(u.email) = account.email
  ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    email = EXCLUDED.email,
    role = EXCLUDED.role,
    branch_id = EXCLUDED.branch_id,
    is_active = true;

  GET DIAGNOSTICS seeded_count = ROW_COUNT;

  UPDATE public.branches b
  SET manager_id = u.id
  FROM auth.users u
  WHERE lower(u.email) = CASE b.id
    WHEN '11111111-1111-1111-1111-111111111111'::uuid THEN 'manager.dhanmondi@retailflow.com'
    WHEN '22222222-2222-2222-2222-222222222222'::uuid THEN 'manager.mirpur@retailflow.com'
    WHEN '33333333-3333-3333-3333-333333333333'::uuid THEN 'manager.uttara@retailflow.com'
  END;

  RETURN seeded_count;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.seed_demo_account_profiles() FROM PUBLIC, anon, authenticated;

-- Backfill app profiles for Auth users that already existed before the
-- on_auth_user_created_retailflow trigger was installed.
CREATE OR REPLACE FUNCTION public.backfill_missing_auth_profiles()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  backfilled_count integer := 0;
BEGIN
  WITH auth_rows AS (
    SELECT
      u.id,
      COALESCE(
        NULLIF(trim(u.raw_user_meta_data ->> 'name'), ''),
        split_part(COALESCE(u.email, 'Employee'), '@', 1)
      ) AS profile_name,
      lower(COALESCE(u.email, '')) AS profile_email,
      CASE
        WHEN lower(COALESCE(u.email, '')) = 'admin@retailflow.com' THEN 'admin'
        WHEN lower(COALESCE(u.email, '')) LIKE 'manager.%@retailflow.com' THEN 'manager'
        ELSE 'employee'
      END AS profile_role,
      CASE lower(COALESCE(u.email, ''))
        WHEN 'manager.dhanmondi@retailflow.com' THEN '11111111-1111-1111-1111-111111111111'::uuid
        WHEN 'employee.dhanmondi.1@retailflow.com' THEN '11111111-1111-1111-1111-111111111111'::uuid
        WHEN 'employee.dhanmondi.2@retailflow.com' THEN '11111111-1111-1111-1111-111111111111'::uuid
        WHEN 'manager.mirpur@retailflow.com' THEN '22222222-2222-2222-2222-222222222222'::uuid
        WHEN 'employee.mirpur.1@retailflow.com' THEN '22222222-2222-2222-2222-222222222222'::uuid
        WHEN 'employee.mirpur.2@retailflow.com' THEN '22222222-2222-2222-2222-222222222222'::uuid
        WHEN 'manager.uttara@retailflow.com' THEN '33333333-3333-3333-3333-333333333333'::uuid
        WHEN 'employee.uttara.1@retailflow.com' THEN '33333333-3333-3333-3333-333333333333'::uuid
        WHEN 'employee.uttara.2@retailflow.com' THEN '33333333-3333-3333-3333-333333333333'::uuid
        ELSE
          CASE
            WHEN COALESCE(u.raw_user_meta_data ->> 'branch_id', '') ~*
              '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
              THEN (u.raw_user_meta_data ->> 'branch_id')::uuid
            ELSE NULL
          END
      END AS profile_branch_id
    FROM auth.users u
  )
  INSERT INTO public.profiles (
    id,
    name,
    email,
    role,
    branch_id,
    is_active,
    total_lifetime_points
  )
  SELECT
    ar.id,
    ar.profile_name,
    ar.profile_email,
    ar.profile_role,
    CASE WHEN ar.profile_role = 'admin' THEN NULL ELSE ar.profile_branch_id END,
    true,
    0
  FROM auth_rows ar
  WHERE NOT EXISTS (
    SELECT 1 FROM public.profiles p WHERE p.id = ar.id
  )
  ON CONFLICT (id) DO NOTHING;

  GET DIAGNOSTICS backfilled_count = ROW_COUNT;
  RETURN backfilled_count;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.backfill_missing_auth_profiles() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.seed_demo_presentation_data()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin_id uuid;
  v_dhan_manager_id uuid;
  v_dhan_employee_1 uuid;
  v_dhan_employee_2 uuid;
  v_task_restock uuid;
  v_task_cleaning uuid;
  v_task_audit uuid;
  v_assignment_id uuid;
  v_completion_id uuid;
  v_dhan_import_id uuid;
  v_mirpur_import_id uuid;
  v_uttara_import_id uuid;
  v_seeded_count integer := 0;
BEGIN
  SELECT id INTO v_admin_id
  FROM public.profiles
  WHERE lower(email) = 'admin@retailflow.com' AND role = 'admin';

  IF v_admin_id IS NULL THEN
    RETURN 0;
  END IF;

  SELECT manager_id INTO v_dhan_manager_id
  FROM public.branches
  WHERE id = '11111111-1111-1111-1111-111111111111'::uuid;

  SELECT id INTO v_dhan_employee_1
  FROM public.profiles
  WHERE lower(email) = 'employee.dhanmondi.1@retailflow.com';

  SELECT id INTO v_dhan_employee_2
  FROM public.profiles
  WHERE lower(email) = 'employee.dhanmondi.2@retailflow.com';

  INSERT INTO public.shifts (id, branch_id, name, start_time, end_time, is_active)
  VALUES
    ('11111111-1111-1111-1111-111111110001', '11111111-1111-1111-1111-111111111111', 'Morning', '09:00', '15:00', true),
    ('11111111-1111-1111-1111-111111110002', '11111111-1111-1111-1111-111111111111', 'Evening', '15:00', '22:00', true),
    ('22222222-2222-2222-2222-222222220001', '22222222-2222-2222-2222-222222222222', 'Morning', '09:00', '15:00', true),
    ('22222222-2222-2222-2222-222222220002', '22222222-2222-2222-2222-222222222222', 'Evening', '15:00', '22:00', true),
    ('33333333-3333-3333-3333-333333330001', '33333333-3333-3333-3333-333333333333', 'Morning', '09:00', '15:00', true),
    ('33333333-3333-3333-3333-333333330002', '33333333-3333-3333-3333-333333333333', 'Evening', '15:00', '22:00', true)
  ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    start_time = EXCLUDED.start_time,
    end_time = EXCLUDED.end_time,
    is_active = true;
  v_seeded_count := v_seeded_count + 1;

  INSERT INTO public.tasks (
    title,
    description,
    frequency,
    branch_id,
    base_points,
    photo_bonus_points,
    photo_required,
    deadline_hours_after_assignment,
    is_active
  )
  SELECT
    task_data.title,
    task_data.description,
    task_data.frequency,
    task_data.branch_id,
    task_data.base_points,
    task_data.photo_bonus_points,
    task_data.photo_required,
    task_data.deadline_hours_after_assignment,
    true
  FROM (VALUES
    ('Shelf Restocking', 'Restock beverage shelves and verify shelf-facing.', 'daily', '11111111-1111-1111-1111-111111111111'::uuid, 10, 5, true, 8),
    ('Store Cleaning', 'Clean entry, checkout, and aisle touchpoints.', 'daily', '11111111-1111-1111-1111-111111111111'::uuid, 10, 5, true, 6),
    ('Inventory Audit', 'Count promoted products and reconcile variances.', 'weekly', '11111111-1111-1111-1111-111111111111'::uuid, 30, 5, false, 48),
    ('Shelf Restocking', 'Restock beverage shelves and verify shelf-facing.', 'daily', '22222222-2222-2222-2222-222222222222'::uuid, 10, 5, true, 8),
    ('Store Cleaning', 'Clean entry, checkout, and aisle touchpoints.', 'daily', '22222222-2222-2222-2222-222222222222'::uuid, 10, 5, true, 6),
    ('Inventory Audit', 'Count promoted products and reconcile variances.', 'weekly', '22222222-2222-2222-2222-222222222222'::uuid, 30, 5, false, 48),
    ('Shelf Restocking', 'Restock beverage shelves and verify shelf-facing.', 'daily', '33333333-3333-3333-3333-333333333333'::uuid, 10, 5, true, 8),
    ('Store Cleaning', 'Clean entry, checkout, and aisle touchpoints.', 'daily', '33333333-3333-3333-3333-333333333333'::uuid, 10, 5, true, 6),
    ('Inventory Audit', 'Count promoted products and reconcile variances.', 'weekly', '33333333-3333-3333-3333-333333333333'::uuid, 30, 5, false, 48)
  ) AS task_data(title, description, frequency, branch_id, base_points, photo_bonus_points, photo_required, deadline_hours_after_assignment)
  WHERE NOT EXISTS (
    SELECT 1
    FROM public.tasks t
    WHERE t.title = task_data.title
      AND t.branch_id = task_data.branch_id
  );
  v_seeded_count := v_seeded_count + 1;

  SELECT id INTO v_task_restock
  FROM public.tasks
  WHERE title = 'Shelf Restocking'
    AND branch_id = '11111111-1111-1111-1111-111111111111'::uuid
  LIMIT 1;

  SELECT id INTO v_task_cleaning
  FROM public.tasks
  WHERE title = 'Store Cleaning'
    AND branch_id = '11111111-1111-1111-1111-111111111111'::uuid
  LIMIT 1;

  SELECT id INTO v_task_audit
  FROM public.tasks
  WHERE title = 'Inventory Audit'
    AND branch_id = '11111111-1111-1111-1111-111111111111'::uuid
  LIMIT 1;

  IF v_dhan_employee_1 IS NOT NULL AND v_task_restock IS NOT NULL THEN
    INSERT INTO public.employee_shifts (employee_id, shift_id, work_date)
    VALUES (
      v_dhan_employee_1,
      '11111111-1111-1111-1111-111111110001'::uuid,
      CURRENT_DATE
    )
    ON CONFLICT (employee_id, shift_id, work_date) DO NOTHING;

    INSERT INTO public.task_assignments (task_id, user_id, scheduled_date, due_at, status)
    VALUES (
      v_task_restock,
      v_dhan_employee_1,
      CURRENT_DATE,
      now() + interval '6 hours',
      'approved'
    )
    ON CONFLICT (task_id, user_id, scheduled_date) DO UPDATE SET
      due_at = EXCLUDED.due_at,
      status = 'approved'
    RETURNING id INTO v_assignment_id;

    INSERT INTO public.task_completions (
      assignment_id,
      attempt_number,
      submitted_by,
      submitted_at,
      completion_note,
      photo_url,
      reviewed_by,
      reviewed_at,
      review_note,
      status,
      points_awarded
    )
    VALUES (
      v_assignment_id,
      1,
      v_dhan_employee_1,
      now() - interval '2 hours',
      'Shelves refilled and front-facing completed.',
      'demo://task-photos/dhanmondi-shelf-restocking.jpg',
      v_dhan_manager_id,
      now() - interval '90 minutes',
      'Approved for presentation demo.',
      'approved',
      15
    )
    ON CONFLICT (assignment_id, attempt_number) DO UPDATE SET
      submitted_at = EXCLUDED.submitted_at,
      completion_note = EXCLUDED.completion_note,
      photo_url = EXCLUDED.photo_url,
      reviewed_by = EXCLUDED.reviewed_by,
      reviewed_at = EXCLUDED.reviewed_at,
      review_note = EXCLUDED.review_note,
      status = 'approved',
      points_awarded = 15
    RETURNING id INTO v_completion_id;

    INSERT INTO public.points_transactions (
      user_id,
      task_completion_id,
      points,
      base_points,
      bonus_points
    )
    VALUES (v_dhan_employee_1, v_completion_id, 15, 10, 5)
    ON CONFLICT (task_completion_id) DO UPDATE SET
      points = EXCLUDED.points,
      base_points = EXCLUDED.base_points,
      bonus_points = EXCLUDED.bonus_points;

    INSERT INTO public.notifications (user_id, type, title, message, data)
    SELECT
      v_dhan_employee_1,
      'task_approved',
      'Task Approved! +15 pts',
      'Your demo task "Shelf Restocking" was approved.',
      jsonb_build_object('assignment_id', v_assignment_id, 'completion_id', v_completion_id)
    WHERE NOT EXISTS (
      SELECT 1
      FROM public.notifications n
      WHERE n.user_id = v_dhan_employee_1
        AND n.type = 'task_approved'
        AND n.data ->> 'completion_id' = v_completion_id::text
    );
  END IF;

  IF v_dhan_employee_1 IS NOT NULL AND v_task_audit IS NOT NULL THEN
    INSERT INTO public.task_assignments (task_id, user_id, scheduled_date, due_at, status)
    VALUES (
      v_task_audit,
      v_dhan_employee_1,
      CURRENT_DATE - 1,
      now() - interval '12 hours',
      'approved'
    )
    ON CONFLICT (task_id, user_id, scheduled_date) DO UPDATE SET
      due_at = EXCLUDED.due_at,
      status = 'approved'
    RETURNING id INTO v_assignment_id;

    INSERT INTO public.task_completions (
      assignment_id,
      attempt_number,
      submitted_by,
      submitted_at,
      completion_note,
      reviewed_by,
      reviewed_at,
      review_note,
      status,
      points_awarded
    )
    VALUES (
      v_assignment_id,
      1,
      v_dhan_employee_1,
      now() - interval '1 day',
      'Promotion stock counted and reconciled.',
      v_dhan_manager_id,
      now() - interval '22 hours',
      'Counts matched the demo target.',
      'approved',
      30
    )
    ON CONFLICT (assignment_id, attempt_number) DO UPDATE SET
      submitted_at = EXCLUDED.submitted_at,
      completion_note = EXCLUDED.completion_note,
      reviewed_by = EXCLUDED.reviewed_by,
      reviewed_at = EXCLUDED.reviewed_at,
      review_note = EXCLUDED.review_note,
      status = 'approved',
      points_awarded = 30
    RETURNING id INTO v_completion_id;

    INSERT INTO public.points_transactions (
      user_id,
      task_completion_id,
      points,
      base_points,
      bonus_points
    )
    VALUES (v_dhan_employee_1, v_completion_id, 30, 30, 0)
    ON CONFLICT (task_completion_id) DO UPDATE SET
      points = EXCLUDED.points,
      base_points = EXCLUDED.base_points,
      bonus_points = EXCLUDED.bonus_points;
  END IF;

  IF v_dhan_employee_2 IS NOT NULL AND v_task_cleaning IS NOT NULL THEN
    INSERT INTO public.task_assignments (task_id, user_id, scheduled_date, due_at, status)
    VALUES (
      v_task_cleaning,
      v_dhan_employee_2,
      CURRENT_DATE,
      now() + interval '4 hours',
      'pending'
    )
    ON CONFLICT (task_id, user_id, scheduled_date) DO UPDATE SET
      due_at = EXCLUDED.due_at,
      status = 'pending';
  END IF;

  UPDATE public.profiles p
  SET total_lifetime_points = COALESCE((
    SELECT SUM(pt.points)
    FROM public.points_transactions pt
    WHERE pt.user_id = p.id
  ), 0)
  WHERE p.id IN (v_dhan_employee_1, v_dhan_employee_2);

  IF v_dhan_employee_1 IS NOT NULL THEN
    PERFORM public.recalculate_user_badge(v_dhan_employee_1);
  END IF;
  IF v_dhan_employee_2 IS NOT NULL THEN
    PERFORM public.recalculate_user_badge(v_dhan_employee_2);
  END IF;
  v_seeded_count := v_seeded_count + 1;

  INSERT INTO public.sales_targets (branch_id, shift_id, target_date, target_amount, created_by)
  VALUES
    ('11111111-1111-1111-1111-111111111111', '11111111-1111-1111-1111-111111110001', CURRENT_DATE, 120000, v_admin_id),
    ('22222222-2222-2222-2222-222222222222', '22222222-2222-2222-2222-222222220001', CURRENT_DATE, 95000, v_admin_id),
    ('33333333-3333-3333-3333-333333333333', '33333333-3333-3333-3333-333333330001', CURRENT_DATE, 110000, v_admin_id)
  ON CONFLICT (branch_id, shift_id, target_date) DO UPDATE SET
    target_amount = EXCLUDED.target_amount,
    created_by = EXCLUDED.created_by;

  INSERT INTO public.sales_imports (
    branch_id,
    shift_id,
    sale_date,
    source,
    sales_source,
    total_amount,
    imported_by,
    external_reference
  )
  VALUES (
    '11111111-1111-1111-1111-111111111111',
    '11111111-1111-1111-1111-111111110001',
    CURRENT_DATE,
    'csv_upload',
    'csv_upload',
    142500,
    v_admin_id,
    'DEMO-DHANMONDI-MORNING'
  )
  ON CONFLICT (branch_id, shift_id, sale_date, source, external_reference)
  DO UPDATE SET
    sales_source = EXCLUDED.sales_source,
    total_amount = EXCLUDED.total_amount,
    imported_by = EXCLUDED.imported_by
  RETURNING id INTO v_dhan_import_id;

  INSERT INTO public.sales_imports (
    branch_id,
    shift_id,
    sale_date,
    source,
    sales_source,
    total_amount,
    imported_by,
    external_reference
  )
  VALUES (
    '22222222-2222-2222-2222-222222222222',
    '22222222-2222-2222-2222-222222220001',
    CURRENT_DATE,
    'csv_upload',
    'csv_upload',
    88400,
    v_admin_id,
    'DEMO-MIRPUR-MORNING'
  )
  ON CONFLICT (branch_id, shift_id, sale_date, source, external_reference)
  DO UPDATE SET
    sales_source = EXCLUDED.sales_source,
    total_amount = EXCLUDED.total_amount,
    imported_by = EXCLUDED.imported_by
  RETURNING id INTO v_mirpur_import_id;

  INSERT INTO public.sales_imports (
    branch_id,
    shift_id,
    sale_date,
    source,
    sales_source,
    total_amount,
    imported_by,
    external_reference
  )
  VALUES (
    '33333333-3333-3333-3333-333333333333',
    '33333333-3333-3333-3333-333333330001',
    CURRENT_DATE,
    'csv_upload',
    'csv_upload',
    117800,
    v_admin_id,
    'DEMO-UTTARA-MORNING'
  )
  ON CONFLICT (branch_id, shift_id, sale_date, source, external_reference)
  DO UPDATE SET
    sales_source = EXCLUDED.sales_source,
    total_amount = EXCLUDED.total_amount,
    imported_by = EXCLUDED.imported_by
  RETURNING id INTO v_uttara_import_id;

  INSERT INTO public.sales_import_items (sales_import_id, product_id, quantity, unit_price)
  SELECT v_dhan_import_id, p.id, 420, 0
  FROM public.products p
  WHERE lower(p.name) = 'coca-cola'
  LIMIT 1
  ON CONFLICT (sales_import_id, product_id) DO UPDATE SET
    quantity = EXCLUDED.quantity,
    unit_price = EXCLUDED.unit_price;

  INSERT INTO public.sales_import_items (sales_import_id, product_id, quantity, unit_price)
  SELECT v_mirpur_import_id, p.id, 330, 0
  FROM public.products p
  WHERE lower(p.name) = 'pepsi'
  LIMIT 1
  ON CONFLICT (sales_import_id, product_id) DO UPDATE SET
    quantity = EXCLUDED.quantity,
    unit_price = EXCLUDED.unit_price;

  INSERT INTO public.sales_import_items (sales_import_id, product_id, quantity, unit_price)
  SELECT v_uttara_import_id, p.id, 510, 0
  FROM public.products p
  WHERE lower(p.name) = 'mineral water'
  LIMIT 1
  ON CONFLICT (sales_import_id, product_id) DO UPDATE SET
    quantity = EXCLUDED.quantity,
    unit_price = EXCLUDED.unit_price;
  v_seeded_count := v_seeded_count + 1;

  PERFORM public.write_audit_log(
    'demo_presentation_data_seeded',
    'company_profile',
    '99999999-9999-9999-9999-999999999999'::uuid,
    NULL,
    jsonb_build_object('seed_scope', 'operational_demo'),
    v_admin_id
  );
  v_seeded_count := v_seeded_count + 1;

  RETURN v_seeded_count;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.seed_demo_presentation_data()
  FROM PUBLIC, anon, authenticated;

-- =============================================================
-- ROW LEVEL SECURITY, GRANTS, AND POLICIES
-- =============================================================

-- Enable RLS on all public tables.
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.branches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_price_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.attendance ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.leave_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.issue_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales_targets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales_imports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales_import_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales_import_failures ENABLE ROW LEVEL SECURITY;

-- Grants for the authenticated role (Flutter app sessions).
GRANT SELECT, INSERT, UPDATE ON public.profiles TO authenticated;
GRANT SELECT ON public.branches TO anon;
GRANT SELECT, INSERT, UPDATE ON public.branches TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.products TO authenticated;
GRANT SELECT, INSERT ON public.product_price_history TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.attendance TO authenticated;
GRANT SELECT, INSERT ON public.leave_requests TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.issue_reports TO authenticated;
REVOKE UPDATE, DELETE ON public.product_price_history FROM authenticated;
REVOKE UPDATE, DELETE ON public.leave_requests FROM authenticated;
GRANT SELECT, INSERT, UPDATE ON public.sales_targets TO authenticated;
GRANT SELECT ON public.sales_imports TO authenticated;
GRANT SELECT ON public.sales_import_items TO authenticated;
GRANT SELECT ON public.sales_import_failures TO authenticated;

-- Grants for the service_role (used by Edge Functions with the service role key).
-- service_role bypasses RLS but still needs table-level privileges.
GRANT ALL ON public.profiles TO service_role;
GRANT ALL ON public.branches TO service_role;
GRANT ALL ON public.products TO service_role;
GRANT ALL ON public.product_price_history TO service_role;
GRANT ALL ON public.attendance TO service_role;
GRANT ALL ON public.leave_requests TO service_role;
GRANT ALL ON public.issue_reports TO service_role;
GRANT ALL ON public.sales_targets TO service_role;
GRANT ALL ON public.sales_imports TO service_role;
GRANT ALL ON public.sales_import_items TO service_role;
GRANT ALL ON public.sales_import_failures TO service_role;

-- Helper function grants.
REVOKE EXECUTE ON FUNCTION public.get_my_role() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_my_branch_id() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.retailflow_current_date() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_role() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_branch_id() TO authenticated;
GRANT EXECUTE ON FUNCTION public.retailflow_current_date() TO authenticated;

-- ─── Profiles policies ─────────────────────────────────────
DROP POLICY IF EXISTS "profiles_select_all_authenticated" ON public.profiles;
DROP POLICY IF EXISTS "profiles_select_scoped" ON public.profiles;
CREATE POLICY "profiles_select_scoped" ON public.profiles FOR SELECT USING (
  id = auth.uid()
  OR public.get_my_role() = 'admin'
  OR (public.get_my_role() = 'manager' AND branch_id = public.get_my_branch_id())
);

DROP POLICY IF EXISTS "profiles_update_admin_or_self" ON public.profiles;
DROP POLICY IF EXISTS "profiles_update_admin_only" ON public.profiles;
CREATE POLICY "profiles_update_admin_only" ON public.profiles FOR UPDATE
  USING (public.get_my_role() = 'admin')
  WITH CHECK (public.get_my_role() = 'admin');

DROP POLICY IF EXISTS "profiles_insert_trigger_or_admin" ON public.profiles;
CREATE POLICY "profiles_insert_trigger_or_admin" ON public.profiles FOR INSERT
  WITH CHECK (public.get_my_role() = 'admin' OR id = auth.uid());

-- ─── Branches policies ─────────────────────────────────────
DROP POLICY IF EXISTS "branches_select" ON public.branches;
DROP POLICY IF EXISTS "branches_select_active_public" ON public.branches;
DROP POLICY IF EXISTS "branches_select_admin" ON public.branches;
DROP POLICY IF EXISTS "branches_insert_admin" ON public.branches;
DROP POLICY IF EXISTS "branches_update_admin" ON public.branches;
CREATE POLICY "branches_select_active_public"
  ON public.branches FOR SELECT
  TO anon, authenticated
  USING (is_active);
CREATE POLICY "branches_select_admin"
  ON public.branches FOR SELECT
  TO authenticated
  USING (public.get_my_role() = 'admin');
CREATE POLICY "branches_insert_admin" ON public.branches FOR INSERT
  WITH CHECK (public.get_my_role() = 'admin');
CREATE POLICY "branches_update_admin" ON public.branches FOR UPDATE
  USING (public.get_my_role() = 'admin')
  WITH CHECK (public.get_my_role() = 'admin');

-- Attendance policies
DROP POLICY IF EXISTS "attendance_select_own" ON public.attendance;
DROP POLICY IF EXISTS "attendance_select_branch" ON public.attendance;
DROP POLICY IF EXISTS "attendance_select_admin" ON public.attendance;
DROP POLICY IF EXISTS "attendance_insert_own" ON public.attendance;
DROP POLICY IF EXISTS "attendance_insert_employee_today" ON public.attendance;
DROP POLICY IF EXISTS "attendance_update_own" ON public.attendance;
DROP POLICY IF EXISTS "attendance_employee_checkout_today" ON public.attendance;
DROP POLICY IF EXISTS "attendance_admin_full" ON public.attendance;

CREATE POLICY "attendance_select_own" ON public.attendance FOR SELECT USING (
  employee_id = auth.uid()
);
CREATE POLICY "attendance_select_branch" ON public.attendance FOR SELECT USING (
  public.get_my_role() = 'manager'
  AND branch_id = public.get_my_branch_id()
);
CREATE POLICY "attendance_select_admin" ON public.attendance FOR SELECT USING (
  public.get_my_role() = 'admin'
);
CREATE POLICY "attendance_insert_employee_today" ON public.attendance FOR INSERT WITH CHECK (
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
CREATE POLICY "attendance_employee_checkout_today" ON public.attendance FOR UPDATE USING (
  employee_id = auth.uid()
  AND attendance_date = public.retailflow_current_date()
) WITH CHECK (
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

-- Leave request policies
DROP POLICY IF EXISTS "leave_requests_select_own" ON public.leave_requests;
DROP POLICY IF EXISTS "leave_requests_select_branch" ON public.leave_requests;
DROP POLICY IF EXISTS "leave_requests_select_admin" ON public.leave_requests;
DROP POLICY IF EXISTS "leave_requests_insert" ON public.leave_requests;
DROP POLICY IF EXISTS "leave_requests_insert_employee_own" ON public.leave_requests;
DROP POLICY IF EXISTS "leave_requests_update" ON public.leave_requests;
DROP POLICY IF EXISTS "leave_requests_update_manager_admin" ON public.leave_requests;

CREATE POLICY "leave_requests_select_own" ON public.leave_requests FOR SELECT USING (
  employee_id = auth.uid()
);
CREATE POLICY "leave_requests_select_branch" ON public.leave_requests FOR SELECT USING (
  public.get_my_role() = 'manager'
  AND branch_id = public.get_my_branch_id()
);
CREATE POLICY "leave_requests_select_admin" ON public.leave_requests FOR SELECT USING (
  public.get_my_role() = 'admin'
);
CREATE POLICY "leave_requests_insert_employee_own" ON public.leave_requests FOR INSERT WITH CHECK (
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

-- Product price history policies
DROP POLICY IF EXISTS "product_price_history_select_auth" ON public.product_price_history;
DROP POLICY IF EXISTS "product_price_history_insert_manager_admin" ON public.product_price_history;
DROP POLICY IF EXISTS "product_price_history_update_manager_admin" ON public.product_price_history;
DROP POLICY IF EXISTS "product_price_history_admin_full" ON public.product_price_history;

CREATE POLICY "product_price_history_select_auth" ON public.product_price_history FOR SELECT USING (
  auth.uid() IS NOT NULL
);
CREATE POLICY "product_price_history_insert_manager_admin" ON public.product_price_history FOR INSERT WITH CHECK (
  public.get_my_role() IN ('manager', 'admin')
);

-- ─── Products policies ─────────────────────────────────────
DROP POLICY IF EXISTS "products_select" ON public.products;
DROP POLICY IF EXISTS "products_select_manager_admin" ON public.products;
DROP POLICY IF EXISTS "products_select_auth" ON public.products;
DROP POLICY IF EXISTS "products_modify_manager_admin" ON public.products;
DROP POLICY IF EXISTS "products_modify_manager_admin_final" ON public.products;
DROP POLICY IF EXISTS "products_insert_manager_admin" ON public.products;
DROP POLICY IF EXISTS "products_update_manager_admin" ON public.products;
CREATE POLICY "products_select_auth" ON public.products FOR SELECT USING (
  auth.uid() IS NOT NULL
);
CREATE POLICY "products_insert_manager_admin" ON public.products FOR INSERT WITH CHECK (
  public.get_my_role() IN ('manager', 'admin')
);
CREATE POLICY "products_update_manager_admin" ON public.products FOR UPDATE USING (
  public.get_my_role() IN ('manager', 'admin')
) WITH CHECK (
  public.get_my_role() IN ('manager', 'admin')
);

-- ─── Sales targets policies ────────────────────────────────
DROP POLICY IF EXISTS "sales_targets_select" ON public.sales_targets;
DROP POLICY IF EXISTS "sales_targets_modify" ON public.sales_targets;
DROP POLICY IF EXISTS "sales_targets_select_scoped" ON public.sales_targets;
DROP POLICY IF EXISTS "sales_targets_modify_scoped" ON public.sales_targets;
CREATE POLICY "sales_targets_select_scoped" ON public.sales_targets FOR SELECT USING (
  public.get_my_role() = 'admin' OR branch_id = public.get_my_branch_id()
);
CREATE POLICY "sales_targets_modify_scoped" ON public.sales_targets FOR ALL USING (
  public.get_my_role() = 'admin'
) WITH CHECK (
  public.get_my_role() = 'admin'
);

-- ─── Sales imports policies ────────────────────────────────
DROP POLICY IF EXISTS "sales_imports_select" ON public.sales_imports;
DROP POLICY IF EXISTS "sales_imports_select_scoped" ON public.sales_imports;
CREATE POLICY "sales_imports_select_scoped" ON public.sales_imports FOR SELECT USING (
  public.get_my_role() = 'admin'
  OR (public.get_my_role() = 'manager' AND branch_id = public.get_my_branch_id())
);

DROP POLICY IF EXISTS "sales_import_items_select" ON public.sales_import_items;
DROP POLICY IF EXISTS "sales_import_items_select_scoped" ON public.sales_import_items;
CREATE POLICY "sales_import_items_select_scoped" ON public.sales_import_items FOR SELECT USING (
  public.get_my_role() = 'admin'
  OR (public.get_my_role() = 'manager' AND EXISTS (
    SELECT 1 FROM public.sales_imports si
    WHERE si.id = sales_import_items.sales_import_id
      AND si.branch_id = public.get_my_branch_id()
  ))
);

DROP POLICY IF EXISTS "sales_import_failures_select" ON public.sales_import_failures;
DROP POLICY IF EXISTS "sales_import_failures_select_scoped" ON public.sales_import_failures;
CREATE POLICY "sales_import_failures_select_scoped" ON public.sales_import_failures FOR SELECT USING (
  public.get_my_role() = 'admin'
);

-- Safe to run repeatedly from the SQL editor.
SELECT public.backfill_missing_auth_profiles();
SELECT public.seed_demo_account_profiles();
SELECT public.seed_demo_presentation_data();

-- 1. Test Task Point Awarding & Duplicate Protection:
--    SELECT public.approve_task_completion('<completion_uuid>', '<manager_uuid>', 'Approved excellent restock');
--    -- Running a second time will throw: 'This completion has already been approved'
--
-- 2. Test Badge Tier Calculation:
--    SELECT public.recalculate_user_badge('<user_uuid>');
--
-- 3. Task template usage remains manual and manager-driven.
--    Managers create a reusable template, then assign tasks manually when needed.
-- =============================================================
