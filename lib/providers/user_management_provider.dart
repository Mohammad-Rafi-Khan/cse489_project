import 'package:flutter/foundation.dart';
import '../models/user_profile.dart';
import '../services/user_service.dart';

/// Manages organization users, role assignments, and branch attachments for Admins.
class UserManagementProvider extends ChangeNotifier {
  final UserService _userService = UserService();

  List<UserProfile> _users = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<UserProfile> get users => _users;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<UserCreationResult> createUser({
    required String name,
    required String email,
    required String password,
    required String role,
    String? branchId,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final result = await _userService.createUser(
        name: name,
        email: email,
        password: password,
        role: role,
        branchId: branchId,
      );
      await loadUsers();
      return result;
    } catch (e) {
      _errorMessage = _displayError(e);
      debugPrint('Create user error: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadUsers() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _users = await _userService.fetchAllUsers();
    } catch (e) {
      _errorMessage = 'Failed to load users.';
      debugPrint('Load users error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> updateUser({
    required String id,
    String? name,
    required String role,
    String? branchId,
    required bool isActive,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final updated = await _userService.updateUser(
        id: id,
        name: name,
        role: role,
        branchId: branchId,
        isActive: isActive,
      );
      _users = _users.map((u) => u.id == id ? updated : u).toList();
    } catch (e) {
      _errorMessage = _displayError(e);
      debugPrint('Update user error: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  String _displayError(Object error) {
    if (error is UserManagementException) {
      return error.message;
    }
    final raw = error.toString().trim();
    if (raw.startsWith('Exception: ')) {
      return raw.substring('Exception: '.length);
    }
    return raw.isEmpty ? 'User management request failed.' : raw;
  }
}
