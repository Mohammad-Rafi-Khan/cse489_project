# RetailFlow

RetailFlow is a Flutter and Supabase retail management app built for the CSE489 project. It supports branch operations, role-based dashboards, task tracking, attendance, leave approvals, issue reporting, product price management, sales imports, reports, points, badges, and notifications.

## Tech Stack

- Flutter
- Dart
- Supabase Auth
- Supabase Postgres
- Supabase Row Level Security
- Supabase Edge Functions
- Provider state management

## User Roles

RetailFlow has three application roles:

- Admin: manages branches, users, products, reports, sales imports, and organization-level operations.
- Manager: manages branch tasks, shifts, branch sales targets, branch attendance, leave approvals, and branch issues.
- Employee: views assigned work, checks in/out, submits task completions, reports issues, requests leave, and tracks points.

## Features

### Authentication And Role Access

- Email/password login with Supabase Auth.
- Employee registration flow.
- Persistent authenticated sessions.
- Role-based dashboard routing for admin, manager, and employee users.
- Route guards that restrict screens by role.
- Admin-only user creation through the `create-user` Supabase Edge Function.

### Admin Features

- Admin dashboard for organization-level controls and KPIs.
- Branch management for creating branches, editing branch details, assigning managers, and toggling branch status.
- User and role management for creating employees/managers/admins, assigning branches, and activating or deactivating users.
- Product price management for viewing products, creating products, editing active products, updating `current_price`, and reviewing price history.
- Admin-only CSV sales import for branch sales data.
- Sales target governance for setting branch and shift targets.
- Organization analytics and reports for branch revenue, product performance, staff counts, badges, and operational summaries.
- Issue report review across the company.
- Notification center for system workflow updates.

### Manager Features

- Manager dashboard for branch-level work, sales, staff, and issue summaries.
- Task assignment for assigning work to branch employees.
- Assigned task review for checking submitted task completions, approving work, rejecting work, and adding review notes.
- Manual task template management without automated recurring generation.
- Branch attendance view for today's attendance and historical attendance records.
- Shift management for branch shifts and employee schedules.
- Sales performance tracking for the manager's branch.
- Sales target management for the manager's branch.
- Branch reports for sales, tasks, points, and performance.
- Branch issue review and issue status updates.
- Leave approval workflow for approving or rejecting branch employee leave requests with manager comments.
- Product viewing and allowed product price updates.
- Notification center for branch workflow updates.

### Employee Features

- Employee dashboard with task, notification, issue, leave, and points summaries.
- My Tasks screen for viewing assigned tasks and submitting task completions.
- Task completion submission with notes and optional photo proof when required.
- My Schedule screen for viewing assigned shifts.
- Attendance check-in and check-out for the current day.
- Attendance history for the employee's own records.
- Request Leave flow for creating leave requests and tracking request status.
- Issue Reporting flow for reporting branch issues and viewing submitted reports.
- Points history for earned task points and achievement records.
- Badge progression based on lifetime points.
- Reports access for employee-visible performance information.
- Notification center for task reviews, leave decisions, issue updates, and other workflow messages.

### Product And Price Features

- Products use `products.current_price` as the only active price field.
- Admins and permitted managers can edit active products.
- Employees can view products but cannot edit them.
- Inactive products are protected from editing in the UI.
- Product price updates write to `products.current_price`.
- Product price changes are recorded in `product_price_history`.
- Price history stores `old_price`, `new_price`, `updated_by`, and `updated_at`.
- Price history is inserted only when the price actually changes.

### Task And Reward Features

- Manual task templates for reusable task definitions.
- Task assignment to branch employees.
- Employee task completion submissions.
- Multiple completion attempts are preserved.
- Manager/admin task review with approval or rejection.
- Fixed reward rules by task frequency.
- Photo bonus points when photo proof is required and submitted.
- Lifetime points tracking.
- Badge recalculation after approved task completions.
- Notifications for task approval and rejection.

### Attendance Features

- Employee check-in button.
- Employee check-out button.
- Employee-only attendance history.
- Automatic status of present or late based on assigned shift timing when available.
- Manager branch attendance view.
- Manager branch attendance history.
- Admin database access is controlled by RLS, while the admin dashboard attendance tile is hidden from the UI.

### Leave Management Features

- Employee leave request creation.
- Employee leave request history.
- Manager branch leave approval queue.
- Manager approve/reject actions.
- Manager comments on leave decisions.
- Admin all-leave visibility through role-scoped data access.
- Notifications for approved and rejected leave requests.

