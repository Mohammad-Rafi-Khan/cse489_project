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
  ('Gold', 3000, 'Earned 3000 lifetime task points', 'stars'),
  ('Platinum', 5000, 'Earned 5000 lifetime task points', 'emoji_events')
ON CONFLICT (name) DO UPDATE SET
  min_points = EXCLUDED.min_points,
  description = EXCLUDED.description;

CREATE TABLE IF NOT EXISTS public.branches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  location text,
  manager_id uuid,
  is_active boolean NOT NULL DEFAULT true,
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

CREATE OR REPLACE FUNCTION public.handle_new_retailflow_user()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE selected_branch uuid;
BEGIN
  BEGIN
    selected_branch := NULLIF(new.raw_user_meta_data ->> 'branch_id', '')::uuid;
  EXCEPTION WHEN invalid_text_representation THEN
    selected_branch := NULL;
  END;
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
  unit_price numeric(10,2) NOT NULL CHECK (unit_price > 0),
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_products_is_active ON public.products(is_active);

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
  is_active          boolean NOT NULL DEFAULT true,
  created_at         timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_tasks_branch_id ON public.tasks(branch_id);
CREATE INDEX IF NOT EXISTS idx_tasks_is_active ON public.tasks(is_active);

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
BEGIN
  SELECT total_lifetime_points, current_badge_id
  INTO v_total_points, v_old_badge_id
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

  IF v_comp.status = 'approved' THEN
    RAISE EXCEPTION 'This completion has already been approved';
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

  v_base_pts := COALESCE(v_task.base_points, 10);

  -- Award photo bonus if photo URL was submitted
  IF v_comp.photo_url IS NOT NULL AND length(trim(v_comp.photo_url)) > 0 THEN
    v_bonus_pts := COALESCE(v_task.photo_bonus_points, 5);
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

  -- Update user total lifetime points
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

  RETURN jsonb_build_object(
    'success', true,
    'points_awarded', v_total_pts,
    'base_points', v_base_pts,
    'bonus_points', v_bonus_pts
  );
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- 10. SALES TARGETS & SALES ENTRIES (BRANCH/SHIFT LEVEL)
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

