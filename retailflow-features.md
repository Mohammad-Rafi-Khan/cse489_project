# RetailFlow — Feature Specification

A task, sales, and competition management platform for multi-branch retail operations. The system tracks employee task completion with photo verification, branch-level sales performance against targets, and inter-branch product competitions — while awarding individual employees points and badges based on their own work.

---

## 1. User & Role Management

The system supports three roles: **Employee**, **Manager**, and **Admin**. Each role has a different scope of access — employees interact with their own tasks and sales entries, managers oversee a branch, and admins operate across the whole organization.

**Capabilities:**
- Create, update, and deactivate user accounts (soft-delete via `isActive`, not hard delete, so historical records stay intact)
- Assign employees and managers to a specific branch
- Enforce role-based access control so, for example, an employee cannot approve their own task or create a competition

**Backing entities:** `USER` (with `role`, `branchId`, `isActive`)

---

## 2. Multi-Branch Management

RetailFlow is built for chains with multiple physical store locations, each operating semi-independently but reporting into the same system.

**Capabilities:**
- Create and manage branch records (name, location)
- Assign one manager per branch
- View the list of employees working at a given branch
- View branch status (active/inactive) and basic branch metadata

**Backing entities:** `BRANCH` (with `managerId` FK to `USER`), `USER.branchId`

---

## 3. Product Management

A shared product catalog used across sales entry and competitions.

**Capabilities:**
- Add and edit products, including name and category
- Set and update unit prices
- Activate or deactivate products (discontinued items stay in history but drop out of new entry forms)
- Reuse the same product records in both day-to-day sales entries and competitions

**Backing entities:** `PRODUCT`

---

## 4. Shift Management & Employee Scheduling

Branches operate in shifts (e.g., Morning, Evening, Night), and employees are scheduled into specific shifts on specific dates.

**Capabilities:**
- Define shift templates with start/end times (e.g., Morning: 8 AM–4 PM)
- Assign employees to a particular shift, at a particular branch, on a particular date
- View who is currently scheduled for a given shift
- Maintain a full history of past shift assignments for reporting

**Example:**
> Dhanmondi Branch – Morning Shift
> Rahim (Cashier), Nabila (Floor Staff), Sakib (Stock Staff)

**Backing entities:** `SHIFT` (templates), `SHIFT_ASSIGNMENT` (the actual employee-date-shift-branch booking)

---

## 5. Daily / Weekly / Monthly Checklist Management

Managers define recurring operational tasks that employees are expected to complete on a schedule.

**Examples:** daily shelf restocking, daily cleaning, weekly inventory checks, weekly equipment inspection, monthly stock audits.

**Each task template defines:**
- Title and description
- Frequency (daily, weekly, monthly)
- Points awarded on approval
- Deadline behavior
- Whether photo proof is required for approval

**Backing entities:** `TASK` (the recurring template — `frequency`, `basePoints`, `photoBonusPoints`, `photoRequired`)

---

## 6. Individual Task Assignment & History

Unlike sales (which are attributed to the branch/shift), tasks are **personal responsibilities** — each task assignment belongs to one specific employee, not the branch as a whole.

**Capabilities:**
- Assign a task to a specific employee
- Automatically generate recurring assignments from a task's frequency (e.g., a daily task spawns a new assignment each day)
- Set the scheduled date for each assignment
- Track each assignment's status: pending, completed, approved, or rejected
- View an employee's full task history over time

**Backing entities:** `TASK_ASSIGNMENT` (one row per employee per scheduled occurrence, generated from `TASK`)

---

## 7. Task Completion & Photo Proof Approval

The submission-and-approval workflow that turns a task assignment into awarded points.

**Employees can:**
- Mark an assigned task as complete
- Upload a photo as evidence, when the task requires it
- Submit the work for manager approval

**Managers can:**
- Approve a submission
- Reject a submission, with a required rejection reason
- Allow the employee to resubmit after a rejection

**Important:** points are awarded **only after approval** — a submitted-but-unreviewed or rejected completion earns nothing. Because resubmission is allowed, a single task assignment can accumulate multiple completion attempts over time (e.g., attempt 1 rejected for a blurry photo, attempt 2 approved) — the system keeps every attempt rather than overwriting the record, so managers can see the full submission history.

**Backing entities:** `TASK_COMPLETION` (one row per submission attempt, linked back to its `TASK_ASSIGNMENT`; `submittedBy` and `reviewedBy` are separate references to `USER`)

---

## 8. Branch/Shift Sales Target Management

Sales targets are set at the **branch + shift + date** level — not per employee.

**Example:**
> Dhanmondi Branch, Morning Shift, Target: ৳80,000
> Actual shift sales: ৳64,000 → Achievement: 80%

Employees do not receive individual personal sales targets; the target is a shared goal for whoever is working that shift.

**Backing entities:** `SALES_TARGET` (unique per `branchId` + `shiftId` + `targetDate`)

---

## 9. Branch/Shift Sales Entry

Sales are recorded against the **store**, not against the individual who happened to enter them.

**Each sales entry records:**
- Branch, shift, and product
- Quantity, unit price, and total amount
- Date of sale
- Who recorded the transaction (for accountability/audit, not attribution of credit)

