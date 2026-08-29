# RetailFlow hosted Supabase deployment

This project uses the hosted Supabase project directly. Docker and `supabase start` are **not** required.

Project ref: `eafefastkvyeufajjukv`

## 1. Apply the Admin repair SQL

Open the Supabase Dashboard for the project, then:

1. **SQL Editor** -> **New query**
2. Open `supabase/admin_remote_repair.sql` from this project.
3. Paste the whole file and click **Run**.

This patch is incremental and does not create the demo dataset from `setup.sql`.

## 2. Enable pg_cron for automatic daily absence checks

The app includes a daily absence job that inserts an `absent` attendance record for active employees who have no attendance entry once the daily cutoff passes.

For this to run, enable the `pg_cron` extension in the Supabase project dashboard and ensure the cron job can be scheduled.

> Without `pg_cron`, the daily `public.mark_absent_employees()` job will not execute, and no-shows will not be auto-marked absent.

## 3. Deploy the `create-user` Edge Function

The Flutter Admin screen prefers the hosted `create-user` Edge Function because it creates confirmed Manager/Employee Auth users without replacing the Admin session.

Use the source at:

`supabase/functions/create-user/index.ts`

For projects using `sb_publishable_...` keys, the function must run with legacy gateway JWT verification disabled. The function verifies the caller itself with `auth.getUser(accessToken)`.

The repository now includes:

```toml
[functions.create-user]
verify_jwt = false
```

### Dashboard-only route

In Supabase Dashboard:

1. Open **Edge Functions**.
2. Create or open the function named **create-user**.
3. Replace its source with `supabase/functions/create-user/index.ts`.
4. Disable the legacy **Verify JWT** gateway option for this function if the Dashboard shows that option.
5. Deploy.

Hosted Edge Functions receive Supabase project secret keys through their environment. Never put a secret/service-role key in Flutter.

### Optional remote CLI route (no Docker/local database needed)

```powershell
supabase login
supabase functions deploy create-user --project-ref eafefastkvyeufajjukv --no-verify-jwt
```

You do **not** need to run `supabase start`.

## 4. Why account creation failed

The app uses a new `sb_publishable_...` client key. Supabase documents that the legacy Edge Function gateway JWT verifier can reject requests in the new key model before the function receives them. The repaired function has `verify_jwt = false` at the gateway and verifies the signed-in Admin access token inside the function.

The Flutter code also contains an isolated sign-up fallback. It uses a separate non-persistent Supabase client, so it cannot replace the logged-in Admin session. If email confirmation is enabled, fallback-created accounts must confirm their email before first login.

## 5. Quick verification

After rebuilding the app:

1. Sign in as Admin.
2. Create an active branch if none exists.
3. User Management -> Create User -> Employee -> select branch -> create.
4. Create User -> Manager -> select branch -> create.
5. Confirm the Admin remains logged in.
6. Sign out and test the new Manager/Employee logins.
7. Verify Manager only sees their assigned branch.

## 6. Other Admin fixes included

- Manager assignment now keeps `profiles.branch_id` aligned with the selected branch.
- Admin accounts are no longer offered as branch managers.
- The current Admin cannot accidentally demote/deactivate their own account.
- Repeated all-shifts sales targets update instead of creating duplicate NULL-shift targets.
- Competition creation cleans up a partially created competition if a later insert fails.
- Admin error messages now expose actionable database/function failures rather than only generic errors.
