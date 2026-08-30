import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/product.dart';

/// Handles all Supabase queries for the `products` table and price history.
class ProductService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<List<Product>> fetchProducts() async {
    final data = await _supabase
        .from('products')
        .select('*, profiles!updated_by(name)')
        .order('name');
    return (data as List).map((e) => Product.fromMap(e)).toList();
  }

  Future<Product> addProduct({
    required String name,
    required String category,
    double currentPrice = 0,
  }) async {
    final data = await _supabase
        .from('products')
        .insert({
          'name': name.trim(),
          'category': category.trim(),
          'current_price': currentPrice,
          'updated_by': _supabase.auth.currentUser?.id,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .select('*, profiles!updated_by(name)')
        .single();
    return Product.fromMap(data);
  }

  Future<Product> updateProduct({
    required String id,
    required String name,
    required String category,
    double currentPrice = 0,
  }) async {
    final userId = _supabase.auth.currentUser?.id;

    final data = await _supabase
        .from('products')
        .update({
          'name': name.trim(),
          'category': category.trim(),
          'current_price': currentPrice,
          'updated_by': userId,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', id)
        .select('*, profiles!updated_by(name)')
        .single();

    return Product.fromMap(data);
  }

  Future<Product> updateProductPrice({
    required String id,
    required double newPrice,
  }) async {
    final userId = _supabase.auth.currentUser?.id;

    final data = await _supabase
        .from('products')
        .update({
          'current_price': newPrice,
          'updated_by': userId,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', id)
        .select('*, profiles!updated_by(name)')
        .single();

    return Product.fromMap(data);
  }

  Future<List<Map<String, dynamic>>> fetchPriceHistory(String productId) async {
    final data = await _supabase
        .from('product_price_history')
        .select('*, profiles!updated_by(name)')
        .eq('product_id', productId)
        .order('updated_at', ascending: false);
    return List<Map<String, dynamic>>.from(data as List);
  }

  Future<void> setProductActive({
    required String id,
    required bool isActive,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    await _supabase
        .from('products')
        .update({
          'is_active': isActive,
          'updated_by': userId,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', id);
  }
}
