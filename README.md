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

- **Email/password login:** Users sign in with Supabase Auth and are routed into the app based on their saved profile role.
- **Employee registration:** New public registrations create employee accounts only, keeping manager and admin creation controlled.
- **Persistent sessions:** Supabase keeps users signed in between app launches until they log out.
- **Role-based dashboards:** Employees, managers, and admins each land on a dashboard designed for their workflow.
- **Route guards:** Protected screens check the current user's role before allowing access.
- **Admin-created users:** Admins create manager, employee, and admin accounts through the secure `create-user` Edge Function.

### Admin Features

- **Admin dashboard:** Shows organization-level controls, business KPIs, and shortcuts to admin modules.
- **Branch management:** Allows admins to create store branches, update branch details, assign branch managers, and activate or deactivate branches.
- **User and role management:** Allows admins to create users, assign roles, assign branches, and manage active or inactive staff accounts.
- **Product price management:** Allows admins to create products, edit active product details, update product prices, and review price change history.
- **CSV sales import:** Allows admins to upload branch sales data from CSV files with validation and duplicate controls.
- **Sales target governance:** Allows admins to set sales targets for branches and shifts so performance can be measured against goals.
- **Organization reports:** Shows company-level reports for revenue, products, branches, users, points, badges, and operations.
- **Company issue review:** Allows admins to view issue reports from all branches and monitor unresolved problems.
- **Notification center:** Gives admins a central place to view workflow notifications and system updates.

### Manager Features

- **Manager dashboard:** Shows branch-level task, sales, staff, issue, leave, and performance summaries.
- **Task assignment:** Allows managers to assign work to employees in their own branch.
- **Assigned task review:** Allows managers to review employee submissions, approve completed work, reject incomplete work, and add review notes.
- **Task template management:** Lets managers maintain reusable manual task definitions without automatic recurring task generation.
- **Branch attendance:** Lets managers view today's branch attendance and previous attendance history for branch employees.
- **Shift management:** Allows managers to create and manage shifts and employee schedules for their branch.
- **Sales performance:** Shows branch sales results and compares actual sales against targets.
- **Sales target management:** Allows managers to manage sales goals for their branch where permitted.
- **Branch reports:** Gives managers reports for branch sales, tasks, points, badges, and staff performance.
- **Branch issue review:** Lets managers view and update issue reports submitted for their own branch.
- **Leave approval:** Allows managers to approve or reject branch employee leave requests and add manager comments.
- **Product access:** Lets managers view products and update prices when their role permissions allow it.
- **Notification center:** Shows task, leave, issue, and sales workflow updates for the manager.

### Employee Features

- **Employee dashboard:** Shows personal task status, points, badge progress, notifications, leave, and issue shortcuts.
- **My Tasks:** Lists assigned tasks and lets employees open task details for completion.
- **Task completion submission:** Lets employees submit completion notes and photo proof when a task requires evidence.
- **My Schedule:** Shows the employee's assigned shifts and work schedule.
- **Attendance check-in/check-out:** Lets employees check in and check out for the current day only.
- **Attendance history:** Shows only the employee's own previous attendance records.
- **Leave requests:** Lets employees create leave requests and track whether each request is pending, approved, or rejected.
- **Issue reporting:** Lets employees report operational issues for their branch and track the status of their reports.
- **Points history:** Shows earned task points and the source of each points transaction.
- **Badge progression:** Shows the employee's current badge and progress toward the next badge tier.
- **Employee reports:** Gives employees access to role-appropriate performance and achievement information.
- **Notification center:** Shows updates for task reviews, leave decisions, issue status changes, and other workflow events.

### Product And Price Features

- **Current price field:** The app uses `products.current_price` as the single active product price column.
- **Product editing:** Admins and permitted managers can edit active products and update prices.
- **Employee read-only access:** Employees can view product information but cannot edit products or prices.
- **Inactive product protection:** Inactive products are shown as inactive and are blocked from normal edit actions.
- **Price update workflow:** Saving a product price update writes the new value to `products.current_price`.
- **Price history tracking:** Product price changes are logged in `product_price_history`.
- **Audit fields:** Price history stores the old price, new price, updater, and update time.
- **Change-only history:** A history row is created only when the old price and new price are different.

### Task And Reward Features

