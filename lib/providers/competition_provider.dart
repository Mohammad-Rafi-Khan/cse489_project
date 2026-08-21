import 'package:flutter/foundation.dart';
import '../models/competition.dart';
import '../services/competition_service.dart';

/// Manages competition lists, creation, status transitions, and leaderboard calculations.
class CompetitionProvider extends ChangeNotifier {
  final CompetitionService _competitionService = CompetitionService();

  List<Competition> _competitions = [];
  Competition? _selectedCompetition;
  bool _isLoading = false;
  String? _errorMessage;

  List<Competition> get competitions => _competitions;
  List<Competition> get activeCompetitions => _competitions.where((c) => c.isActive && c.status == 'active').toList();
  Competition? get selectedCompetition => _selectedCompetition;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> loadCompetitions() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _competitions = await _competitionService.fetchCompetitions();
    } catch (e) {
      _errorMessage = 'Failed to load competitions.';
      debugPrint('Load competitions error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadCompetitionDetail(String competitionId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _selectedCompetition = await _competitionService.fetchCompetitionDetail(competitionId);
    } catch (e) {
      _errorMessage = 'Failed to load competition details.';
      debugPrint('Load competition detail error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> createCompetition({
    required String title,
    String? description,
    required DateTime startDate,
    required DateTime endDate,
    required List<String> branchIds,
    required List<Map<String, dynamic>> products,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final comp = await _competitionService.createCompetition(
        title: title,
        description: description,
        startDate: startDate,
        endDate: endDate,
        branchIds: branchIds,
        products: products,
      );
      _competitions = [comp, ..._competitions];
    } catch (e) {
      _errorMessage = 'Failed to create competition.';
      debugPrint('Create competition error: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> recalculateLeaderboard(String competitionId) async {
    try {
      await _competitionService.recalculateLeaderboard(competitionId);
      await loadCompetitionDetail(competitionId);
    } catch (e) {
      debugPrint('Recalculate leaderboard error: $e');
    }
  }

  Future<void> updateStatus({
    required String id,
    required String status,
    required bool isActive,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _competitionService.updateCompetitionStatus(
        id: id,
        status: status,
        isActive: isActive,
      );
      await loadCompetitions();
    } catch (e) {
      _errorMessage = 'Failed to update competition.';
      debugPrint('Update competition status error: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
