import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/product.dart';

/// Handles all Supabase queries for the `products` table.
class ProductService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Returns all products ordered by name.
  Future<List<Product>> fetchProducts() async {
    final data = await _supabase
        .from('products')
        .select()
        .order('name');
    return (data as List).map((e) => Product.fromMap(e)).toList();
  }

  /// Inserts a new product and returns the created record.
  Future<Product> addProduct({
    required String name,
    required String category,
    required double unitPrice,
  }) async {
    final data = await _supabase
        .from('products')
        .insert({
          'name': name.trim(),
          'category': category.trim(),
          'unit_price': unitPrice,
        })
        .select()
        .single();
    return Product.fromMap(data);
  }

  /// Updates an existing product and returns the updated record.
  Future<Product> updateProduct({
    required String id,
    required String name,
    required String category,
    required double unitPrice,
  }) async {
    final data = await _supabase
        .from('products')
        .update({
          'name': name.trim(),
          'category': category.trim(),
          'unit_price': unitPrice,
        })
        .eq('id', id)
        .select()
        .single();
    return Product.fromMap(data);
  }

  /// Sets a product's active status (soft activate/deactivate).
  Future<void> setProductActive({
    required String id,
    required bool isActive,
  }) async {
    await _supabase
        .from('products')
        .update({'is_active': isActive})
        .eq('id', id);
  }
}
