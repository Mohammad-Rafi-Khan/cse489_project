# RetailFlow Task Template + Automation Fix

Scope: Task Template and automatic employee assignment only.

Verified flow:

Manager creates active task template
-> automation runs
-> task assignment is generated for selected employee
-> employee sees normal task
-> existing completion/approval/points workflow continues.

Required Supabase action:
1. Run `supabase/task_template_automation_patch.sql` in Supabase SQL Editor if it has not already been applied.
2. Ensure pg_cron is enabled if you want automatic daily generation.
3. Verify `retailflow-task-template-automation` cron job exists.

No changes were made to:
- task completion
- photo proof
- approval workflow
- points calculation
- badges
