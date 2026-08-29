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

  -- Public registration is always employee-only. Admin-created users are
  -- promoted to manager/admin by the create-user Edge Function after Auth
  -- creates this initial profile row.
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
    COALESCE(
      NULLIF(trim(new.raw_user_meta_data ->> 'name'), ''),
      split_part(COALESCE(new.email, 'Employee'), '@', 1)
    ),
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

REVOKE EXECUTE ON FUNCTION public.backfill_missing_auth_profiles()
  FROM PUBLIC, anon, authenticated;
