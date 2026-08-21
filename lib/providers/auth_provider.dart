import 'package:flutter/foundation.dart';
import '../models/user_profile.dart';
import '../models/branch.dart';
import '../services/auth_service.dart';

/// Manages authentication state, user profile, and role information.
class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();

  UserProfile? _profile;
  List<Branch> _branches = [];
  bool _isLoading = false;
  String? _errorMessage;

  // ─── Getters ──────────────────────────────────────────────

  UserProfile? get profile => _profile;
  List<Branch> get branches => _branches;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated => _profile != null;
  String? get role => _profile?.role;

  // ─── Startup: check session ────────────────────────────────

  /// Called at app startup to restore an existing session.
  Future<void> checkExistingSession() async {
    _setLoading(true);
    try {
      _profile = await _authService.getSessionProfile();
    } catch (e) {
      _profile = null;
      debugPrint('Session check error: $e');
    } finally {
      _setLoading(false);
    }
  }

  // ─── Registration ─────────────────────────────────────────

  Future<bool> register({
    required String name,
    required String email,
    required String password,
    required String branchId,
  }) async {
    _setLoading(true);
    _clearError();
    try {
      final result = await _authService.signUp(
        name: name,
        email: email,
        password: password,
        branchId: branchId,
      );
      _profile = result.profile;
      notifyListeners();
      return result.hasSession;
    } on Exception catch (e) {
      _errorMessage = _friendlyError(e.toString());
      notifyListeners();
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  // ─── Login ────────────────────────────────────────────────

  Future<void> login({
    required String email,
    required String password,
  }) async {
    _setLoading(true);
    _clearError();
    try {
      _profile = await _authService.signIn(
        email: email,
        password: password,
      );
      if (_profile != null && !_profile!.isActive) {
        await _authService.signOut();
        _profile = null;
        _errorMessage =
            'Your account has been deactivated. Please contact your manager.';
        notifyListeners();
        throw Exception(_errorMessage);
      }
      notifyListeners();
    } on Exception catch (e) {
      _errorMessage = _friendlyError(e.toString());
      notifyListeners();
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  // ─── Logout ───────────────────────────────────────────────

  Future<void> logout() async {
    await _authService.signOut();
    _profile = null;
    _branches = [];
    _clearError();
    notifyListeners();
  }

  // ─── Branches (for registration) ──────────────────────────

  Future<void> loadBranches() async {
    try {
      _branches = await _authService.fetchBranches();
      notifyListeners();
    } catch (e) {
      debugPrint('Load branches error: $e');
    }
  }

  /// Refreshes the current user's profile from Supabase (e.g., after points are awarded).
  Future<void> reloadProfile() async {
    try {
      final updated = await _authService.getSessionProfile();
      if (updated != null) {
        _profile = updated;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Reload profile error: $e');
    }
  }


  // ─── Helpers ──────────────────────────────────────────────

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void _clearError() {
    _errorMessage = null;
  }

  void clearError() {
    _clearError();
    notifyListeners();
  }

  /// Converts raw exception messages into user-friendly strings.
  String _friendlyError(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('invalid login credentials') ||
        lower.contains('invalid email or password')) {
      return 'Invalid email or password. Please try again.';
    }
    if (lower.contains('user already registered') ||
        lower.contains('already been registered')) {
      return 'An account with this email already exists.';
    }
    if (lower.contains('network') || lower.contains('socket')) {
      return 'Network error. Please check your internet connection.';
    }
    if (lower.contains('email not confirmed')) {
      return 'Please confirm your email before logging in.';
    }
    if (lower.contains('deactivated')) {
      return raw;
    }
    return 'Something went wrong. Please try again.';
  }
}