CREATE TABLE IF NOT EXISTS public.sales_entries (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  branch_id     uuid NOT NULL REFERENCES public.branches(id) ON DELETE CASCADE,
  shift_id      uuid REFERENCES public.shifts(id) ON DELETE SET NULL,
  sale_date     date NOT NULL,
  employee_id   uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  product_id    uuid NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
  quantity      integer NOT NULL CHECK (quantity > 0),
  unit_price    numeric(10,2) NOT NULL CHECK (unit_price > 0),
  total_amount  numeric(14,2) GENERATED ALWAYS AS (quantity * unit_price) STORED,
  recorded_at   timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_sales_entries_branch_date
  ON public.sales_entries(branch_id, sale_date);
CREATE INDEX IF NOT EXISTS idx_sales_entries_product
  ON public.sales_entries(product_id);

-- ─────────────────────────────────────────────────────────────
-- 11. COMPETITIONS & BRANCH LEADERBOARDS
-- ─────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.competitions (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title        text NOT NULL,
  description  text,
  start_date   date NOT NULL,
  end_date     date NOT NULL,
  status       text NOT NULL DEFAULT 'upcoming'
                 CHECK (status IN ('upcoming', 'active', 'ended', 'cancelled')),
  is_active    boolean NOT NULL DEFAULT true,
  created_by   uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at   timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_competitions_dates ON public.competitions(start_date, end_date);

CREATE TABLE IF NOT EXISTS public.competition_branches (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  competition_id  uuid NOT NULL REFERENCES public.competitions(id) ON DELETE CASCADE,
  branch_id       uuid NOT NULL REFERENCES public.branches(id) ON DELETE CASCADE,
  UNIQUE (competition_id, branch_id)
);

CREATE TABLE IF NOT EXISTS public.competition_products (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  competition_id  uuid NOT NULL REFERENCES public.competitions(id) ON DELETE CASCADE,
  product_id      uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  points_per_unit integer NOT NULL DEFAULT 1 CHECK (points_per_unit > 0),
  UNIQUE (competition_id, product_id)
);

CREATE TABLE IF NOT EXISTS public.branch_leaderboard_entries (
  id                        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  competition_id            uuid NOT NULL REFERENCES public.competitions(id) ON DELETE CASCADE,
  branch_id                 uuid NOT NULL REFERENCES public.branches(id) ON DELETE CASCADE,
  total_qualifying_qty      integer NOT NULL DEFAULT 0 CHECK (total_qualifying_qty >= 0),
  total_competition_points  integer NOT NULL DEFAULT 0 CHECK (total_competition_points >= 0),
  current_rank              integer,
  previous_rank             integer,
  updated_at                timestamptz NOT NULL DEFAULT now(),
  UNIQUE (competition_id, branch_id)
);

-- Recalculate competition leaderboard function
CREATE OR REPLACE FUNCTION public.recalculate_competition_leaderboard(p_competition_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_comp public.competitions%ROWTYPE;
  v_record RECORD;
  v_rank integer := 1;
BEGIN
  SELECT * INTO v_comp FROM public.competitions WHERE id = p_competition_id;
  IF NOT FOUND THEN RETURN; END IF;

  FOR v_record IN (
    SELECT
      cb.branch_id,
      COALESCE(SUM(se.quantity), 0)::integer AS total_qty,
      COALESCE(SUM(se.quantity * cp.points_per_unit), 0)::integer AS total_pts
    FROM public.competition_branches cb
    CROSS JOIN public.competition_products cp
    LEFT JOIN public.sales_entries se
      ON se.branch_id = cb.branch_id
      AND se.product_id = cp.product_id
      AND se.sale_date >= v_comp.start_date
      AND se.sale_date <= v_comp.end_date
    WHERE cb.competition_id = p_competition_id
      AND cp.competition_id = p_competition_id
    GROUP BY cb.branch_id
    ORDER BY total_pts DESC, total_qty DESC
  ) LOOP
    INSERT INTO public.branch_leaderboard_entries (
      competition_id,
      branch_id,
      total_qualifying_qty,
      total_competition_points,
      current_rank,
      previous_rank,
      updated_at
    )
    VALUES (
      p_competition_id,
      v_record.branch_id,
      v_record.total_qty,
      v_record.total_pts,
      v_rank,
      v_rank,
      now()
    )
    ON CONFLICT (competition_id, branch_id) DO UPDATE SET
      previous_rank = public.branch_leaderboard_entries.current_rank,
      current_rank = EXCLUDED.current_rank,
      total_qualifying_qty = EXCLUDED.total_qualifying_qty,
      total_competition_points = EXCLUDED.total_competition_points,
      updated_at = now();

    v_rank := v_rank + 1;
  END LOOP;
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- 12. NOTIFICATIONS TABLE
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

CREATE INDEX IF NOT EXISTS idx_notifications_user_unread
  ON public.notifications(user_id, is_read);

-- ─────────────────────────────────────────────────────────────
-- 13. RECURRING TASK GENERATION STORED PROCEDURE
-- ─────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.generate_recurring_task_assignments(
  p_task_id      uuid,
  p_user_ids     uuid[],
  p_start_date   date,
  p_end_date     date
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id    uuid;
  v_curr_date  date;
  v_count      integer := 0;
BEGIN
  FOREACH v_user_id IN ARRAY p_user_ids LOOP
    v_curr_date := p_start_date;
    WHILE v_curr_date <= p_end_date LOOP
      INSERT INTO public.task_assignments (
        task_id,
        user_id,
        scheduled_date,
        status
      )
      VALUES (
        p_task_id,
        v_user_id,
        v_curr_date,
        'pending'
      )
      ON CONFLICT (task_id, user_id, scheduled_date) DO NOTHING;

      IF FOUND THEN
        v_count := v_count + 1;
      END IF;

      v_curr_date := v_curr_date + 1;
    END LOOP;
  END LOOP;

  RETURN v_count;
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- 14. ROW LEVEL SECURITY (RLS) POLICIES
-- ─────────────────────────────────────────────────────────────

ALTER TABLE public.badges ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.branches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.shifts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.employee_shifts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.task_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.task_completions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.points_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales_targets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.competitions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.competition_branches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.competition_products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.branch_leaderboard_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

-- Grants
GRANT SELECT ON public.badges TO anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.branches TO authenticated;
GRANT SELECT ON public.branches TO anon;
GRANT SELECT, INSERT, UPDATE ON public.profiles TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.products TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.shifts TO authenticated;
GRANT SELECT, INSERT, DELETE ON public.employee_shifts TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.tasks TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.task_assignments TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.task_completions TO authenticated;
GRANT SELECT ON public.points_transactions TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.sales_targets TO authenticated;
GRANT SELECT, INSERT ON public.sales_entries TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.competitions TO authenticated;
GRANT SELECT, INSERT, DELETE ON public.competition_branches TO authenticated;
GRANT SELECT, INSERT, DELETE ON public.competition_products TO authenticated;
GRANT SELECT ON public.branch_leaderboard_entries TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.notifications TO authenticated;

-- Badges Policies
DROP POLICY IF EXISTS "badges_select_all" ON public.badges;
CREATE POLICY "badges_select_all" ON public.badges FOR SELECT USING (true);

-- Branches Policies
DROP POLICY IF EXISTS "branches_select" ON public.branches;
DROP POLICY IF EXISTS "branches_insert_admin" ON public.branches;
DROP POLICY IF EXISTS "branches_update_admin" ON public.branches;
CREATE POLICY "branches_select" ON public.branches FOR SELECT USING (true);
CREATE POLICY "branches_insert_admin" ON public.branches FOR INSERT WITH CHECK (public.get_my_role() = 'admin');
CREATE POLICY "branches_update_admin" ON public.branches FOR UPDATE USING (public.get_my_role() = 'admin') WITH CHECK (public.get_my_role() = 'admin');

-- Profiles Policies
DROP POLICY IF EXISTS "profiles_select_all_authenticated" ON public.profiles;
DROP POLICY IF EXISTS "profiles_update_admin_or_self" ON public.profiles;
CREATE POLICY "profiles_select_all_authenticated" ON public.profiles FOR SELECT USING (auth.uid() IS NOT NULL);
CREATE POLICY "profiles_update_admin_or_self" ON public.profiles FOR UPDATE USING (
  public.get_my_role() = 'admin' OR id = auth.uid()
);

-- Products Policies
DROP POLICY IF EXISTS "products_select" ON public.products;
DROP POLICY IF EXISTS "products_modify_manager_admin" ON public.products;
CREATE POLICY "products_select" ON public.products FOR SELECT USING (auth.uid() IS NOT NULL);
CREATE POLICY "products_modify_manager_admin" ON public.products FOR ALL USING (public.get_my_role() IN ('manager', 'admin'));

-- Shifts Policies
DROP POLICY IF EXISTS "shifts_select" ON public.shifts;
DROP POLICY IF EXISTS "shifts_modify" ON public.shifts;
CREATE POLICY "shifts_select" ON public.shifts FOR SELECT USING (auth.uid() IS NOT NULL);
CREATE POLICY "shifts_modify" ON public.shifts FOR ALL USING (public.get_my_role() IN ('manager', 'admin'));

-- Employee Shifts Policies
DROP POLICY IF EXISTS "employee_shifts_select" ON public.employee_shifts;
DROP POLICY IF EXISTS "employee_shifts_modify" ON public.employee_shifts;
CREATE POLICY "employee_shifts_select" ON public.employee_shifts FOR SELECT USING (auth.uid() IS NOT NULL);
CREATE POLICY "employee_shifts_modify" ON public.employee_shifts FOR ALL USING (public.get_my_role() IN ('manager', 'admin'));

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

-- Sales Targets Policies
DROP POLICY IF EXISTS "sales_targets_select" ON public.sales_targets;
DROP POLICY IF EXISTS "sales_targets_modify" ON public.sales_targets;
CREATE POLICY "sales_targets_select" ON public.sales_targets FOR SELECT USING (auth.uid() IS NOT NULL);
CREATE POLICY "sales_targets_modify" ON public.sales_targets FOR ALL USING (public.get_my_role() IN ('manager', 'admin'));

-- Sales Entries Policies
DROP POLICY IF EXISTS "sales_entries_select" ON public.sales_entries;
DROP POLICY IF EXISTS "sales_entries_insert" ON public.sales_entries;
CREATE POLICY "sales_entries_select" ON public.sales_entries FOR SELECT USING (auth.uid() IS NOT NULL);
CREATE POLICY "sales_entries_insert" ON public.sales_entries FOR INSERT WITH CHECK (
  auth.uid() IS NOT NULL AND employee_id = auth.uid()
);

-- Competitions Policies
DROP POLICY IF EXISTS "competitions_select" ON public.competitions;
DROP POLICY IF EXISTS "competitions_modify_admin" ON public.competitions;
CREATE POLICY "competitions_select" ON public.competitions FOR SELECT USING (auth.uid() IS NOT NULL);
CREATE POLICY "competitions_modify_admin" ON public.competitions FOR ALL USING (public.get_my_role() = 'admin');

DROP POLICY IF EXISTS "competition_branches_select" ON public.competition_branches;
DROP POLICY IF EXISTS "competition_branches_modify" ON public.competition_branches;
CREATE POLICY "competition_branches_select" ON public.competition_branches FOR SELECT USING (auth.uid() IS NOT NULL);
CREATE POLICY "competition_branches_modify" ON public.competition_branches FOR ALL USING (public.get_my_role() = 'admin');

DROP POLICY IF EXISTS "competition_products_select" ON public.competition_products;
DROP POLICY IF EXISTS "competition_products_modify" ON public.competition_products;
CREATE POLICY "competition_products_select" ON public.competition_products FOR SELECT USING (auth.uid() IS NOT NULL);
CREATE POLICY "competition_products_modify" ON public.competition_products FOR ALL USING (public.get_my_role() = 'admin');

DROP POLICY IF EXISTS "leaderboard_select" ON public.branch_leaderboard_entries;
CREATE POLICY "leaderboard_select" ON public.branch_leaderboard_entries FOR SELECT USING (auth.uid() IS NOT NULL);

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

INSERT INTO public.products (name, category, unit_price)
SELECT v.name, v.category, v.unit_price
FROM (VALUES
  ('Coca-Cola'::text,     'Beverage'::text, 50.00::numeric),
  ('Pepsi'::text,         'Beverage'::text, 45.00::numeric),
  ('Chips'::text,         'Snacks'::text,   30.00::numeric),
  ('7-Up'::text,          'Beverage'::text, 45.00::numeric),
  ('Mineral Water'::text, 'Beverage'::text, 20.00::numeric)
) AS v(name, category, unit_price)
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

CREATE OR REPLACE FUNCTION public.record_sale(
  p_branch_id uuid, p_shift_id uuid, p_sale_date date,
  p_product_id uuid, p_quantity integer
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE caller_id uuid := auth.uid(); caller_branch uuid; caller_role text;
  product_row public.products%ROWTYPE; entry_id uuid;
BEGIN
  SELECT role, branch_id INTO caller_role, caller_branch FROM public.profiles WHERE id = caller_id;
  IF caller_id IS NULL OR (caller_role <> 'admin' AND
     (caller_branch IS NULL OR caller_branch <> p_branch_id)) THEN
    RAISE EXCEPTION 'Unauthorized branch';
  END IF;
  IF p_quantity IS NULL OR p_quantity <= 0 OR p_sale_date > CURRENT_DATE THEN
    RAISE EXCEPTION 'Invalid sale';
  END IF;
  SELECT * INTO product_row FROM public.products WHERE id = p_product_id AND is_active;
  IF NOT FOUND THEN RAISE EXCEPTION 'Product is inactive or missing'; END IF;
  IF p_shift_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.shifts WHERE id = p_shift_id AND branch_id = p_branch_id AND is_active
  ) THEN RAISE EXCEPTION 'Invalid shift'; END IF;
  INSERT INTO public.sales_entries(branch_id, shift_id, sale_date, employee_id, product_id, quantity, unit_price)
  VALUES (p_branch_id, p_shift_id, p_sale_date, caller_id, p_product_id, p_quantity, product_row.unit_price)
  RETURNING id INTO entry_id;
  RETURN jsonb_build_object('success', true, 'id', entry_id);
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
GRANT EXECUTE ON FUNCTION public.record_sale(uuid, uuid, date, uuid, integer) TO authenticated;
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
DECLARE caller_id uuid := auth.uid(); caller_role text;
BEGIN
  SELECT role INTO caller_role FROM public.profiles WHERE id = caller_id;
  IF caller_id IS NULL OR caller_role NOT IN ('manager', 'admin')
     OR NULLIF(trim(p_review_note), '') IS NULL THEN
    RAISE EXCEPTION 'Authorized reviewer and reason are required';
  END IF;
  UPDATE public.task_completions SET status = 'rejected', reviewed_by = caller_id,
    reviewed_at = now(), review_note = trim(p_review_note)
  WHERE id = p_completion_id AND status = 'submitted';
  IF NOT FOUND THEN RAISE EXCEPTION 'Completion is not available'; END IF;
  UPDATE public.task_assignments ta SET status = 'rejected'
  WHERE ta.id = (SELECT assignment_id FROM public.task_completions WHERE id = p_completion_id);
  RETURN jsonb_build_object('success', true);
END;
$$;
GRANT EXECUTE ON FUNCTION public.reject_task_completion(uuid, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.generate_recurring_task_assignments(
  p_task_id uuid, p_user_ids uuid[], p_start_date date, p_end_date date
)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE caller_role text; caller_branch uuid; task_row public.tasks%ROWTYPE;
  employee_id uuid; scheduled_date date; step_days integer; created_count integer := 0;
BEGIN
  SELECT role, branch_id INTO caller_role, caller_branch
  FROM public.profiles WHERE id = auth.uid();
  IF caller_role NOT IN ('manager', 'admin') OR p_start_date IS NULL OR p_end_date IS NULL
     OR p_start_date > p_end_date OR p_end_date > p_start_date + 366 THEN
    RAISE EXCEPTION 'Invalid assignment request';
  END IF;
  SELECT * INTO task_row FROM public.tasks WHERE id = p_task_id AND is_active;
  IF NOT FOUND OR (caller_role = 'manager' AND task_row.branch_id IS NOT NULL
     AND task_row.branch_id IS DISTINCT FROM caller_branch) THEN
    RAISE EXCEPTION 'Task is outside the caller scope';
  END IF;
  step_days := CASE task_row.frequency WHEN 'weekly' THEN 7 WHEN 'monthly' THEN 30 ELSE 1 END;
  FOREACH employee_id IN ARRAY p_user_ids LOOP
    IF NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = employee_id
      AND p.role = 'employee' AND p.is_active
      AND (caller_role = 'admin' OR p.branch_id = caller_branch)) THEN
      RAISE EXCEPTION 'Employee is outside the caller scope';
    END IF;
    scheduled_date := p_start_date;
    WHILE scheduled_date <= p_end_date LOOP
      INSERT INTO public.task_assignments(task_id, user_id, scheduled_date, status)
      VALUES (p_task_id, employee_id, scheduled_date, 'pending')
      ON CONFLICT (task_id, user_id, scheduled_date) DO NOTHING;
      IF FOUND THEN created_count := created_count + 1; END IF;
      scheduled_date := scheduled_date + step_days;
    END LOOP;
  END LOOP;
  RETURN created_count;
END;
$$;
GRANT EXECUTE ON FUNCTION public.generate_recurring_task_assignments(uuid, uuid[], date, date) TO authenticated;

INSERT INTO storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
VALUES ('task-photos', 'task-photos', false, 5242880,
  ARRAY['image/jpeg','image/png','image/webp','image/heic','image/gif'])
ON CONFLICT (id) DO UPDATE SET public = false, file_size_limit = 5242880;

DROP POLICY IF EXISTS "task_photos_upload_own" ON storage.objects;
CREATE POLICY "task_photos_upload_own" ON storage.objects FOR INSERT
  WITH CHECK (bucket_id = 'task-photos' AND (storage.foldername(name))[1] = auth.uid()::text);
DROP POLICY IF EXISTS "task_photos_read_own" ON storage.objects;
CREATE POLICY "task_photos_read_own" ON storage.objects FOR SELECT
  USING (bucket_id = 'task-photos' AND (storage.foldername(name))[1] = auth.uid()::text);

-- Final branch-scoped access rules. These replace the permissive baseline rules.
DROP POLICY IF EXISTS "profiles_select_all_authenticated" ON public.profiles;
CREATE POLICY "profiles_select_scoped" ON public.profiles FOR SELECT USING (
  id = auth.uid()
  OR public.get_my_role() = 'admin'
  OR (public.get_my_role() = 'manager' AND branch_id = public.get_my_branch_id())
);

DROP POLICY IF EXISTS "shifts_select" ON public.shifts;
DROP POLICY IF EXISTS "shifts_modify" ON public.shifts;
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
CREATE POLICY "employee_shifts_select_scoped" ON public.employee_shifts FOR SELECT USING (
  employee_id = auth.uid()
  OR public.get_my_role() = 'admin'
  OR (public.get_my_role() = 'manager' AND EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = employee_shifts.employee_id AND p.branch_id = public.get_my_branch_id()
  ))
);
CREATE POLICY "employee_shifts_modify_scoped" ON public.employee_shifts FOR ALL USING (
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

DROP POLICY IF EXISTS "tasks_select" ON public.tasks;
DROP POLICY IF EXISTS "tasks_modify" ON public.tasks;
CREATE POLICY "tasks_select_scoped" ON public.tasks FOR SELECT USING (
  public.get_my_role() = 'admin'
  OR (is_active AND (branch_id IS NULL OR branch_id = public.get_my_branch_id()))
);
CREATE POLICY "tasks_modify_scoped" ON public.tasks FOR ALL USING (
  public.get_my_role() = 'admin'
  OR (public.get_my_role() = 'manager' AND (branch_id IS NULL OR branch_id = public.get_my_branch_id()))
) WITH CHECK (
  public.get_my_role() = 'admin'
  OR (public.get_my_role() = 'manager' AND (branch_id IS NULL OR branch_id = public.get_my_branch_id()))
);

DROP POLICY IF EXISTS "task_assignments_select" ON public.task_assignments;
DROP POLICY IF EXISTS "task_assignments_insert_manager" ON public.task_assignments;
DROP POLICY IF EXISTS "task_assignments_update" ON public.task_assignments;
CREATE POLICY "task_assignments_select_scoped" ON public.task_assignments FOR SELECT USING (
  user_id = auth.uid() OR public.get_my_role() = 'admin'
  OR (public.get_my_role() = 'manager' AND EXISTS (
    SELECT 1 FROM public.profiles p WHERE p.id = task_assignments.user_id
      AND p.branch_id = public.get_my_branch_id()
  ))
);
CREATE POLICY "task_assignments_insert_scoped" ON public.task_assignments FOR INSERT WITH CHECK (
  public.get_my_role() = 'admin' OR (public.get_my_role() = 'manager' AND EXISTS (
    SELECT 1 FROM public.profiles p JOIN public.tasks t ON t.id = task_assignments.task_id
    WHERE p.id = task_assignments.user_id AND p.branch_id = public.get_my_branch_id()
      AND (t.branch_id IS NULL OR t.branch_id = public.get_my_branch_id())
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
CREATE POLICY "sales_targets_select_scoped" ON public.sales_targets FOR SELECT USING (
  public.get_my_role() = 'admin' OR branch_id = public.get_my_branch_id()
);
CREATE POLICY "sales_targets_modify_scoped" ON public.sales_targets FOR ALL USING (
  public.get_my_role() = 'admin'
  OR (public.get_my_role() = 'manager' AND branch_id = public.get_my_branch_id())
) WITH CHECK (
  public.get_my_role() = 'admin'
  OR (public.get_my_role() = 'manager' AND branch_id = public.get_my_branch_id())
);

DROP POLICY IF EXISTS "sales_entries_select" ON public.sales_entries;
DROP POLICY IF EXISTS "sales_entries_insert" ON public.sales_entries;
CREATE POLICY "sales_entries_select_scoped" ON public.sales_entries FOR SELECT USING (
  employee_id = auth.uid() OR public.get_my_role() = 'admin'
  OR (public.get_my_role() = 'manager' AND branch_id = public.get_my_branch_id())
);
REVOKE INSERT ON public.sales_entries FROM authenticated;

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

-- 1. Test Task Point Awarding & Duplicate Protection:
--    SELECT public.approve_task_completion('<completion_uuid>', '<manager_uuid>', 'Approved excellent restock');
--    -- Running a second time will throw: 'This completion has already been approved'
--
-- 2. Test Badge Tier Calculation:
--    SELECT public.recalculate_user_badge('<user_uuid>');
--
-- 3. Test Recurring Task Generation:
--    SELECT public.generate_recurring_task_assignments('<task_uuid>', ARRAY['<user1_uuid>', '<user2_uuid>']::uuid[], '2026-09-01', '2026-09-07');
--
-- 4. Test Competition Leaderboard Calculation:
--    SELECT public.recalculate_competition_leaderboard('<competition_uuid>');
-- =============================================================
