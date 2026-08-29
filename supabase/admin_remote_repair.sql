-- RetailFlow hosted Supabase Admin repair patch
-- Safe incremental patch: no demo users/branches/data are inserted.
-- Run in: Supabase Dashboard -> SQL Editor -> New query -> Run

BEGIN;

-- -----------------------------------------------------------------------------
-- 1) Core helper functions used by RLS
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_my_role()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT role
  FROM public.profiles
  WHERE id = auth.uid() AND is_active = true;
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
  WHERE id = auth.uid() AND is_active = true;
$$;

REVOKE EXECUTE ON FUNCTION public.get_my_role() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_my_branch_id() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_role() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_branch_id() TO authenticated;

-- -----------------------------------------------------------------------------
-- 2) Auth -> profile trigger. Public sign-up is employee-first by design.
--    The create-user Edge Function / authenticated Admin then applies role.
-- -----------------------------------------------------------------------------
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
  EXCEPTION WHEN invalid_text_representation THEN
    selected_branch := NULL;
  END;

  IF selected_branch IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.branches
    WHERE id = selected_branch AND is_active = true
  ) THEN
    selected_branch := NULL;
  END IF;

  INSERT INTO public.profiles (
    id, name, email, role, branch_id, is_active, total_lifetime_points
  )
  VALUES (
    new.id,
    COALESCE(
      NULLIF(trim(new.raw_user_meta_data ->> 'name'), ''),
      split_part(COALESCE(new.email, 'Employee'), '@', 1)
    ),
    lower(COALESCE(new.email, '')),
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

-- Repair Auth accounts that are missing only their profile row. This does NOT
-- trust client-provided role metadata, so a public user cannot self-promote.
INSERT INTO public.profiles (
  id, name, email, role, branch_id, is_active, total_lifetime_points
)
SELECT
  u.id,
  COALESCE(
    NULLIF(trim(u.raw_user_meta_data ->> 'name'), ''),
    split_part(COALESCE(u.email, 'Employee'), '@', 1)
  ),
  lower(COALESCE(u.email, '')),
  CASE
    WHEN lower(COALESCE(u.email, '')) = 'admin@retailflow.com' THEN 'admin'
    ELSE 'employee'
  END,
  CASE
    WHEN lower(COALESCE(u.email, '')) = 'admin@retailflow.com' THEN NULL
    WHEN COALESCE(u.raw_user_meta_data ->> 'branch_id', '') ~*
      '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      AND EXISTS (
        SELECT 1 FROM public.branches b
        WHERE b.id = (u.raw_user_meta_data ->> 'branch_id')::uuid
          AND b.is_active = true
      )
      THEN (u.raw_user_meta_data ->> 'branch_id')::uuid
    ELSE NULL
  END,
  true,
  0
FROM auth.users u
WHERE NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = u.id)
ON CONFLICT (id) DO NOTHING;

-- Normalize emails so client-side duplicate checks are deterministic.
UPDATE public.profiles
SET email = lower(trim(email))
WHERE email IS DISTINCT FROM lower(trim(email));

CREATE UNIQUE INDEX IF NOT EXISTS idx_profiles_email_unique
  ON public.profiles (lower(email));

-- -----------------------------------------------------------------------------
-- 3) RLS and grants needed by Admin features
-- -----------------------------------------------------------------------------
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.branches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales_targets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales_imports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales_import_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales_import_failures ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.competitions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.competition_branches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.competition_products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.branch_leaderboard_entries ENABLE ROW LEVEL SECURITY;

-- Grants for the authenticated role (Flutter app sessions).
GRANT SELECT, INSERT, UPDATE ON public.profiles TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.branches TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.products TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.sales_targets TO authenticated;
GRANT SELECT ON public.sales_imports TO authenticated;
GRANT SELECT ON public.sales_import_items TO authenticated;
GRANT SELECT ON public.sales_import_failures TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.competitions TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.competition_branches TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.competition_products TO authenticated;
GRANT SELECT ON public.branch_leaderboard_entries TO authenticated;

-- Grants for the service_role (used by Edge Functions with the service role key).
-- service_role bypasses RLS but still needs table-level privileges.
GRANT ALL ON public.profiles TO service_role;
GRANT ALL ON public.branches TO service_role;
GRANT ALL ON public.products TO service_role;
GRANT ALL ON public.sales_targets TO service_role;
GRANT ALL ON public.sales_imports TO service_role;
GRANT ALL ON public.sales_import_items TO service_role;
GRANT ALL ON public.sales_import_failures TO service_role;
GRANT ALL ON public.competitions TO service_role;
GRANT ALL ON public.competition_branches TO service_role;
GRANT ALL ON public.competition_products TO service_role;
GRANT ALL ON public.branch_leaderboard_entries TO service_role;

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

DROP POLICY IF EXISTS "branches_select" ON public.branches;
DROP POLICY IF EXISTS "branches_insert_admin" ON public.branches;
DROP POLICY IF EXISTS "branches_update_admin" ON public.branches;
CREATE POLICY "branches_select" ON public.branches FOR SELECT USING (
  is_active OR public.get_my_role() = 'admin'
);
CREATE POLICY "branches_insert_admin" ON public.branches FOR INSERT
  WITH CHECK (public.get_my_role() = 'admin');
CREATE POLICY "branches_update_admin" ON public.branches FOR UPDATE
  USING (public.get_my_role() = 'admin')
  WITH CHECK (public.get_my_role() = 'admin');

