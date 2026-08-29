import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/product.dart';
import '../../providers/auth_provider.dart';
import '../../providers/product_provider.dart';
import '../../widgets/empty_state.dart';

/// Displays products as the active pricing catalog for imported sales analytics.
class ProductListScreen extends StatefulWidget {
  const ProductListScreen({super.key});

  @override
  State<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends State<ProductListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ProductProvider>().loadProducts();
    });
  }

  bool get _canEdit {
    final role = context.read<AuthProvider>().profile?.role;
    return role == 'manager' || role == 'admin';
  }

  Future<void> _toggleActive(Product product) async {
    final action = product.isActive ? 'Deactivate' : 'Activate';

    if (product.isActive) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Deactivate Product'),
          content: Text(
            'Are you sure you want to deactivate "${product.name}"? '
            'It will no longer appear in new sales imports.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(
                'Deactivate',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (confirmed != true) return;
    }

    final productProvider = context.read<ProductProvider>();
    final wasActive = product.isActive;
    try {
      await productProvider.setProductActive(
        id: product.id,
        isActive: !wasActive,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${product.name} ${action}d successfully.'),
            backgroundColor: wasActive ? Colors.orange : Colors.green,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to $action product.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final canEdit = _canEdit;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Product Price Management',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        iconTheme: IconThemeData(color: colorScheme.onPrimary),
        actions: [
          if (canEdit)
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Add Product',
              onPressed: () async {
                await Navigator.pushNamed(context, '/product-form');
                if (!context.mounted) return;
                context.read<ProductProvider>().loadProducts();
              },
            ),
        ],
      ),
      body: Consumer<ProductProvider>(
        builder: (context, productProvider, _) {
          if (productProvider.isLoading && productProvider.products.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (productProvider.products.isEmpty) {
            return EmptyState(
              icon: Icons.inventory_2_outlined,
              title: 'No Products',
              subtitle: canEdit
                  ? 'Add products and maintain pricing for branch operations.'
                  : 'No products have been added yet.',
              action: TextButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
                onPressed: () => productProvider.loadProducts(),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () => productProvider.loadProducts(),
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(16, 16, 16, canEdit ? 96 : 24),
              itemCount: productProvider.products.length,
              itemBuilder: (context, index) {
                final product = productProvider.products[index];
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: _ProductCard(
                      product: product,
                      canEdit: canEdit,
                      onEdit: () async {
                        await Navigator.pushNamed(
                          context,
                          '/product-form',
                          arguments: product,
                        );
                        if (!mounted) return;
                        productProvider.loadProducts();
                      },
                      onToggleActive: () => _toggleActive(product),
                      onViewHistory: () async {
                        final history = await productProvider.fetchPriceHistory(product.id);
                        if (!mounted) return;
                        if (!context.mounted) return;
                        showDialog(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: Text('Price History - ${product.name}'),
                            content: SizedBox(
                              width: 420,
                              child: history.isEmpty
                                  ? const Text('No price changes recorded yet.')
                                  : ListView.separated(
                                      shrinkWrap: true,
                                      itemCount: history.length,
                                      separatorBuilder: (_, _) => const Divider(),
                                      itemBuilder: (context, index) {
                                        final item = history[index];
                                        final oldPrice = (item['old_price'] as num?)?.toDouble() ?? 0;
                                        final newPrice = (item['new_price'] as num?)?.toDouble() ?? 0;
                                        final updateTime = item['updated_at'] != null
                                            ? DateTime.parse(item['updated_at'] as String)
                                            : DateTime.now();
                                        return ListTile(
                                          title: Text('BDT ${newPrice.toStringAsFixed(0)}'),
                                          subtitle: Text(
                                            'From BDT ${oldPrice.toStringAsFixed(0)} • ${updateTime.toLocal().toString().substring(0, 16)}',
                                          ),
                                        );
                                      },
                                    ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Close'),
                              )
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              onPressed: () async {
                await Navigator.pushNamed(context, '/product-form');
                if (!context.mounted) return;
                context.read<ProductProvider>().loadProducts();
              },
              icon: const Icon(Icons.add),
              label: const Text('Add Product'),
            )
          : null,
    );
  }
}

class _ProductCard extends StatelessWidget {
  final Product product;
  final bool canEdit;
  final VoidCallback onEdit;
  final VoidCallback onToggleActive;
  final VoidCallback onViewHistory;

  const _ProductCard({
    required this.product,
    required this.canEdit,
    required this.onEdit,
    required this.onToggleActive,
    required this.onViewHistory,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isActive = product.isActive;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Opacity(
        opacity: isActive ? 1.0 : 0.65,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isActive
                      ? colorScheme.primaryContainer
                      : colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _categoryIcon(product.category),
                  color: isActive ? colorScheme.primary : colorScheme.outline,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            product.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              decoration: isActive
                                  ? null
                                  : TextDecoration.lineThrough,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: isActive
                                ? Colors.green.withValues(alpha: 0.12)
                                : colorScheme.errorContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            isActive ? 'Active' : 'Inactive',
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isActive
                                  ? Colors.green
                                  : colorScheme.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      product.category,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colorScheme.onSurface.withValues(alpha: 0.6),
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.sell_outlined, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          'BDT ${product.currentPrice.toStringAsFixed(0)}',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (canEdit) ...[
                const SizedBox(width: 2),
                PopupMenuButton<String>(
                  icon: Icon(
                    Icons.more_vert,
                    color: colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                  tooltip: 'Product actions',
                  onSelected: (value) {
                    if (value == 'edit') onEdit();
                    if (value == 'history') onViewHistory();
                    if (value == 'toggle') onToggleActive();
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit_outlined, size: 18),
                          SizedBox(width: 8),
                          Text('Edit'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'history',
                      child: Row(
                        children: [
                          Icon(Icons.history_outlined, size: 18),
                          SizedBox(width: 8),
                          Text('Price History'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'toggle',
                      child: Row(
                        children: [
                          Icon(
                            isActive
                                ? Icons.toggle_off_outlined
                                : Icons.toggle_on_outlined,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(isActive ? 'Deactivate' : 'Activate'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  IconData _categoryIcon(String category) {
    final lower = category.toLowerCase();
    if (lower.contains('beverage') || lower.contains('drink')) {
      return Icons.local_drink_outlined;
    }
    if (lower.contains('snack') || lower.contains('food')) {
      return Icons.fastfood_outlined;
    }
    if (lower.contains('dairy')) return Icons.egg_alt_outlined;
    if (lower.contains('fresh')) return Icons.eco_outlined;
    return Icons.category_outlined;
  }
}
