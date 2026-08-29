# RetailFlow Admin Fix Package

The source code in this ZIP has been repaired for the hosted Supabase project configured in `lib/config/supabase_config.dart`.

## Required hosted step

Run:

`supabase/admin_remote_repair.sql`

in **Supabase Dashboard -> SQL Editor**.

For the best Manager/Employee creation flow, deploy:

`supabase/functions/create-user/index.ts`

as the hosted **create-user** function with **Verify JWT disabled** at the Edge Function gateway. The function performs its own Admin JWT verification.

See `supabase/DEPLOYMENT.md` for exact steps. No Docker/local Supabase is required.