DROP POLICY IF EXISTS "products_select" ON public.products;
DROP POLICY IF EXISTS "products_select_manager_admin" ON public.products;
DROP POLICY IF EXISTS "products_modify_manager_admin" ON public.products;
DROP POLICY IF EXISTS "products_modify_manager_admin_final" ON public.products;
CREATE POLICY "products_select_manager_admin" ON public.products FOR SELECT USING (
  public.get_my_role() IN ('manager', 'admin')
);
CREATE POLICY "products_modify_manager_admin_final" ON public.products FOR ALL USING (
  public.get_my_role() IN ('manager', 'admin')
) WITH CHECK (
  public.get_my_role() IN ('manager', 'admin')
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

DROP POLICY IF EXISTS "competitions_select" ON public.competitions;
DROP POLICY IF EXISTS "competitions_select_scoped" ON public.competitions;
DROP POLICY IF EXISTS "competitions_modify_admin" ON public.competitions;
DROP POLICY IF EXISTS "competitions_modify_admin_final" ON public.competitions;
CREATE POLICY "competitions_select_scoped" ON public.competitions FOR SELECT USING (
  public.get_my_role() = 'admin'
  OR (public.get_my_role() = 'manager' AND EXISTS (
    SELECT 1 FROM public.competition_branches cb
    WHERE cb.competition_id = competitions.id
      AND cb.branch_id = public.get_my_branch_id()
  ))
);
CREATE POLICY "competitions_modify_admin_final" ON public.competitions FOR ALL USING (
  public.get_my_role() = 'admin'
) WITH CHECK (
  public.get_my_role() = 'admin'
);

DROP POLICY IF EXISTS "competition_branches_select" ON public.competition_branches;
DROP POLICY IF EXISTS "competition_branches_select_scoped" ON public.competition_branches;
DROP POLICY IF EXISTS "competition_branches_modify" ON public.competition_branches;
DROP POLICY IF EXISTS "competition_branches_modify_admin_final" ON public.competition_branches;
CREATE POLICY "competition_branches_select_scoped" ON public.competition_branches FOR SELECT USING (
  public.get_my_role() = 'admin'
  OR (public.get_my_role() = 'manager' AND EXISTS (
    SELECT 1 FROM public.competition_branches own_branch
    WHERE own_branch.competition_id = competition_branches.competition_id
      AND own_branch.branch_id = public.get_my_branch_id()
  ))
);
CREATE POLICY "competition_branches_modify_admin_final" ON public.competition_branches FOR ALL USING (
  public.get_my_role() = 'admin'
) WITH CHECK (
  public.get_my_role() = 'admin'
);

DROP POLICY IF EXISTS "competition_products_select" ON public.competition_products;
DROP POLICY IF EXISTS "competition_products_select_scoped" ON public.competition_products;
DROP POLICY IF EXISTS "competition_products_modify" ON public.competition_products;
DROP POLICY IF EXISTS "competition_products_modify_admin_final" ON public.competition_products;
CREATE POLICY "competition_products_select_scoped" ON public.competition_products FOR SELECT USING (
  public.get_my_role() = 'admin'
  OR (public.get_my_role() = 'manager' AND EXISTS (
    SELECT 1 FROM public.competition_branches cb
    WHERE cb.competition_id = competition_products.competition_id
      AND cb.branch_id = public.get_my_branch_id()
  ))
);
CREATE POLICY "competition_products_modify_admin_final" ON public.competition_products FOR ALL USING (
  public.get_my_role() = 'admin'
) WITH CHECK (
  public.get_my_role() = 'admin'
);

DROP POLICY IF EXISTS "leaderboard_select" ON public.branch_leaderboard_entries;
DROP POLICY IF EXISTS "leaderboard_select_scoped" ON public.branch_leaderboard_entries;
CREATE POLICY "leaderboard_select_scoped" ON public.branch_leaderboard_entries FOR SELECT USING (
  public.get_my_role() = 'admin'
  OR (public.get_my_role() = 'manager' AND EXISTS (
    SELECT 1 FROM public.competition_branches cb
    WHERE cb.competition_id = branch_leaderboard_entries.competition_id
      AND cb.branch_id = public.get_my_branch_id()
  ))
);

-- -----------------------------------------------------------------------------
-- 4) Prevent duplicate company-wide sales targets where shift_id is NULL.
--    PostgreSQL's normal UNIQUE constraint treats NULL values as distinct.
--    If an older build already created duplicate all-shifts rows, keep the most
--    recently created row for each branch/date before adding the guard.
-- -----------------------------------------------------------------------------
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

CREATE UNIQUE INDEX IF NOT EXISTS idx_sales_targets_no_shift_unique
  ON public.sales_targets (branch_id, target_date)
  WHERE shift_id IS NULL;

-- Keep the normal branch+shift+date path protected as well.
CREATE UNIQUE INDEX IF NOT EXISTS idx_sales_targets_with_shift_unique
  ON public.sales_targets (branch_id, shift_id, target_date)
  WHERE shift_id IS NOT NULL;

-- -----------------------------------------------------------------------------
-- 5) Server RPC grants used by Admin sales/competition features.
-- -----------------------------------------------------------------------------
DO $$
BEGIN
  IF to_regprocedure('public.import_sales_data(uuid,uuid,date,text,numeric,text,jsonb)') IS NOT NULL THEN
    EXECUTE 'GRANT EXECUTE ON FUNCTION public.import_sales_data(uuid, uuid, date, text, numeric, text, jsonb) TO authenticated';
  END IF;
  IF to_regprocedure('public.recalculate_competition_leaderboard(uuid)') IS NOT NULL THEN
    EXECUTE 'GRANT EXECUTE ON FUNCTION public.recalculate_competition_leaderboard(uuid) TO authenticated';
  END IF;
END $$;

COMMIT;

-- Quick verification queries (read-only):
-- select id, email, role, branch_id, is_active from public.profiles order by created_at desc;
-- select id, name, manager_id, is_active from public.branches order by name;
