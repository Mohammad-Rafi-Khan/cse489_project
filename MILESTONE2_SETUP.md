# RetailFlow — Milestone 2 Setup & Demo Guide

This build is scoped to:

1. Employee Registration
2. Login + role-based dashboards
3. Product Management
4. Task Assignment

## 1. Supabase database

Open your Supabase project, go to **SQL Editor**, paste the full contents of:

`supabase/setup.sql`

and run it.

It creates/seeds:

- `branches`
- `profiles`
- `products`
- `tasks`
- `task_assignments`
- RLS policies
- secure profile creation trigger for public registration
- Dhanmondi, Mirpur and Uttara demo branches
- sample products
- sample task templates

## 2. Authentication setting

For the fastest live classroom demo, you may disable email confirmation in the Supabase Auth email provider settings. Then a newly registered employee is signed in immediately.

If you leave email confirmation enabled, the app is also handled: it sends the user back to Login and asks them to confirm their email first.

## 3. Demo manager + employees

After running `setup.sql`:

1. Supabase Dashboard → Authentication → Users → Add user.
2. Create one manager and two employee auth users.
3. Copy their UUIDs.
4. At the bottom of `supabase/setup.sql`, use the provided UPSERT example and replace the UUID placeholders.
5. Put all three in the Dhanmondi branch for the simplest demo.
6. Set the Dhanmondi branch `manager_id` to the manager UUID using the provided UPDATE statement.

Public registration inside the Flutter app always creates an **employee** account.

## 4. Run Flutter

From the project root:

```bash
flutter pub get
flutter analyze
flutter run
```

If you use Android, the main Android manifest already contains Internet permission.

## 5. Demo sequence

### Registration

- Open Login → Create Account.
- Enter employee name/email/password.
- Select Dhanmondi Branch.
- Register.

### Login

- Login as Employee → Employee Dashboard.
- Logout.
- Login as Manager → Manager Dashboard.

### Product Management

As Manager:

- Product Management → Add Product.
- Add `Sprite`, category `Beverage`, price `45`.
- Edit it.
- Deactivate it.

Employees can view the product list but do not get editing controls, and database RLS also blocks product writes for employees.

### Task Assignment

As Manager:

- Assign Task.
- Select `Shelf Restocking`.
- Select an employee from the same branch.
- Pick date and due time.
- Assign.
- Open Assigned Tasks and show the new pending assignment.

Then logout and login as that employee:

- Open My Tasks.
- Show the same assignment with status `Pending`.

## 6. Important notes

- Supabase Auth stores passwords. RetailFlow does not store password hashes in `profiles`.
- Public users cannot register themselves as manager/admin.
- Managers can only assign tasks to active employees in their own branch.
- Task completion/photo proof is intentionally left for the next milestone.
- Sales, targets, competitions, leaderboard, points, badges, notifications and analytics are intentionally not implemented in Milestone 2.

## 7. Video code-base section

Briefly show these layers:

- `lib/models/` — data objects
- `lib/services/` — Supabase queries/auth calls
- `lib/providers/` — Provider state management
- `lib/screens/` — UI by role/feature
- `supabase/setup.sql` — database + RLS

Do not spend too long reading code line-by-line; show how one feature flows through Screen → Provider → Service → Supabase.
