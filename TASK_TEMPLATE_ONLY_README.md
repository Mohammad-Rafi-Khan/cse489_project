# Task Automation Removed

Removed:
- automatic recurring task generation
- cron/scheduler dependency
- run_task_template_automation
- recurring generation worker

Kept:
- Task Templates
- manual task creation
- task assignment
- completion
- photo proof
- approval
- points/badges
- notifications

After deploying, run:
supabase/remove_task_automation.sql

No task data is deleted.
