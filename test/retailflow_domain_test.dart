import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cse489_project/models/product.dart';
import 'package:cse489_project/models/shift.dart';
import 'package:cse489_project/models/user_profile.dart';
import 'package:cse489_project/models/points_transaction.dart';
import 'package:cse489_project/models/task_assignment.dart';
import 'package:cse489_project/models/task_completion.dart';
import 'package:cse489_project/models/app_notification.dart';
import 'package:cse489_project/models/issue_report.dart';
import 'package:cse489_project/models/leave_request.dart';
import 'package:cse489_project/models/sales_import_failure.dart';
import 'package:cse489_project/models/sales_import.dart';
import 'package:cse489_project/models/task.dart';
import 'package:cse489_project/models/badge.dart';
import 'package:cse489_project/services/csv_sales_import_parser.dart';
import 'package:cse489_project/services/points_service.dart';

String _readSource(String path) {
  return File(path).readAsStringSync().replaceAll('\r\n', '\n');
}

String _sourceSection(String source, String start, String end) {
  final startIndex = source.indexOf(start);
  expect(startIndex, isNonNegative);
  final endIndex = source.indexOf(end, startIndex + start.length);
  expect(endIndex, isNonNegative);
  return source.substring(startIndex, endIndex);
}

void main() {
  group('0. Product Price Compatibility Tests', () {
    test(
      'Product model reads current_price safely and defaults missing values',
      () {
        final modern = Product.fromMap({
          'id': 'p1',
          'name': 'Rice',
          'category': 'Groceries',
          'current_price': 125.5,
          'is_active': true,
          'created_at': '2026-08-30T00:00:00Z',
        });

        final missing = Product.fromMap({
          'id': 'p3',
          'name': 'Salt',
          'category': 'Groceries',
          'is_active': true,
          'created_at': '2026-08-30T00:00:00Z',
        });

        expect(modern.currentPrice, equals(125.5));
        expect(missing.currentPrice, equals(0.0));
      },
    );
  });

  group('1. Points & Badge Progression Tests', () {
    final badgeTiers = [
      const BadgeTier(
        id: 'bronze',
        name: 'Bronze',
        minPoints: 500,
        description: 'Bronze tier',
        iconName: 'workspace_premium',
      ),
      const BadgeTier(
        id: 'silver',
        name: 'Silver',
        minPoints: 1500,
        description: 'Silver tier',
        iconName: 'military_tech',
      ),
      const BadgeTier(
        id: 'gold',
        name: 'Gold',
        minPoints: 3000,
        description: 'Gold tier',
        iconName: 'stars',
      ),
    ];

    int nextTierThreshold(int points) {
      for (final tier in badgeTiers) {
        if (points < tier.minPoints) return tier.minPoints;
      }
      return badgeTiers.last.minPoints;
    }

    String nextTierName(int points) {
      for (final tier in badgeTiers) {
        if (points < tier.minPoints) return tier.name;
      }
      return 'Max Tier';
    }

    test(
      'User with 0 points has No Badge and progress towards the first tier',
      () {
        final user = UserProfile(
          id: 'u1',
          name: 'Rahim',
          email: 'rahim@test.com',
          role: 'employee',
          isActive: true,
          totalLifetimePoints: 0,
          createdAt: DateTime(2026, 1, 1),
        );

        final firstTier = badgeTiers.first;
        expect(user.badgeTierName, equals('No Badge'));
        expect(user.nextBadgeThreshold, equals(firstTier.minPoints));
        expect(user.nextBadgeName, equals(firstTier.name));
        expect(user.badgeProgress, equals(0.0));
      },
    );

    test('User with 250 points has 50% progress towards the first tier', () {
      final user = UserProfile(
        id: 'u1',
        name: 'Rahim',
        email: 'rahim@test.com',
        role: 'employee',
        isActive: true,
        totalLifetimePoints: 250,
        createdAt: DateTime(2026, 1, 1),
      );

      final firstTier = badgeTiers.first;
      expect(user.badgeTierName, equals('No Badge'));
      expect(user.badgeProgress, closeTo(250 / firstTier.minPoints, 0.01));
    });

    test('User with 500 points unlocks Bronze Badge', () {
      final user = UserProfile(
        id: 'u1',
        name: 'Rahim',
        email: 'rahim@test.com',
        role: 'employee',
        isActive: true,
        totalLifetimePoints: 500,
        createdAt: DateTime(2026, 1, 1),
      );

      expect(user.badgeTierName, equals('Bronze'));
      expect(user.nextBadgeThreshold, equals(nextTierThreshold(500)));
      expect(user.nextBadgeName, equals(nextTierName(500)));
      expect(user.badgeProgress, equals(0.0));
    });

    test('User with 1000 points has 50% progress from Bronze to Silver', () {
      final user = UserProfile(
        id: 'u1',
        name: 'Rahim',
        email: 'rahim@test.com',
        role: 'employee',
        isActive: true,
        totalLifetimePoints: 1000,
        createdAt: DateTime(2026, 1, 1),
      );

      final bronze = badgeTiers.first;
      final silver = badgeTiers[1];
      expect(user.badgeTierName, equals('Bronze'));
      expect(
        user.badgeProgress,
        closeTo(
          (1000 - bronze.minPoints) / (silver.minPoints - bronze.minPoints),
          0.01,
        ),
      );
    });

    test('User with 1500 points unlocks Silver Badge', () {
      final user = UserProfile(
        id: 'u1',
        name: 'Nabila',
        email: 'nabila@test.com',
        role: 'employee',
        isActive: true,
        totalLifetimePoints: 1500,
        createdAt: DateTime(2026, 1, 1),
      );

      expect(user.badgeTierName, equals('Silver'));
      expect(user.nextBadgeThreshold, equals(nextTierThreshold(1500)));
      expect(user.nextBadgeName, equals(nextTierName(1500)));
    });

    test('User with 3000 points unlocks Gold Badge', () {
      final user = UserProfile(
        id: 'u1',
        name: 'Sakib',
        email: 'sakib@test.com',
        role: 'employee',
        isActive: true,
        totalLifetimePoints: 3000,
        createdAt: DateTime(2026, 1, 1),
      );

      expect(user.badgeTierName, equals('Gold'));
      expect(user.nextBadgeThreshold, equals(nextTierThreshold(3000)));
      expect(user.nextBadgeName, equals(nextTierName(3000)));
      expect(user.badgeProgress, equals(1.0));
    });

    test('User with 5000+ points remains Gold Badge (Max Tier)', () {
      final user = UserProfile(
        id: 'u1',
        name: 'Sakib',
        email: 'sakib@test.com',
        role: 'employee',
        isActive: true,
        totalLifetimePoints: 5200,
        createdAt: DateTime(2026, 1, 1),
      );

      expect(user.badgeTierName, equals('Gold'));
      expect(user.badgeProgress, equals(1.0));
      expect(user.nextBadgeName, equals('Max Tier'));
    });
  });

  group('2. Issue Reporting & Leave Request Tests', () {
    test('Issue reports parse status and branch metadata correctly', () {
      final issue = IssueReport.fromMap({
        'id': 'i1',
        'branch_id': 'b1',
        'reported_by': 'u1',
        'title': 'Broken freezer door',
        'description': 'The freezer door is misaligned.',
        'status': 'open',
        'priority': 'high',
        'created_at': '2026-08-30T08:00:00Z',
        'updated_at': '2026-08-30T09:00:00Z',
        'resolved_at': null,
        'reported_by_profile': {'name': 'Rahim'},
        'branches': {'name': 'Downtown Branch'},
      });

      expect(issue.status, equals('open'));
      expect(issue.priority, equals('high'));
      expect(issue.branchName, equals('Downtown Branch'));
      expect(issue.reporterName, equals('Rahim'));
      expect(issue.isResolved, isFalse);
    });

    test('Leave requests parse employee and manager decisions correctly', () {
      final leave = LeaveRequest.fromMap({
        'id': 'l1',
        'branch_id': 'b1',
        'employee_id': 'u1',
        'start_date': '2026-09-01',
        'end_date': '2026-09-03',
        'reason': 'Medical appointment',
        'status': 'approved',
        'created_at': '2026-08-20T08:00:00Z',
        'updated_at': '2026-08-21T09:00:00Z',
        'manager_comment': 'Approved',
        'employee_profile': {'name': 'Rahim'},
        'branches': {'name': 'Downtown Branch'},
      });

      expect(leave.status, equals('approved'));
      expect(leave.employeeName, equals('Rahim'));
      expect(leave.branchName, equals('Downtown Branch'));
      expect(leave.durationDays, equals(3));
      expect(leave.isApproved, isTrue);
    });
  });

  group('3. Task Multi-Attempt History & Completion Tests', () {
    test('Task reward rules are fixed by frequency', () {
      final daily = Task(
        id: 'daily',
        title: 'Clean display',
        frequency: 'daily',
        branchId: 'b1',
        createdBy: 'm1',
        basePoints: 999,
        photoRequired: true,
        isActive: true,
        createdAt: DateTime(2026, 8, 24),
      );
      final weekly = Task(
        id: 'weekly',
        title: 'Audit shelf',
        frequency: 'weekly',
        branchId: 'b1',
        createdBy: 'm1',
        basePoints: 999,
        photoRequired: true,
        isActive: true,
        createdAt: DateTime(2026, 8, 24),
      );
      final monthly = Task(
        id: 'monthly',
        title: 'Stock inspection',
        frequency: 'monthly',
        branchId: 'b1',
        createdBy: 'm1',
        basePoints: 999,
        photoRequired: true,
        isActive: true,
        createdAt: DateTime(2026, 8, 24),
      );

      expect(daily.ruleBasePoints, equals(10));
      expect(weekly.ruleBasePoints, equals(30));
      expect(monthly.ruleBasePoints, equals(60));
      expect(daily.rulePhotoBonusPoints, equals(5));
    });

    test('Task template maps automation rule metadata', () {
      final template = Task.fromMap({
        'id': 't1',
        'title': 'Clean Display Shelf',
        'description': 'Clean and organize the front display.',
        'frequency': 'weekly',
        'branch_id': 'b1',
        'created_by': 'm1',
        'assigned_user_id': 'e1',
        'schedule_weekday': 5,
        'schedule_month_day': null,
        'last_generated_date': '2026-08-30',
        'last_generated_at': '2026-08-30T00:05:00Z',
        'base_points': 10,
        'photo_bonus_points': 5,
        'photo_required': true,
        'deadline_hours_after_assignment': 8,
        'is_active': true,
        'created_at': '2026-08-24T10:00:00Z',
        'assigned_employee': {
          'name': 'Rahim Ahmed',
          'email': 'rahim@retailflow.test',
        },
      });

      expect(template.assignedUserId, equals('e1'));
      expect(template.assignedEmployeeName, equals('Rahim Ahmed'));
      expect(template.scheduleWeekday, equals(5));
      expect(template.scheduleLabel, equals('Every Friday'));
      expect(template.lastGeneratedDate, equals(DateTime(2026, 8, 30)));
    });

    test('Task templates remain manual and automation-free', () {
      final sql = _readSource('supabase/setup.sql');

      expect(sql, contains('ADD COLUMN IF NOT EXISTS assigned_user_id'));
      expect(sql, contains('ADD COLUMN IF NOT EXISTS schedule_weekday'));
      expect(sql, contains('ADD COLUMN IF NOT EXISTS schedule_month_day'));
      expect(
        sql,
        isNot(
          contains(
            'CREATE OR REPLACE FUNCTION public.run_task_template_automation',
          ),
        ),
      );
      expect(sql, isNot(contains('generate_recurring_task_assignments')));
      expect(
        sql,
        isNot(contains("jobname = 'retailflow-task-template-automation'")),
      );
      expect(sql, isNot(contains('generated_from_template')));
      expect(sql, isNot(contains('last_generated_date = p_generation_date')));
    });

    test('Attendance and product price history schema are available', () {
      final sql = _readSource('supabase/setup.sql');

      expect(sql, contains('CREATE TABLE IF NOT EXISTS public.attendance'));
      expect(
        sql,
        contains(
          'employee_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE',
        ),
      );
      expect(sql, contains('attendance_date date NOT NULL'));
      expect(sql, contains('check_in_time timestamptz'));
      expect(sql, contains("status text NOT NULL DEFAULT 'present'"));
      expect(
        sql,
        contains('CREATE TABLE IF NOT EXISTS public.product_price_history'),
      );
      expect(sql, contains('old_price numeric(14,2) NOT NULL'));
      expect(sql, contains('new_price numeric(14,2) NOT NULL'));
      expect(
        sql,
        contains(
          'CREATE OR REPLACE FUNCTION public.log_product_price_change()',
        ),
      );
      expect(sql, contains('products_price_history_log'));
    });

    test(
      'Task assignment preserves multiple attempts with latest completion reference',
      () {
        final attempt1 = TaskCompletion(
          id: 'c1',
          assignmentId: 'a1',
          attemptNumber: 1,
          submittedBy: 'u1',
          submittedAt: DateTime(2026, 8, 20, 10, 0),
          completionNote: 'First attempt',
          photoUrl: 'https://example.com/photo1.jpg',
          reviewedBy: 'mgr1',
          reviewedAt: DateTime(2026, 8, 20, 12, 0),
          reviewNote: 'Photo was blurry. Please retake.',
          status: 'rejected',
        );

        final attempt2 = TaskCompletion(
          id: 'c2',
          assignmentId: 'a1',
          attemptNumber: 2,
          submittedBy: 'u1',
          submittedAt: DateTime(2026, 8, 21, 9, 0),
          completionNote: 'Retook clear photo',
          photoUrl: 'https://example.com/photo2.jpg',
          reviewedBy: 'mgr1',
          reviewedAt: DateTime(2026, 8, 21, 11, 0),
          reviewNote: 'Approved excellent work!',
          status: 'approved',
          pointsAwarded: 15,
        );

        final assignment = TaskAssignment(
          id: 'a1',
          taskId: 't1',
          userId: 'u1',
          scheduledDate: DateTime(2026, 8, 20),
          status: 'approved',
          assignedAt: DateTime(2026, 8, 19),
          taskTitle: 'Shelf Restocking',
          basePoints: 10,
          photoBonusPoints: 5,
          photoRequired: true,
          completions: [attempt2, attempt1], // sorted descending
          latestCompletion: attempt2,
        );

        expect(assignment.isApproved, isTrue);
        expect(assignment.completions.length, equals(2));
        expect(assignment.latestCompletion?.attemptNumber, equals(2));
        expect(assignment.latestCompletion?.status, equals('approved'));
        expect(assignment.completionNote, equals('Retook clear photo'));
        expect(assignment.reviewNote, equals('Approved excellent work!'));
      },
    );
  });

  group('3. Reward Flow Tests', () {
    test('Points transaction maps achievement history source metadata', () {
      final transaction = PointsTransaction.fromMap({
        'id': 'pt1',
        'user_id': 'u1',
        'task_completion_id': 'tc1',
        'points': 15,
        'base_points': 10,
        'bonus_points': 5,
        'awarded_at': '2026-08-30T08:30:00Z',
        'task_completions': {
          'completion_note': 'Shelf cleaned and front-facing completed.',
          'photo_url': 'https://example.com/proof.jpg',
          'task_assignments': {
            'tasks': {'title': 'Clean Display Shelf', 'frequency': 'daily'},
          },
        },
      });

      expect(
        transaction.sourceLabel,
        equals('Task approved: Clean Display Shelf'),
      );
      expect(transaction.detailLabel, contains('Base 10 pts'));
      expect(transaction.detailLabel, contains('Photo bonus 5 pts'));
      expect(transaction.detailLabel, contains('DAILY'));
      expect(transaction.hasPhotoProof, isTrue);
    });

    test('Points history screen is routed from the dashboard summary card', () {
      final main = _readSource('lib/main.dart');
      final dashboard = _readSource(
        'lib/screens/employee/employee_dashboard.dart',
      );
      final screen = _readSource(
        'lib/screens/employee/points_history_screen.dart',
      );
      final provider = _readSource('lib/providers/points_provider.dart');
      final service = _readSource('lib/services/points_service.dart');

      expect(
        main,
        contains("ChangeNotifierProvider(create: (_) => PointsProvider())"),
      );
      expect(main, contains("'/points-history'"));
      expect(main, contains("requiredRoles: {'employee', 'manager', 'admin'}"));
      expect(
        dashboard,
        contains(
          "Navigator.pushNamed(\n                              context,\n                              '/points-history'",
        ),
      );
      expect(screen, contains('Achievement History'));
      expect(screen, contains('runningTotal'));
      expect(
        provider,
        contains('PointsService _pointsService = PointsService()'),
      );
      expect(provider, contains('loadUserTransactions'));
      expect(service, contains('fetchUserTransactions(String userId)'));
      expect(service, contains('.from(\'points_transactions\')'));
      expect(
        service,
        contains(
          'task_completions(completion_note, photo_url, task_assignments(tasks(title, frequency)))',
        ),
      );
    });

    test('PointsService owns fixed reward calculation rules', () {
      final daily = PointsService.calculateTaskAward(
        frequency: 'daily',
        hasPhotoProof: false,
      );
      final weeklyWithPhoto = PointsService.calculateTaskAward(
        frequency: 'weekly',
        hasPhotoProof: true,
      );
      final monthlyWithPhoto = PointsService.calculateTaskAward(
        frequency: 'monthly',
        hasPhotoProof: true,
      );

      expect(daily.basePoints, equals(10));
      expect(daily.bonusPoints, equals(0));
      expect(daily.totalPoints, equals(10));
      expect(weeklyWithPhoto.totalPoints, equals(35));
      expect(monthlyWithPhoto.totalPoints, equals(65));
    });

    test('Approval SQL keeps reward side effects ordered and idempotent', () {
      final sql = _readSource('supabase/setup.sql');
      final approvalBody = _sourceSection(
        sql,
        'CREATE OR REPLACE FUNCTION public.approve_task_completion(\n'
            '  p_completion_id uuid,\n'
            '  p_reviewer_id',
        'CREATE TABLE IF NOT EXISTS public.sales_targets',
      );

      final completionUpdate = approvalBody.indexOf(
        'UPDATE public.task_completions',
      );
      final pointsInsert = approvalBody.indexOf(
        'INSERT INTO public.points_transactions',
      );
      final profileUpdate = approvalBody.indexOf('UPDATE public.profiles');
      final badgeRecalc = approvalBody.indexOf(
        'PERFORM public.recalculate_user_badge',
      );
      final approvedNotification = approvalBody.indexOf("'task_approved'");

      expect(sql, contains('CONSTRAINT uq_points_task_completion UNIQUE'));
      expect(
        approvalBody,
        contains('ON CONFLICT (task_completion_id) DO NOTHING'),
      );
      expect(completionUpdate, isNonNegative);
      expect(pointsInsert, greaterThan(completionUpdate));
      expect(profileUpdate, greaterThan(pointsInsert));
      expect(badgeRecalc, greaterThan(profileUpdate));
      expect(approvedNotification, greaterThan(badgeRecalc));
    });
  });

  group('5. Imported Sales Data Tests', () {
    test('SalesImport maps external sales source metadata correctly', () {
      final imported = SalesImport.fromMap({
        'id': 'si1',
        'branch_id': 'b1',
        'shift_id': null,
        'sale_date': '2026-08-24',
        'source': 'csv_upload',
        'sales_source': 'csv_upload',
        'total_amount': 800000,
        'imported_by': 'manager1',
        'imported_at': '2026-08-24T10:00:00Z',
        'external_reference': 'CSV-DHK-20260824',
        'branches': {'name': 'Dhaka'},
        'profiles': {'name': 'Dhaka Manager'},
      });

      expect(imported.branchName, equals('Dhaka'));
      expect(imported.source, equals('csv_upload'));
      expect(imported.salesSource, equals('csv_upload'));
      expect(imported.totalAmount, equals(800000));
      expect(imported.externalReference, equals('CSV-DHK-20260824'));
    });

    test('SalesImportFailure maps rejected CSV import attempts', () {
      final failure = SalesImportFailure.fromMap({
        'id': 'f1',
        'branch_id': 'b1',
        'sale_date': '2026-08-24',
        'source': 'csv_upload',
        'sales_source': 'csv_upload',
        'error_message': 'Duplicate CSV import',
        'attempted_by': 'manager1',
        'attempted_at': '2026-08-24T10:05:00Z',
        'profiles': {'name': 'Dhaka Manager'},
      });

      expect(failure.source, equals('csv_upload'));
      expect(failure.salesSource, equals('csv_upload'));
      expect(failure.errorMessage, contains('Duplicate'));
      expect(failure.attemptedByName, equals('Dhaka Manager'));
    });

    test('CSV parser accepts required branch sales columns only', () {
      final result = CsvSalesImportParser().parse(
        'batch_reference,total_amount\n'
        'CSV-DHK-001,120000\n'
        'CSV-DHK-002,0',
      );

      expect(result.totalRows, equals(2));
      expect(result.validRows.length, equals(2));
      expect(result.failedRows, isEmpty);
      expect(result.validRows.first.reference, equals('CSV-DHK-001'));
      expect(result.validRows.first.totalAmount, equals(120000));
      expect(result.validRows.first.shift, isNull);
      expect(result.validRows.first.product, isNull);
    });

    test(
      'CSV parser validates optional shift and product data when present',
      () {
        final shift = Shift(
          id: 's1',
          branchId: 'b1',
          name: 'Morning',
          startTime: '09:00:00',
          endTime: '15:00:00',
          isActive: true,
          createdAt: DateTime(2026, 8, 24),
        );
        final product = Product(
          id: 'p1',
          name: 'Coca-Cola',
          category: 'Beverage',
          isActive: true,
          createdAt: DateTime(2026, 8, 24),
        );

        final result = CsvSalesImportParser().parse(
          'batch_reference,total_amount,shift_name,product_name,quantity\n'
          'CSV-DHK-003,125000,Morning,Coca-Cola,48\n'
          'CSV-DHK-004,80000,Night,Coca-Cola,24',
          shiftsByName: {'Morning': shift},
          productsByName: {'Coca-Cola': product},
        );

        expect(result.totalRows, equals(2));
        expect(result.validRows.length, equals(1));
        expect(result.validRows.single.shift?.name, equals('Morning'));
        expect(result.validRows.single.product?.name, equals('Coca-Cola'));
        expect(result.validRows.single.quantity, equals(48));
        expect(result.failedRows.single.reason, contains('Shift "Night"'));
      },
    );

    test('Sales import SQL enforces duplicate batch references', () {
      final sql = _readSource('supabase/setup.sql');

      expect(sql, contains('external_reference text NOT NULL'));
      expect(sql, contains('sales_imports_external_reference_not_blank'));
      expect(sql, contains('idx_sales_imports_batch_reference_unique'));
      expect(
        sql,
        contains(
          "COALESCE(shift_id, '00000000-0000-0000-0000-000000000000'::uuid)",
        ),
      );
      expect(
        sql,
        contains(
          'Duplicate CSV import for this branch, shift, date, and batch reference',
        ),
      );
    });
  });

  group('6. Permission Boundary Tests', () {
    test('Flutter uses the hosted Supabase project and client key only', () {
      final config = _readSource('lib/config/supabase_config.dart');
      final main = _readSource('lib/main.dart');

      expect(config, contains('https://eafefastkvyeufajjukv.supabase.co'));
      expect(
        config,
        contains('sb_publishable_zaD-1UM4FZSc7BKCYUoXww_WST6HOTN'),
      );
      expect(main, contains('publishableKey: SupabaseConfig.anonKey'));
      expect(config, isNot(contains('SERVICE_ROLE')));
      expect(config, isNot(contains('127.0.0.1')));
      expect(config, isNot(contains('localhost')));
    });

    test('Public registration can load active branches before sign-in', () {
      final sql = _readSource('supabase/setup.sql');
      final migration = _readSource('supabase/final_retailflow_migration.sql');
      final provider = _readSource('lib/providers/auth_provider.dart');
      final screen = _readSource('lib/screens/auth/registration_screen.dart');

      for (final source in [sql, migration]) {
        expect(source, contains('GRANT SELECT ON public.branches TO anon'));
        expect(
          source,
          contains('CREATE POLICY "branches_select_active_public"'),
        );
        expect(source, contains('TO anon, authenticated'));
        expect(source, contains('USING (is_active)'));
        expect(source, contains('CREATE POLICY "branches_select_admin"'));
      }
      expect(provider, contains('bool _isLoadingBranches = false;'));
      expect(provider, contains('String? _branchLoadError;'));
      expect(provider, contains('_friendlyBranchLoadError'));
      expect(screen, contains('Retry branch load'));
    });

    test('Sales import route and RPC are admin-only', () {
      final sql = _readSource('supabase/setup.sql');
      final main = _readSource('lib/main.dart');
      final importRoute = _sourceSection(
        main,
        "'/sales-import'",
        "'/product-form'",
      );

      expect(
        sql,
        contains("IF caller_id IS NULL OR caller_role <> 'admin' THEN"),
      );
      expect(importRoute, contains("requiredRoles: {'admin'}"));
      expect(main, isNot(contains('/sales-entry')));
    });

    test('RLS role helpers are SECURITY DEFINER functions', () {
      final sql = _readSource('supabase/setup.sql');
      final roleFunction = _sourceSection(
        sql,
        'CREATE OR REPLACE FUNCTION public.get_my_role()',
        'CREATE OR REPLACE FUNCTION public.get_my_branch_id()',
      );
      final branchFunction = _sourceSection(
        sql,
        'CREATE OR REPLACE FUNCTION public.get_my_branch_id()',
        'CREATE OR REPLACE FUNCTION public.retailflow_current_date()',
      );
      final businessDateFunction = _sourceSection(
        sql,
        'CREATE OR REPLACE FUNCTION public.retailflow_current_date()',
        'CREATE OR REPLACE FUNCTION public.handle_new_retailflow_user()',
      );

      expect(
        roleFunction,
        contains('SECURITY DEFINER SET search_path = public'),
      );
      expect(
        branchFunction,
        contains('SECURITY DEFINER SET search_path = public'),
      );
      expect(
        roleFunction,
        contains('WHERE id = auth.uid() AND is_active = true'),
      );
      expect(
        branchFunction,
        contains('WHERE id = auth.uid() AND is_active = true'),
      );
      expect(
        businessDateFunction,
        contains("SELECT (now() AT TIME ZONE 'Asia/Dhaka')::date"),
      );
    });

    test('Attendance, product, and leave policies use final role boundaries', () {
      final sql = _readSource('supabase/setup.sql');
      final migration = _readSource('supabase/final_retailflow_migration.sql');

      expect(sql, contains('CREATE POLICY "attendance_select_own"'));
      expect(sql, contains('CREATE POLICY "attendance_select_branch"'));
      expect(sql, contains('CREATE POLICY "attendance_select_admin"'));
      expect(
        sql,
        contains('CREATE POLICY "attendance_employee_checkout_today"'),
      );
      expect(
        sql,
        contains('attendance_date = public.retailflow_current_date()'),
      );
      expect(sql, contains('CREATE POLICY "products_select_auth"'));
      expect(sql, contains('CREATE POLICY "products_update_manager_admin"'));
      expect(
        sql,
        contains('CREATE POLICY "leave_requests_insert_employee_own"'),
      );
      expect(
        sql,
        contains('ALTER TABLE public.issue_reports ENABLE ROW LEVEL SECURITY'),
      );
      expect(
        sql,
        contains(
          'GRANT SELECT, INSERT, UPDATE ON public.issue_reports TO authenticated',
        ),
      );
      expect(
        migration,
        contains(
          'GRANT SELECT, INSERT, UPDATE ON public.issue_reports TO authenticated',
        ),
      );
      expect(
        migration,
        contains(
          "table_name IN ('attendance', 'issue_reports', 'leave_requests'",
        ),
      );
      expect(sql, contains('CREATE POLICY "issue_reports_select_branch"'));
      expect(sql, contains('CREATE POLICY "issue_reports_select_admin"'));
      expect(sql, contains('REVOKE UPDATE, DELETE ON public.leave_requests'));
      expect(sql, isNot(contains('CREATE POLICY "leave_requests_update"')));
      expect(
        sql,
        isNot(contains('NEW.attendance_date IS DISTINCT FROM CURRENT_DATE')),
      );
      expect(sql, isNot(contains('USING (true)')));
    });

    test('Managers can view only branch-scoped sales analytics', () {
      final sql = _readSource('supabase/setup.sql');
      final salesImportPolicy = _sourceSection(
        sql,
        'CREATE POLICY "sales_imports_select_scoped"',
        'DROP POLICY IF EXISTS "sales_import_items_select"',
      );

      expect(
        sql,
        contains(
          "public.get_my_role() = 'admin'\n"
          "  OR (public.get_my_role() = 'manager' AND branch_id = public.get_my_branch_id())",
        ),
      );
      expect(
        sql,
        contains(
          "public.get_my_role() = 'admin'\n"
          "     OR (public.get_my_role() = 'manager' AND public.get_my_branch_id() = p_branch_id)",
        ),
      );
      expect(salesImportPolicy, contains("public.get_my_role() = 'admin'"));
      expect(
        salesImportPolicy,
        contains(
          "public.get_my_role() = 'manager' AND branch_id = public.get_my_branch_id()",
        ),
      );
      expect(salesImportPolicy, isNot(contains("'employee'")));
    });

    test('Admin-created users go through create-user, not client signUp', () {
      final service = _readSource('lib/services/user_service.dart');
      final screen = _readSource(
        'lib/screens/admin/user_management_screen.dart',
      );
      final function = _readSource('supabase/functions/create-user/index.ts');

      expect(service, contains("'create-user'"));
      expect(
        service,
        contains(r"headers: {'Authorization': 'Bearer $accessToken'}"),
      );
      expect(service, contains('_supabase.auth.currentSession'));
      expect(service, isNot(contains('_supabase.auth.signUp')));
      expect(service, contains('_createViaIsolatedSignup'));
      expect(service, contains('final signupClient = SupabaseClient('));
      expect(service, contains('signupClient.auth.signUp'));
      expect(service, contains('role: normalizedRole'));
      expect(
        service,
        contains(
          "branchId: normalizedRole == 'admin' ? null : normalizedBranchId",
        ),
      );
      expect(service, contains('on FunctionException catch'));
      expect(
        screen,
        contains('Temporary password must be at least 8 characters.'),
      );
      expect(screen, contains('errorMessage ??'));
      expect(function, contains('adminClient.auth.admin.createUser'));
      expect(function, contains('SUPABASE_SERVICE_ROLE_KEY'));
    });

    test(
      'Admin create form passes branch UUIDs for manager and employee users',
      () {
        final screen = _readSource(
          'lib/screens/admin/user_management_screen.dart',
        );

        expect(screen, contains("String _role = 'employee';"));
        expect(screen, contains("if (_role != 'admin' && _branchId == null)"));
        expect(
          screen,
          contains("_showError('Select a branch for this user.');"),
        );
        expect(
          screen,
          contains('context.watch<BranchProvider>().activeBranches'),
        );
        expect(screen, contains('DropdownMenuItem(value: b.id'));
        expect(screen, contains("if (_role == 'admin') _branchId = null"));
      },
    );

    test('create-user rejects non-admin and inactive callers', () {
      final function = _readSource('supabase/functions/create-user/index.ts');

      expect(function, contains('adminClient.auth.getUser(accessToken)'));
      expect(function, contains('.select("role, is_active")'));
      expect(function, contains('maybeSingle()'));
      expect(function, contains('!callerProfile.is_active'));
      expect(function, contains('callerProfile.role !== "admin"'));
      expect(function, contains('but only admins can create users.'));
    });

    test(
      'create-user validates role, password, and active branch server-side',
      () {
        final service = _readSource('lib/services/user_service.dart');
        final function = _readSource('supabase/functions/create-user/index.ts');

        expect(
          service,
          contains("{'employee', 'manager', 'admin'}.contains(role)"),
        );
        expect(
          service,
          contains('A branch is required for employees and managers.'),
        );
        expect(function, contains('password.length < 8'));
        expect(
          function,
          contains('!["employee", "manager", "admin"].includes(role)'),
        );
        expect(function, contains('A branch is required for this role'));
        expect(function, contains('.eq("is_active", true)'));
        expect(function, contains('Selected branch is inactive or missing'));
      },
    );

    test('create-user persists manager and employee role/branch profiles', () {
      final function = _readSource('supabase/functions/create-user/index.ts');

      expect(function, contains('user_metadata: {'));
      expect(function, contains('.upsert('));
      expect(function, contains("branch_id: branchId"));
      expect(function, contains('role === "manager" && branchId'));
      expect(function, contains('.update({ manager_id: data.user.id })'));
      expect(function, contains('branch_manager_assigned'));
    });

    test(
      'create-user handles duplicate email and rolls back partial failures',
      () {
        final function = _readSource('supabase/functions/create-user/index.ts');

        expect(function, contains('adminClient.auth.admin.createUser'));
        expect(function, contains('profileUpsertError'));
        expect(function, contains('branchUpdateError'));
        expect(
          function,
          contains('adminClient.auth.admin.deleteUser(data.user.id)'),
        );
        expect(
          function
              .split('adminClient.auth.admin.deleteUser(data.user.id)')
              .length,
          greaterThanOrEqualTo(3),
        );
      },
    );

    test(
      'SQL trigger and backfill create deterministic employee-first profiles',
      () {
        final sql = _readSource('supabase/setup.sql');
        final trigger = _sourceSection(
          sql,
          'CREATE OR REPLACE FUNCTION public.handle_new_retailflow_user()',
          'DROP TRIGGER IF EXISTS on_auth_user_created_retailflow',
        );
        final backfill = _sourceSection(
          sql,
          'CREATE OR REPLACE FUNCTION public.backfill_missing_auth_profiles()',
          'REVOKE EXECUTE ON FUNCTION public.backfill_missing_auth_profiles()',
        );

        expect(
          trigger,
          contains('WHERE id = selected_branch AND is_active = true'),
        );
        expect(
          trigger,
          contains("COALESCE(new.email, ''), 'employee', selected_branch"),
        );
        expect(trigger, isNot(contains("raw_user_meta_data ->> 'role'")));
        expect(backfill, contains("ELSE 'employee'"));
        expect(backfill, isNot(contains("raw_user_meta_data ->> 'role'")));
      },
    );

    test('New manager and employee logins route to role dashboards', () {
      final main = _readSource('lib/main.dart');
      final login = _readSource('lib/screens/auth/login_screen.dart');

      for (final source in [main, login]) {
        expect(source, contains("case 'manager':"));
        expect(source, contains("'/manager-dashboard'"));
        expect(source, contains("case 'admin':"));
        expect(source, contains("'/admin-dashboard'"));
        expect(source, contains("'/employee-dashboard'"));
      }
    });
  });

  test(
    'Hosted create-user function uses explicit auth verification for publishable keys',
    () {
      final config = _readSource('supabase/config.toml');
      final function = _readSource('supabase/functions/create-user/index.ts');

      expect(config, contains('[functions.create-user]'));
      expect(config, contains('verify_jwt = false'));
      expect(function, contains('adminClient.auth.getUser(accessToken)'));
      expect(function, contains('SUPABASE_SECRET_KEYS'));
      expect(function, contains('SUPABASE_SERVICE_ROLE_KEY'));
    },
  );

  test('Admin branch assignment keeps manager profile branch in sync', () {
    final service = _readSource('lib/services/branch_service.dart');

    expect(service, contains(".eq('role', 'manager')"));
    expect(service, isNot(contains(".inFilter('role', ['manager', 'admin'])")));
    expect(service, contains("'branch_id': branchId"));
    expect(service, contains("'manager_id': null"));
  });

  test('All-shifts sales targets are idempotent and SQL-protected', () {
    final service = _readSource('lib/services/sales_service.dart');
    final sql = _readSource('supabase/setup.sql');

    expect(service, contains(".isFilter('shift_id', null)"));
    expect(service, contains(".update({"));
    expect(sql, contains('idx_sales_targets_no_shift_unique'));
    expect(sql, contains('WHERE shift_id IS NULL'));
  });

  group('7. Notification State Tests', () {
    test('AppNotification reflects unread and read status correctly', () {
      final notif = AppNotification(
        id: 'n1',
        userId: 'u1',
        type: 'task_approved',
        title: 'Task Approved! +15 pts',
        message: 'Your task was approved by your manager.',
        isRead: false,
        createdAt: DateTime(2026, 8, 22),
      );

      expect(notif.isRead, isFalse);
      expect(notif.type, equals('task_approved'));
    });
  });
}
