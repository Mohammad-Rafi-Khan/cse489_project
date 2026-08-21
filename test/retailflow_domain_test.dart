import 'package:flutter_test/flutter_test.dart';
import 'package:cse489_project/models/user_profile.dart';
import 'package:cse489_project/models/task_assignment.dart';
import 'package:cse489_project/models/task_completion.dart';
import 'package:cse489_project/models/branch_leaderboard_entry.dart';
import 'package:cse489_project/models/competition_product.dart';
import 'package:cse489_project/models/app_notification.dart';

void main() {
  group('1. Points & Badge Progression Tests', () {
    test('User with 0 points has No Badge and progress towards Bronze (500 pts)', () {
      final user = UserProfile(
        id: 'u1',
        name: 'Rahim',
        email: 'rahim@test.com',
        role: 'employee',
        isActive: true,
        totalLifetimePoints: 0,
        createdAt: DateTime(2026, 1, 1),
      );

      expect(user.badgeTierName, equals('No Badge'));
      expect(user.nextBadgeThreshold, equals(500));
      expect(user.nextBadgeName, equals('Bronze'));
      expect(user.badgeProgress, equals(0.0));
    });

    test('User with 250 points has 50% progress towards Bronze', () {
      final user = UserProfile(
        id: 'u1',
        name: 'Rahim',
        email: 'rahim@test.com',
        role: 'employee',
        isActive: true,
        totalLifetimePoints: 250,
        createdAt: DateTime(2026, 1, 1),
      );

      expect(user.badgeTierName, equals('No Badge'));
      expect(user.badgeProgress, closeTo(0.5, 0.01));
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
      expect(user.nextBadgeThreshold, equals(1500));
      expect(user.nextBadgeName, equals('Silver'));
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

      expect(user.badgeTierName, equals('Bronze'));
      expect(user.badgeProgress, closeTo(0.5, 0.01));
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
      expect(user.nextBadgeThreshold, equals(3000));
      expect(user.nextBadgeName, equals('Gold'));
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
      expect(user.nextBadgeThreshold, equals(5000));
      expect(user.nextBadgeName, equals('Platinum'));
    });

    test('User with 5000+ points unlocks Platinum Badge (Max Tier)', () {
      final user = UserProfile(
        id: 'u1',
        name: 'Sakib',
        email: 'sakib@test.com',
        role: 'employee',
        isActive: true,
        totalLifetimePoints: 5200,
        createdAt: DateTime(2026, 1, 1),
      );

      expect(user.badgeTierName, equals('Platinum'));
      expect(user.badgeProgress, equals(1.0));
      expect(user.nextBadgeName, equals('Max Tier'));
    });
  });

  group('2. Task Multi-Attempt History & Completion Tests', () {
    test('Task assignment preserves multiple attempts with latest completion reference', () {
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
    });
  });

  group('3. Competition Leaderboard & Points Calculations', () {
    test('Competition points formula multiplies qualifying units by points per unit', () {
      final compProduct = CompetitionProduct(
        id: 'cp1',
        competitionId: 'comp1',
        productId: 'prod1',
        pointsPerUnit: 2, // e.g. 2 points per Coca-Cola
        productName: 'Coca-Cola',
      );

      const quantitySold = 1200;
      final totalPoints = quantitySold * compProduct.pointsPerUnit;

      expect(totalPoints, equals(2400));
    });

    test('BranchLeaderboardEntry accurately computes rank movement indicators', () {
      final climbedEntry = BranchLeaderboardEntry(
        id: 'le1',
        competitionId: 'c1',
        branchId: 'b1',
        totalQualifyingQty: 1200,
        totalCompetitionPoints: 2400,
        currentRank: 1,
        previousRank: 2,
        updatedAt: DateTime.now(),
        branchName: 'Dhanmondi Branch',
      );

      final droppedEntry = BranchLeaderboardEntry(
        id: 'le2',
        competitionId: 'c1',
        branchId: 'b2',
        totalQualifyingQty: 900,
        totalCompetitionPoints: 1800,
        currentRank: 3,
        previousRank: 2,
        updatedAt: DateTime.now(),
        branchName: 'Uttara Branch',
      );

      final sameEntry = BranchLeaderboardEntry(
        id: 'le3',
        competitionId: 'c1',
        branchId: 'b3',
        totalQualifyingQty: 1050,
        totalCompetitionPoints: 2100,
        currentRank: 2,
        previousRank: 2,
        updatedAt: DateTime.now(),
        branchName: 'Mirpur Branch',
      );

      expect(climbedEntry.rankMovement, equals(1)); // Climbed Up
      expect(droppedEntry.rankMovement, equals(-1)); // Dropped Down
      expect(sameEntry.rankMovement, equals(0)); // Unchanged
    });
  });

  group('4. Notification State Tests', () {
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