**Example:**
> Rahim enters: Coca-Cola × 10 = ৳500
> Rahim is only the person who *recorded* the transaction — the sale itself belongs to Dhanmondi Branch → Morning Shift, not to Rahim personally.

**Backing entities:** `SALES_ENTRY` (`recordedBy` is an audit trail field, not a performance-attribution field)

---

## 10. Shift Sales Performance Tracking

The system automatically compares actual sales against the target for the same branch/shift/date.

**Example:**
> Target: ৳80,000 | Actual: ৳72,000 | Achievement: 90%

**Managers can compare:**
- Morning vs. Evening (or any shift vs. shift)
- Today's performance vs. past performance
- One branch's target achievement vs. another's

**Backing entities:** Computed from `SALES_ENTRY` (summed by branch/shift/date) against `SALES_TARGET` — this is a derived comparison, not a separately stored value.

---

## 11. Product-Based Branch Competition Management

Admins can run time-boxed competitions between branches, centered on specific products.

**Example:**
> "August Coca-Cola Challenge" — Aug 1 to Aug 31
> Competition product: Coca-Cola, worth 2 points per bottle sold
> Participating branches: Dhanmondi, Mirpur, Uttara, Banani

All sales from every employee/POS entry within a branch during the competition window count toward that branch's total — the competition is branch-vs-branch, not employee-vs-employee.

**Backing entities:** `COMPETITION` (dates, status), `COMPETITION_BRANCH` (which branches participate), `COMPETITION_PRODUCT` (which products qualify, and their point value per unit)

---

## 12. Branch Competition Leaderboard

Rankings are calculated **per branch**, aggregating every qualifying sale made by anyone at that branch during the competition window.

**Example:**

| Rank | Branch | Coca-Cola Sold | Competition Points |
|------|--------|-----------------|---------------------|
| 1 | Dhanmondi | 1,200 | 2,400 |
| 2 | Mirpur | 1,050 | 2,100 |
| 3 | Uttara | 900 | 1,800 |

**Formula:** `Competition Points = Qualifying Product Quantity × Points Per Unit`

This branch-level aggregation is intentional — it prevents the leaderboard from unfairly crediting all of a store's sales to whichever single cashier happened to record them.

**Backing entities:** `BRANCH_LEADERBOARD_ENTRY` — a materialized/cached result, recalculated from `SALES_ENTRY` joined against `COMPETITION_PRODUCT` and `COMPETITION_BRANCH`, filtered to the competition's date range. Stores current `rank` alongside `previousRank` so rank-change notifications (see Feature 14) can be triggered without a separate history table.

---

## 13. Individual Employee Points & Badge System

Separate from branch sales performance, each employee earns personal **Lifetime Points** from their own task work.

**Example point rules:**
- Daily task approved → +10 points
- Weekly task approved → +30 points
- Monthly task approved → +60 points
- Approved photo proof → +5 bonus points

**Example badge tiers:**

| Lifetime Points | Badge |
|------------------|-------|
| 0–499 | None |
| 500–1,499 | Bronze |
| 1,500–2,999 | Silver |
| 3,000+ | Gold |

**Important distinction:** branch sales performance (Features 9–12) does **not** feed into an individual employee's points. The two systems are deliberately separate — points reward personal task diligence, not store-wide sales results.

**Backing entities:** `POINTS_TRANSACTION` (one row per point-earning event, linked to the `TASK_COMPLETION` that triggered it), summed into `USER.totalLifetimePoints`; `BADGE` defines the tier thresholds, and `USER.currentBadgeId` is a cached pointer that should be recalculated any time `totalLifetimePoints` changes.

---

## 14. Notifications & Alerts

Employees and managers get notified of anything requiring their attention or worth celebrating.

**Trigger events:**
- New task assigned
- Task due soon
- Task approved / rejected
- New shift assigned
- Sales target reached
- Competition started / ended
- Branch rank changed
- Badge unlocked

Each notification supports **read/unread** status so users can track what they've already seen.

**Backing entities:** `NOTIFICATION` (per-user, with `type`, `isRead`). Rank-change and badge-unlock notifications rely on comparing current vs. previous state (`BRANCH_LEADERBOARD_ENTRY.previousRank`, and a similar before/after check on `USER.currentBadgeId`) — this comparison happens in application logic at the moment new data is written, not as a standalone schema feature.

---

## 15. Reports & Analytics

Role-scoped reporting, so each user type sees the data relevant to their responsibilities.

**Employee Reports**
- Task completion percentage
- Approved vs. rejected task counts
- Lifetime points total
- Progress toward the next badge
- Full task history

**Manager Reports**
- Branch sales (overall and by shift)
- Sales target achievement
- Employee task completion rates
- Pending task approvals awaiting review
- Product sales performance within the branch

**Admin Reports**
- Branch-vs-branch sales comparison
- Shift performance across the organization
- Product performance org-wide
- Competition leaderboards
- Top-performing branches
- Employee task performance and points/badge distribution

**Backing entities:** These are read-only aggregate views computed from `TASK_COMPLETION`, `SALES_ENTRY`, `POINTS_TRANSACTION`, and `BRANCH_LEADERBOARD_ENTRY` — no new entities required beyond what's already defined.
