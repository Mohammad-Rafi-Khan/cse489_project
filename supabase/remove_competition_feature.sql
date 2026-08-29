-- RetailFlow: remove competition feature and orphaned leaderboard artifacts.
-- Safe migration script for Supabase SQL editor.
-- This is intentionally idempotent and only removes objects tied to the old
-- product-competition feature while leaving the core task, sales, and pricing
-- workflow intact.

BEGIN;

-- 1) Remove scheduler jobs created for competition lifecycle tracking.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'retailflow-sync-competition-statuses') THEN
      PERFORM cron.unschedule((SELECT jobid FROM cron.job WHERE jobname = 'retailflow-sync-competition-statuses'));
    END IF;
  END IF;
EXCEPTION WHEN undefined_table OR undefined_function THEN
  NULL;
END $$;

-- 2) Drop competition-specific security policies.
DROP POLICY IF EXISTS "competitions_select" ON public.competitions;
DROP POLICY IF EXISTS "competitions_select_scoped" ON public.competitions;
DROP POLICY IF EXISTS "competitions_modify_admin" ON public.competitions;
DROP POLICY IF EXISTS "competitions_modify_admin_final" ON public.competitions;

DROP POLICY IF EXISTS "competition_branches_select" ON public.competition_branches;
DROP POLICY IF EXISTS "competition_branches_select_scoped" ON public.competition_branches;
DROP POLICY IF EXISTS "competition_branches_modify" ON public.competition_branches;
DROP POLICY IF EXISTS "competition_branches_modify_admin_final" ON public.competition_branches;

DROP POLICY IF EXISTS "competition_products_select" ON public.competition_products;
DROP POLICY IF EXISTS "competition_products_select_scoped" ON public.competition_products;
DROP POLICY IF EXISTS "competition_products_modify" ON public.competition_products;
DROP POLICY IF EXISTS "competition_products_modify_admin_final" ON public.competition_products;

DROP POLICY IF EXISTS "leaderboard_select" ON public.branch_leaderboard_entries;
DROP POLICY IF EXISTS "leaderboard_select_scoped" ON public.branch_leaderboard_entries;

-- 3) Revoke grants on competition tables and their functions.
REVOKE ALL ON TABLE public.competitions FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TABLE public.competition_branches FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TABLE public.competition_products FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TABLE public.branch_leaderboard_entries FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.recalculate_competition_leaderboard(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.sync_competition_statuses() FROM PUBLIC, anon, authenticated, service_role;

-- 4) Drop competition-specific functions.
DROP FUNCTION IF EXISTS public.recalculate_competition_leaderboard(uuid);
DROP FUNCTION IF EXISTS public.sync_competition_statuses();

-- 5) Drop competition tables if present.
DROP TABLE IF EXISTS public.branch_leaderboard_entries CASCADE;
DROP TABLE IF EXISTS public.competition_products CASCADE;
DROP TABLE IF EXISTS public.competition_branches CASCADE;
DROP TABLE IF EXISTS public.competitions CASCADE;

-- 6) Remove stale notification data that referenced competition lifecycle events.
DELETE FROM public.notifications
WHERE type IN (
  'competition_started',
  'competition_ended',
  'competition_status_synced',
  'branch_rank_changed',
  'competition'
);

COMMIT;

-- Optional verification queries for a live database:
-- SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' AND table_name IN ('competitions','competition_branches','competition_products','branch_leaderboard_entries');
-- SELECT proname FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname ILIKE '%competition%';
-- SELECT jobname FROM cron.job WHERE jobname LIKE '%competition%';
