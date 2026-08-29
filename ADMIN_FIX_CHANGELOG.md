# RetailFlow Admin Fix Changelog

## Primary account-creation repair

- Hardened Admin -> Create Manager/Employee workflow.
- Keeps the signed-in Admin session intact.
- Uses the hosted `create-user` Edge Function first.
- Supports the project's `sb_publishable_...` key model by configuring the function with `verify_jwt = false` and validating the Admin access token inside the function.
- Reads the hosted `SUPABASE_SECRET_KEYS` default secret server-side, with legacy `SUPABASE_SERVICE_ROLE_KEY` fallback.
- Added a separate, non-persistent Supabase Auth client fallback when the hosted function is missing or blocked by legacy JWT gateway verification.
- Added validation for email, password, role, active branch, duplicate profile email, and Admin authorization.
- Added clearer errors and user-creation success state.

## Other Admin-side repairs

- Branch manager selection now only lists active Manager accounts, not Admin accounts.
- Branch `manager_id` and Manager `profiles.branch_id` are synchronized.
- Replacing a primary branch manager cleans up the previous primary manager's branch assignment when appropriate.
- Current Admin cannot demote or deactivate the account currently in use.
- All-shifts sales targets update existing rows instead of silently creating duplicate rows when `shift_id` is NULL.
- Added database uniqueness protection for all-shifts targets.
- Product pricing updates remove partial price history entries safely if a later write fails.
- Product, branch, user, and target forms surface more useful backend errors.
- Added hosted incremental SQL repair script: `supabase/admin_remote_repair.sql`.
- Updated Admin-related source tests for the repaired architecture.

## Hosted Supabase steps required

1. Run `supabase/admin_remote_repair.sql` in the hosted project's SQL Editor.
2. Deploy `supabase/functions/create-user/index.ts` as `create-user` with Verify JWT disabled.
3. Rebuild/restart the Flutter app and test Admin -> Create Manager/Employee.

No Docker, local Supabase, or offline business database is required.

## Validation performed in this environment

- Dart source delimiter/static structural scan: passed (0 unmatched delimiters).
- `create-user/index.ts` TypeScript transpile/syntax check: passed (0 syntax errors).
- Supabase Dart APIs introduced in the repair (`SupabaseClient`, `AuthClientOptions`, `isFilter`) were cross-checked against Supabase/Dart documentation.
- Full `flutter analyze` / `flutter test` could not be executed because Flutter and Dart executables are not installed in this sandbox.