### Issue Reporting Features

- Employee, manager, and admin issue reporting screen access.
- Employee own issue history.
- Manager branch issue list.
- Admin company issue list.
- Issue priorities: low, medium, high, and critical.
- Issue statuses: open, in progress, resolved, and closed.
- Manager/admin issue status updates through an RPC.
- Reporter notifications when issue status changes.

### Sales And Reporting Features

- CSV upload for importing sales data.
- CSV validation before import.
- Duplicate batch reference protection.
- Branch/date/shift scoped sales imports.
- Optional product and quantity details in imported sales rows.
- Sales import failure logging.
- Branch sales target tracking.
- Shift-level sales target tracking.
- Sales performance comparison against targets.
- Reports for branch revenue, sales performance, products, staff, tasks, points, and badges.

### Notification Features

- Notification center screen.
- Unread notification count in dashboards.
- Task approval/rejection notifications.
- Leave approval/rejection notifications.
- Issue status update notifications.
- Sales import and target-related workflow notifications.

### Database And Security Features

- Supabase Row Level Security for role-scoped access.
- Security-definer helper functions for role and branch checks.
- Safe migration script for existing live databases.
- Full setup script for fresh databases.
- Product price history trigger.
- Attendance write guard trigger.
- Leave review RPC.
- Issue status update RPC.
- Admin user creation Edge Function using the service role key server-side only.

## Project Structure

```text
lib/
  config/        Supabase configuration
  models/        App data models
  providers/     Provider state classes
  screens/       Flutter UI screens by role/workflow
  services/      Supabase and business workflow services
  widgets/       Shared UI widgets

supabase/
  functions/     Supabase Edge Functions
  snippets/      Targeted SQL repair snippets
  setup.sql      Full database setup script
  final_retailflow_migration.sql

test/
  retailflow_domain_test.dart
  widget_test.dart
```

## Diagrams

These project documentation assets should stay in GitHub:

- [Schema Diagram](Schema%20Diagram/Schema%20Diagram.png)
- [Wireframe Diagram](Wireframe%20Diagram/)

## Setup

1. Install Flutter and confirm it is available:

```bash
flutter --version
```

2. Install dependencies:

```bash
flutter pub get
```

3. Configure Supabase in:

```text
lib/config/supabase_config.dart
```

Use the Supabase project URL and publishable/anon client key only. Do not put a service role key in the Flutter app.

4. Apply the database SQL in Supabase SQL Editor:

```text
supabase/setup.sql
```

For an existing live database, use:

```text
supabase/final_retailflow_migration.sql
```

5. Deploy the `create-user` Edge Function if admin-created users are needed:

```text
supabase/functions/create-user/index.ts
```

## Running The App

```bash
flutter run
```

## Tests

Run static analysis:

```bash
flutter analyze --no-pub
```

Run tests:

```bash
flutter test --no-pub --reporter compact
```

## CSV Sales Import Format

The sales import screen asks the admin to select the branch and sales date in the app. The CSV file should contain sales rows only.

Simple format:

```csv
batch_reference,total_amount
DHK-2026-08-30-001,125000
DHK-2026-08-30-002,80000
```

Full format:

```csv
batch_reference,total_amount,shift_name,product_name,quantity
DHK-2026-08-30-MORNING,125000,Morning,Coca-Cola,48
DHK-2026-08-30-EVENING,80000,Evening,Rice 5kg,12
```

Rules:

- `batch_reference` is required and should be unique.
- `total_amount` is required and must be a plain number.
- `shift_name` is optional but must match an existing shift when provided.
- `product_name` and `quantity` are optional, but if product data is used, both should be provided.
- `quantity` must be a positive whole number.

## Git Hygiene

Keep source code, SQL files, tests, schema diagrams, and wireframe diagrams in GitHub.

Do not commit local exports, temporary folders, generated files, logs, local CSV samples, build outputs, `node_modules`, or zip files.

The root `.gitignore` excludes:

- `New folder/`
- `*.zip`
- `branches.csv`
- Flutter build output
- Dart tooling output
- IDE folders
- logs
- `node_modules/`

## Notes

- The Flutter app must use the Supabase publishable/anon key, not the service role key.
- RLS policies are part of the database security model and should be kept in sync with app roles.
- Existing live databases should be updated with the migration script instead of rerunning the full setup script.
