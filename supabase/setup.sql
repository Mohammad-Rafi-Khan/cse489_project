-- =============================================================
-- RetailFlow — Supabase Database Setup (Milestone 2)
--
-- Scope:
--   1) Registration
--   2) Login / role-based access
--   3) Product management
--   4) Task assignment
--
-- Run in: Supabase Dashboard → SQL Editor
-- =============================================================

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ─────────────────────────────────────────────────────────────
-- 1. CORE TABLES NEEDED BY AUTH / REGISTRATION
-- ─────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.branches (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name        text NOT NULL,
  location    text,
  manager_id  uuid,
  is_active   boolean NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.profiles (
  id                    uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  name                  text NOT NULL,
  email                 text NOT NULL,
  role                  text NOT NULL DEFAULT 'employee'
                          CHECK (role IN ('employee', 'manager', 'admin')),
  branch_id             uuid REFERENCES public.branches(id) ON DELETE SET NULL,
  current_badge_id      uuid,
  total_lifetime_points integer NOT NULL DEFAULT 0,
  is_active             boolean NOT NULL DEFAULT true,
  created_at            timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_profiles_email_unique
  ON public.profiles (lower(email));

CREATE INDEX IF NOT EXISTS idx_profiles_branch_id
  ON public.profiles(branch_id);

CREATE INDEX IF NOT EXISTS idx_profiles_role
  ON public.profiles(role);

-- Add branches.manager_id → profiles.id after profiles exists.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'branches_manager_id_fkey'
      AND conrelid = 'public.branches'::regclass
  ) THEN
    ALTER TABLE public.branches
      ADD CONSTRAINT branches_manager_id_fkey
      FOREIGN KEY (manager_id)
      REFERENCES public.profiles(id)
      ON DELETE SET NULL;
  END IF;
END $$;

-- ─────────────────────────────────────────────────────────────
-- 2. HELPER FUNCTIONS FOR RLS
-- ─────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.get_my_role()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT role
  FROM public.profiles
  WHERE id = auth.uid();
$$;

CREATE OR REPLACE FUNCTION public.get_my_branch_id()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT branch_id
  FROM public.profiles
  WHERE id = auth.uid();
$$;

-- Public sign-up profile creation.
-- The Flutter app passes `name` and `branch_id` as auth metadata.
-- The role is ALWAYS forced to employee here, so public sign-up cannot
-- self-register as manager/admin.
CREATE OR REPLACE FUNCTION public.handle_new_retailflow_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  selected_branch uuid;
BEGIN
  BEGIN
    selected_branch := NULLIF(new.raw_user_meta_data ->> 'branch_id', '')::uuid;
  EXCEPTION
    WHEN invalid_text_representation THEN
      selected_branch := NULL;
  END;

  INSERT INTO public.profiles (
    id,
    name,
    email,
    role,
    branch_id,
    is_active,
    total_lifetime_points
  )
  VALUES (
    new.id,
    COALESCE(NULLIF(trim(new.raw_user_meta_data ->> 'name'), ''), split_part(COALESCE(new.email, 'Employee'), '@', 1)),
    COALESCE(new.email, ''),
    'employee',
    selected_branch,
    true,
    0
  )
  ON CONFLICT (id) DO NOTHING;

  RETURN new;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created_retailflow ON auth.users;
CREATE TRIGGER on_auth_user_created_retailflow
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_retailflow_user();

-- ─────────────────────────────────────────────────────────────
-- 3. BRANCH / PROFILE SECURITY
-- ─────────────────────────────────────────────────────────────

ALTER TABLE public.branches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- Explicit privileges. RLS still decides which rows can be accessed.
GRANT SELECT ON public.branches TO anon, authenticated;
GRANT SELECT ON public.profiles TO authenticated;
GRANT UPDATE ON public.profiles TO authenticated;

DROP POLICY IF EXISTS "branches_select_authenticated" ON public.branches;
DROP POLICY IF EXISTS "branches_select_active_public" ON public.branches;
DROP POLICY IF EXISTS "branches_select_admin" ON public.branches;
DROP POLICY IF EXISTS "branches_insert_admin" ON public.branches;
DROP POLICY IF EXISTS "branches_update_admin" ON public.branches;

-- Registration needs branch names BEFORE login, so active branches are public.
CREATE POLICY "branches_select_active_public"
  ON public.branches FOR SELECT
  USING (is_active = true);

CREATE POLICY "branches_select_admin"
  ON public.branches FOR SELECT
  USING (public.get_my_role() = 'admin');

CREATE POLICY "branches_insert_admin"
  ON public.branches FOR INSERT
  WITH CHECK (public.get_my_role() = 'admin');

CREATE POLICY "branches_update_admin"
  ON public.branches FOR UPDATE
  USING (public.get_my_role() = 'admin')
  WITH CHECK (public.get_my_role() = 'admin');

DROP POLICY IF EXISTS "profiles_select_own" ON public.profiles;
DROP POLICY IF EXISTS "profiles_select_manager" ON public.profiles;
DROP POLICY IF EXISTS "profiles_select_admin" ON public.profiles;
DROP POLICY IF EXISTS "profiles_insert_own" ON public.profiles;
DROP POLICY IF EXISTS "profiles_update_own" ON public.profiles;
DROP POLICY IF EXISTS "profiles_update_admin" ON public.profiles;

CREATE POLICY "profiles_select_own"
  ON public.profiles FOR SELECT
  USING (id = auth.uid());

-- Managers can read people in their own branch. The Flutter task picker then
-- filters this to active employees only.
CREATE POLICY "profiles_select_manager"
  ON public.profiles FOR SELECT
  USING (
    public.get_my_role() = 'manager'
    AND branch_id = public.get_my_branch_id()
  );

CREATE POLICY "profiles_select_admin"
  ON public.profiles FOR SELECT
  USING (public.get_my_role() = 'admin');

-- There is intentionally NO client-side INSERT policy for profiles.
-- The auth trigger above creates employee profiles securely.
-- There is also no self-update policy in Milestone 2, preventing a user from
-- changing their own role/is_active/points through a custom client request.
CREATE POLICY "profiles_update_admin"
  ON public.profiles FOR UPDATE
  USING (public.get_my_role() = 'admin')
  WITH CHECK (public.get_my_role() = 'admin');

-- ─────────────────────────────────────────────────────────────
-- 4. PRODUCTS
-- ─────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.products (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name        text NOT NULL,
  category    text NOT NULL,
  unit_price  numeric(10,2) NOT NULL CHECK (unit_price > 0),
  is_active   boolean NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_products_is_active
  ON public.products(is_active);

ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT, UPDATE ON public.products TO authenticated;

DROP POLICY IF EXISTS "products_select_authenticated" ON public.products;
DROP POLICY IF EXISTS "products_insert_manager_admin" ON public.products;
DROP POLICY IF EXISTS "products_update_manager_admin" ON public.products;

CREATE POLICY "products_select_authenticated"
  ON public.products FOR SELECT
  USING (auth.uid() IS NOT NULL);

CREATE POLICY "products_insert_manager_admin"
  ON public.products FOR INSERT
  WITH CHECK (public.get_my_role() IN ('manager', 'admin'));

CREATE POLICY "products_update_manager_admin"
  ON public.products FOR UPDATE
  USING (public.get_my_role() IN ('manager', 'admin'))
  WITH CHECK (public.get_my_role() IN ('manager', 'admin'));

-- ─────────────────────────────────────────────────────────────
-- 5. TASK TEMPLATES
-- ─────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.tasks (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title              text NOT NULL,
  description        text,
  frequency          text NOT NULL DEFAULT 'daily'
                       CHECK (frequency IN ('daily', 'weekly', 'monthly')),
  branch_id          uuid REFERENCES public.branches(id) ON DELETE SET NULL,
  created_by         uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  base_points        integer NOT NULL DEFAULT 0 CHECK (base_points >= 0),
  photo_bonus_points integer NOT NULL DEFAULT 0 CHECK (photo_bonus_points >= 0),
  photo_required     boolean NOT NULL DEFAULT false,
  is_active          boolean NOT NULL DEFAULT true,
  created_at         timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_tasks_branch_id
  ON public.tasks(branch_id);

CREATE INDEX IF NOT EXISTS idx_tasks_is_active
  ON public.tasks(is_active);

ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT, UPDATE ON public.tasks TO authenticated;

DROP POLICY IF EXISTS "tasks_select_authenticated" ON public.tasks;
DROP POLICY IF EXISTS "tasks_select_branch" ON public.tasks;
DROP POLICY IF EXISTS "tasks_select_admin" ON public.tasks;
DROP POLICY IF EXISTS "tasks_insert_manager_admin" ON public.tasks;
DROP POLICY IF EXISTS "tasks_insert_manager" ON public.tasks;
DROP POLICY IF EXISTS "tasks_insert_admin" ON public.tasks;
DROP POLICY IF EXISTS "tasks_update_manager_admin" ON public.tasks;
DROP POLICY IF EXISTS "tasks_update_manager" ON public.tasks;
DROP POLICY IF EXISTS "tasks_update_admin" ON public.tasks;

-- Employees/managers only need active task templates for their own branch.
-- NULL branch_id is treated as an organization-wide task template.
CREATE POLICY "tasks_select_branch"
  ON public.tasks FOR SELECT
  USING (
    auth.uid() IS NOT NULL
    AND is_active = true
    AND (
      branch_id IS NULL
      OR branch_id = public.get_my_branch_id()
    )
  );

CREATE POLICY "tasks_select_admin"
  ON public.tasks FOR SELECT
  USING (public.get_my_role() = 'admin');

CREATE POLICY "tasks_insert_manager"
  ON public.tasks FOR INSERT
  WITH CHECK (
    public.get_my_role() = 'manager'
    AND (
      branch_id = public.get_my_branch_id()
      OR branch_id IS NULL
    )
  );

CREATE POLICY "tasks_insert_admin"
  ON public.tasks FOR INSERT
  WITH CHECK (public.get_my_role() = 'admin');

CREATE POLICY "tasks_update_manager"
  ON public.tasks FOR UPDATE
  USING (
    public.get_my_role() = 'manager'
    AND (
      branch_id = public.get_my_branch_id()
      OR branch_id IS NULL
    )
  )
  WITH CHECK (
    public.get_my_role() = 'manager'
    AND (
      branch_id = public.get_my_branch_id()
      OR branch_id IS NULL
    )
  );

CREATE POLICY "tasks_update_admin"
  ON public.tasks FOR UPDATE
  USING (public.get_my_role() = 'admin')
  WITH CHECK (public.get_my_role() = 'admin');

-- ─────────────────────────────────────────────────────────────
-- 6. TASK ASSIGNMENTS
-- ─────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.task_assignments (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id        uuid NOT NULL REFERENCES public.tasks(id) ON DELETE RESTRICT,
  user_id        uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  scheduled_date date NOT NULL,
  due_at         timestamptz,
  status         text NOT NULL DEFAULT 'pending'
                   CHECK (status IN ('pending', 'completed', 'approved', 'rejected')),
  assigned_at    timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_task_assignments_user_id
  ON public.task_assignments(user_id);

CREATE INDEX IF NOT EXISTS idx_task_assignments_task_id
  ON public.task_assignments(task_id);

CREATE INDEX IF NOT EXISTS idx_task_assignments_scheduled_date
  ON public.task_assignments(scheduled_date);

ALTER TABLE public.task_assignments ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT, UPDATE ON public.task_assignments TO authenticated;

DROP POLICY IF EXISTS "task_assignments_select_own" ON public.task_assignments;
DROP POLICY IF EXISTS "task_assignments_select_manager" ON public.task_assignments;
DROP POLICY IF EXISTS "task_assignments_select_admin" ON public.task_assignments;
DROP POLICY IF EXISTS "task_assignments_insert_manager" ON public.task_assignments;
DROP POLICY IF EXISTS "task_assignments_insert_admin" ON public.task_assignments;
DROP POLICY IF EXISTS "task_assignments_update_manager_admin" ON public.task_assignments;
DROP POLICY IF EXISTS "task_assignments_update_manager" ON public.task_assignments;
DROP POLICY IF EXISTS "task_assignments_update_admin" ON public.task_assignments;

CREATE POLICY "task_assignments_select_own"
  ON public.task_assignments FOR SELECT
  USING (user_id = auth.uid());

CREATE POLICY "task_assignments_select_manager"
  ON public.task_assignments FOR SELECT
  USING (
    public.get_my_role() = 'manager'
    AND EXISTS (
      SELECT 1
      FROM public.profiles p
      WHERE p.id = task_assignments.user_id
        AND p.role = 'employee'
        AND p.branch_id = public.get_my_branch_id()
    )
  );

CREATE POLICY "task_assignments_select_admin"
  ON public.task_assignments FOR SELECT
  USING (public.get_my_role() = 'admin');

-- Manager must assign BOTH an employee and a task belonging to the manager's
-- branch. This prevents cross-branch assignment even if a UUID is guessed.
CREATE POLICY "task_assignments_insert_manager"
  ON public.task_assignments FOR INSERT
  WITH CHECK (
    public.get_my_role() = 'manager'
    AND EXISTS (
      SELECT 1
      FROM public.profiles p
      WHERE p.id = task_assignments.user_id
        AND p.role = 'employee'
        AND p.is_active = true
        AND p.branch_id = public.get_my_branch_id()
    )
    AND EXISTS (
      SELECT 1
      FROM public.tasks t
      WHERE t.id = task_assignments.task_id
        AND t.is_active = true
        AND (
          t.branch_id = public.get_my_branch_id()
          OR t.branch_id IS NULL
        )
    )
  );

CREATE POLICY "task_assignments_insert_admin"
  ON public.task_assignments FOR INSERT
  WITH CHECK (public.get_my_role() = 'admin');

-- Not used by Milestone 2 UI, but kept ready for the later approval workflow.
CREATE POLICY "task_assignments_update_manager"
  ON public.task_assignments FOR UPDATE
  USING (
    public.get_my_role() = 'manager'
    AND EXISTS (
      SELECT 1
      FROM public.profiles p
      WHERE p.id = task_assignments.user_id
        AND p.branch_id = public.get_my_branch_id()
    )
  )
  WITH CHECK (
    public.get_my_role() = 'manager'
    AND EXISTS (
      SELECT 1
      FROM public.profiles p
      WHERE p.id = task_assignments.user_id
        AND p.branch_id = public.get_my_branch_id()
    )
  );

CREATE POLICY "task_assignments_update_admin"
  ON public.task_assignments FOR UPDATE
  USING (public.get_my_role() = 'admin')
  WITH CHECK (public.get_my_role() = 'admin');

-- ─────────────────────────────────────────────────────────────
-- 7. DEMO / SEED DATA
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
  SELECT 1
  FROM public.products p
  WHERE lower(p.name) = lower(v.name)
    AND lower(p.category) = lower(v.category)
);

INSERT INTO public.tasks (title, description, frequency, branch_id, base_points)
SELECT v.title, v.description, v.frequency, v.branch_id, v.base_points
FROM (VALUES
  ('Shelf Restocking'::text,    'Restock all product shelves to full capacity.'::text,   'daily'::text,  '11111111-1111-1111-1111-111111111111'::uuid, 10),
  ('Store Cleaning'::text,      'Clean the store floor, windows, and counters.'::text,   'daily'::text,  '11111111-1111-1111-1111-111111111111'::uuid, 10),
  ('Inventory Check'::text,     'Count and verify current stock levels.'::text,          'weekly'::text, '11111111-1111-1111-1111-111111111111'::uuid, 30),
  ('Display Arrangement'::text, 'Arrange promotional displays at the storefront.'::text,'weekly'::text, '11111111-1111-1111-1111-111111111111'::uuid, 20),
  ('Shelf Restocking'::text,    'Restock all product shelves to full capacity.'::text,   'daily'::text,  '22222222-2222-2222-2222-222222222222'::uuid, 10),
  ('Store Cleaning'::text,      'Clean the store floor, windows, and counters.'::text,   'daily'::text,  '22222222-2222-2222-2222-222222222222'::uuid, 10),
  ('Inventory Check'::text,     'Count and verify current stock levels.'::text,          'weekly'::text, '22222222-2222-2222-2222-222222222222'::uuid, 30),
  ('Display Arrangement'::text, 'Arrange promotional displays at the storefront.'::text,'weekly'::text, '22222222-2222-2222-2222-222222222222'::uuid, 20),
  ('Shelf Restocking'::text,    'Restock all product shelves to full capacity.'::text,   'daily'::text,  '33333333-3333-3333-3333-333333333333'::uuid, 10),
  ('Store Cleaning'::text,      'Clean the store floor, windows, and counters.'::text,   'daily'::text,  '33333333-3333-3333-3333-333333333333'::uuid, 10),
  ('Inventory Check'::text,     'Count and verify current stock levels.'::text,          'weekly'::text, '33333333-3333-3333-3333-333333333333'::uuid, 30),
  ('Display Arrangement'::text, 'Arrange promotional displays at the storefront.'::text,'weekly'::text, '33333333-3333-3333-3333-333333333333'::uuid, 20)
) AS v(title, description, frequency, branch_id, base_points)
WHERE NOT EXISTS (
  SELECT 1
  FROM public.tasks t
  WHERE t.title = v.title
    AND t.branch_id = v.branch_id
);

-- ─────────────────────────────────────────────────────────────
-- 8. DEMO ACCOUNT SETUP
-- ─────────────────────────────────────────────────────────────
-- Recommended for the milestone video:
--
-- 1) Run this setup.sql FIRST (so the auth trigger exists).
-- 2) Supabase Dashboard → Authentication → Users → Add user
--    Create:
--       manager1@retailflow.com
--       employee1@retailflow.com
--       employee2@retailflow.com
--    Use demo passwords of your choice. Do NOT commit them to Git.
--
-- 3) Copy the UUID of each user and run the following, replacing placeholders:
--
-- INSERT INTO public.profiles (id, name, email, role, branch_id)
-- VALUES
--   ('<manager-uuid>', 'Sarah Manager', 'manager1@retailflow.com', 'manager',  '11111111-1111-1111-1111-111111111111'),
--   ('<emp1-uuid>',    'Rahim Ahmed',   'employee1@retailflow.com','employee', '11111111-1111-1111-1111-111111111111'),
--   ('<emp2-uuid>',    'Nabila Khan',   'employee2@retailflow.com','employee', '11111111-1111-1111-1111-111111111111')
-- ON CONFLICT (id) DO UPDATE SET
--   name = EXCLUDED.name,
--   email = EXCLUDED.email,
--   role = EXCLUDED.role,
--   branch_id = EXCLUDED.branch_id,
--   is_active = true;
--
-- UPDATE public.branches
-- SET manager_id = '<manager-uuid>'
-- WHERE id = '11111111-1111-1111-1111-111111111111';
--
-- NOTE: Public app registration always creates an EMPLOYEE account.
-- Manager/Admin roles should only be assigned from trusted server/admin SQL.
-- =============================================================
