import 'package:flutter/foundation.dart';
import '../models/issue_report.dart';
import '../services/issue_service.dart';

/// Manages issue report lifecycle for employee and manager workflows.
class IssueProvider extends ChangeNotifier {
  final IssueService _service = IssueService();

  List<IssueReport> _issues = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<IssueReport> get issues => _issues;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> loadMyIssues(String userId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _issues = await _service.fetchMyIssues(userId);
    } catch (e) {
      _errorMessage = 'Failed to load issues.';
      debugPrint('Load issues error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadBranchIssues(String branchId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _issues = await _service.fetchBranchIssues(branchId);
    } catch (e) {
      _errorMessage = 'Failed to load branch issues.';
      debugPrint('Load branch issues error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadCompanyIssues() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _issues = await _service.fetchCompanyIssues();
    } catch (e) {
      _errorMessage = 'Failed to load company issues.';
      debugPrint('Load company issues error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> createIssue({
    required String branchId,
    required String reportedBy,
    required String reporterName,
    required String reporterRole,
    required String title,
    required String description,
    required String priority,
  }) async {
    try {
      final issue = await _service.createIssue(
        branchId: branchId,
        reportedBy: reportedBy,
        reporterName: reporterName,
        reporterRole: reporterRole,
        title: title,
        description: description,
        priority: priority,
      );
      _issues = [issue, ..._issues];
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to create issue report.';
      debugPrint('Create issue error: $e');
      rethrow;
    }
  }


  Future<void> updateIssueStatus({
    required String id,
    required String status,
    String? resolutionNote,
  }) async {
    try {
      final issue = await _service.updateIssueStatus(
        id: id,
        status: status,
        resolutionNote: resolutionNote,
      );
      _issues = _issues.map((item) => item.id == id ? issue : item).toList();
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to update issue status.';
      debugPrint('Update issue status error: $e');
      rethrow;
    }
  }

  void clearAll() {
    _issues = [];
    _isLoading = false;
    _errorMessage = null;
    notifyListeners();
  }
}
