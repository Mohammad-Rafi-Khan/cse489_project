import 'package:flutter/foundation.dart';

import '../models/branch.dart';
import '../models/user_profile.dart';
import '../services/branch_service.dart';

/// Manages branches list and admin branch CRUD operations.
class BranchProvider extends ChangeNotifier {
  final BranchService _branchService = BranchService();

  List<Branch> _branches = [];
  List<UserProfile> _eligibleManagers = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<Branch> get branches => _branches;
  List<Branch> get activeBranches =>
      _branches.where((b) => b.isActive).toList();
  List<UserProfile> get eligibleManagers => _eligibleManagers;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> loadBranches() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _branches = await _branchService.fetchAllBranches();
    } catch (e) {
      _errorMessage = _displayError(e, fallback: 'Failed to load branches.');
      debugPrint('Load branches error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadEligibleManagers() async {
    try {
      _eligibleManagers = await _branchService.fetchEligibleManagers();
      notifyListeners();
    } catch (e) {
      _errorMessage = _displayError(
        e,
        fallback: 'Failed to load eligible managers.',
      );
      debugPrint('Load eligible managers error: $e');
      notifyListeners();
    }
  }

  Future<void> createBranch({
    required String name,
    String? location,
    String? managerId,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final branch = await _branchService.createBranch(
        name: name,
        location: location,
        managerId: managerId,
      );
      _branches = [branch, ..._branches];
      await loadEligibleManagers();
    } catch (e) {
      _errorMessage = _displayError(e, fallback: 'Failed to create branch.');
      debugPrint('Create branch error: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> updateBranch({
    required String id,
    required String name,
    String? location,
    String? managerId,
    required bool isActive,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final updated = await _branchService.updateBranch(
        id: id,
        name: name,
        location: location,
        managerId: managerId,
        isActive: isActive,
      );
      _branches = _branches.map((b) => b.id == id ? updated : b).toList();
      await loadEligibleManagers();
    } catch (e) {
      _errorMessage = _displayError(e, fallback: 'Failed to update branch.');
      debugPrint('Update branch error: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  String _displayError(Object error, {required String fallback}) {
    if (error is BranchManagementException) return error.message;
    final value = error.toString().trim();
    if (value.startsWith('Exception: ')) {
      return value.substring('Exception: '.length);
    }
    return value.isEmpty ? fallback : value;
  }
}
