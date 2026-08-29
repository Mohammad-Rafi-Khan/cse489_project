import 'package:flutter/foundation.dart';

import '../models/points_transaction.dart';
import '../services/points_service.dart';

/// Manages the employee points transaction ledger for reward history screens.
class PointsProvider extends ChangeNotifier {
  final PointsService _pointsService = PointsService();

  List<PointsTransaction> _transactions = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<PointsTransaction> get transactions => _transactions;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  int get totalEarned =>
      _transactions.fold(0, (sum, transaction) => sum + transaction.points);

  Future<void> loadUserTransactions(String userId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _transactions = await _pointsService.fetchUserTransactions(userId);
    } catch (e) {
      _errorMessage = 'Failed to load points history.';
      debugPrint('Load points history error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void clear() {
    _transactions = [];
    _errorMessage = null;
    notifyListeners();
  }
}
