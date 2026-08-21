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
      _errorMessage = 'Failed to update user profile.';
      debugPrint('Update user error: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
