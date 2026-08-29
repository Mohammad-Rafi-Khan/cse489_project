import 'package:flutter/foundation.dart';
import '../models/product.dart';
import '../services/product_service.dart';

/// Manages product list state and price-management operations.
class ProductProvider extends ChangeNotifier {
  final ProductService _productService = ProductService();

  List<Product> _products = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<Product> get products => _products;
  List<Product> get activeProducts =>
      _products.where((p) => p.isActive).toList();
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> loadProducts() async {
    _setLoading(true);
    _clearError();
    try {
      _products = await _productService.fetchProducts();
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to load products. Please try again.';
      debugPrint('Load products error: $e');
      notifyListeners();
    } finally {
      _setLoading(false);
    }
  }

  Future<void> addProduct({
    required String name,
    required String category,
    double currentPrice = 0,
  }) async {
    _setLoading(true);
    _clearError();
    try {
      final newProduct = await _productService.addProduct(
        name: name,
        category: category,
        currentPrice: currentPrice,
      );
      _products = [newProduct, ..._products];
      _products.sort((a, b) => a.name.compareTo(b.name));
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to add product. Please try again.';
      debugPrint('Add product error: $e');
      notifyListeners();
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> updateProduct({
    required String id,
    required String name,
    required String category,
    double currentPrice = 0,
  }) async {
    _setLoading(true);
    _clearError();
    try {
      final updated = await _productService.updateProduct(
        id: id,
        name: name,
        category: category,
        currentPrice: currentPrice,
      );
      final index = _products.indexWhere((p) => p.id == id);
      if (index != -1) {
        _products[index] = updated;
        notifyListeners();
      }
    } catch (e) {
      _errorMessage = 'Failed to update product. Please try again.';
      debugPrint('Update product error: $e');
      notifyListeners();
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<Product> updateProductPrice({
    required String id,
    required double newPrice,
  }) async {
    _clearError();
    try {
      final updated = await _productService.updateProductPrice(
        id: id,
        newPrice: newPrice,
      );
      final index = _products.indexWhere((p) => p.id == id);
      if (index != -1) {
        _products[index] = updated;
      }
      notifyListeners();
      return updated;
    } catch (e) {
      _errorMessage = 'Failed to update product price.';
      debugPrint('Update product price error: $e');
      notifyListeners();
      rethrow;
    }
  }

  Future<List<dynamic>> fetchPriceHistory(String productId) async {
    return _productService.fetchPriceHistory(productId);
  }

  Future<void> setProductActive({
    required String id,
    required bool isActive,
  }) async {
    _clearError();
    try {
      await _productService.setProductActive(id: id, isActive: isActive);
      final index = _products.indexWhere((p) => p.id == id);
      if (index != -1) {
        _products[index] = _products[index].copyWith(isActive: isActive);
        notifyListeners();
      }
    } catch (e) {
      _errorMessage = 'Failed to update product status.';
      debugPrint('SetProductActive error: $e');
      notifyListeners();
      rethrow;
    }
  }

  void clearAll() {
    _products = [];
    _errorMessage = null;
    _isLoading = false;
    notifyListeners();
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void _clearError() {
    _errorMessage = null;
  }
}
