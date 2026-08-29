-- =============================================================
-- Quick-fix: Grant service_role and authenticated table access
-- Run this in: Supabase Dashboard → SQL Editor → New query → Run
-- =============================================================

-- Grant service_role full access (needed by Edge Functions).
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

-- Add missing INSERT grant on profiles for authenticated role.
GRANT INSERT ON public.profiles TO authenticated;

-- Add missing INSERT policy on profiles for admin/self.
DROP POLICY IF EXISTS "profiles_insert_trigger_or_admin" ON public.profiles;
CREATE POLICY "profiles_insert_trigger_or_admin" ON public.profiles FOR INSERT
  WITH CHECK (public.get_my_role() = 'admin' OR id = auth.uid());

-- Verify: should show service_role and authenticated with proper permissions
SELECT grantee, privilege_type
FROM information_schema.role_table_grants
WHERE table_name = 'profiles'
  AND table_schema = 'public'
ORDER BY grantee, privilege_type;