- **Manual task templates:** Managers create reusable task definitions for common branch work.
- **Task assignment:** Managers assign tasks to employees and track assignment status.
- **Completion submissions:** Employees submit completed tasks with notes and optional proof.
- **Multiple attempts:** Rejected or repeated submissions are preserved as task completion history.
- **Review workflow:** Managers or admins can approve or reject task completions.
- **Fixed reward rules:** Approved tasks award points based on task frequency rules.
- **Photo bonus:** Extra points can be awarded when photo proof is required and submitted.
- **Lifetime points:** Employee profiles store cumulative lifetime task points.
- **Badge recalculation:** Badge tiers update after approved task completions change lifetime points.
- **Task notifications:** Employees receive notifications when task submissions are approved or rejected.

### Attendance Features

- **Check-in button:** Employees can create today's attendance record with a check-in time.
- **Check-out button:** Employees can update today's attendance record with a check-out time after checking in.
- **Own history only:** Employees can view only their own attendance history.
- **Automatic status:** Attendance status is set to present or late using assigned shift timing when shift data exists.
- **Branch attendance view:** Managers can see attendance for employees in their own branch.
- **Branch attendance history:** Managers can review historical attendance records for their branch.
- **Admin UI hidden:** Admin attendance access remains controlled in the database, but the admin dashboard does not show the attendance overview tile.

### Leave Management Features

- **Leave request creation:** Employees can submit leave requests with date range and reason.
- **Leave request history:** Employees can view their own past and current leave requests.
- **Branch approval queue:** Managers can view pending leave requests from employees in their branch.
- **Approve/reject actions:** Managers can approve or reject pending leave requests.
- **Manager comments:** Managers can add a comment explaining the leave decision.
- **Admin visibility:** Admins can view leave data through role-scoped access rules.
- **Leave notifications:** Employees receive notifications when leave requests are approved or rejected.

### Issue Reporting Features

- **Issue reporting access:** Employees, managers, and admins can open the issue reporting screen according to route permissions.
- **Employee issue history:** Employees can view the issues they reported.
- **Manager branch issues:** Managers can view and manage issue reports for their assigned branch.
- **Admin company issues:** Admins can view issue reports across all branches.
- **Issue priorities:** Issues can be marked as low, medium, high, or critical.
- **Issue statuses:** Issues move through open, in progress, resolved, and closed states.
- **Status update RPC:** Manager/admin status updates are handled through a secure database RPC.
- **Reporter notifications:** The original reporter is notified when an issue status changes.

### Sales And Reporting Features

- **CSV upload:** Admins can import branch sales rows from a CSV file.
- **CSV validation:** The app validates required columns, numbers, shifts, products, and quantities before import.
- **Duplicate protection:** Batch references prevent the same sales import from being recorded more than once.
- **Scoped imports:** Sales imports are tied to the selected branch, selected date, and optional shift.
- **Product details:** CSV rows can include optional product name and quantity details for product-level reporting.
- **Failure logging:** Failed import attempts are recorded with error details for audit and troubleshooting.
- **Branch targets:** Sales targets can be stored for each branch.
- **Shift targets:** Sales targets can also be tracked at shift level.
- **Performance comparison:** Reports compare actual sales against target sales.
- **Reporting dashboard:** Reports summarize branch revenue, sales performance, product performance, staff, tasks, points, and badges.

### Notification Features

- **Notification center:** Users can view workflow notifications in one screen.
- **Unread count:** Dashboards show an unread notification badge.
- **Task notifications:** Employees are notified when submitted task work is approved or rejected.
- **Leave notifications:** Employees are notified when leave requests are approved or rejected.
- **Issue notifications:** Reporters are notified when their issue status changes.
- **Sales notifications:** Relevant users can receive updates from sales import and target workflows.

### Database And Security Features

- **Row Level Security:** Supabase RLS policies restrict data access by role, user, and branch.
- **Role helper functions:** Security-definer helpers safely read the current user's role and branch inside policies.
- **Safe migration:** `final_retailflow_migration.sql` upgrades existing databases without recreating live tables.
- **Fresh setup:** `setup.sql` creates the full database structure for a new project database.
- **Product price trigger:** A database trigger writes product price history when `current_price` changes.
- **Attendance write guard:** A trigger protects attendance records from employee edits to past or unrelated records.
- **Leave review RPC:** Leave approval and rejection happen through a controlled database function.
- **Issue status RPC:** Issue status changes happen through a controlled database function.
- **Secure admin user creation:** The service role key is used only inside the server-side Edge Function, never in the Flutter app.

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
