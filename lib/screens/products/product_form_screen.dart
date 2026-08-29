import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/product.dart';
import '../../providers/product_provider.dart';
import '../../widgets/custom_text_field.dart';
import '../../widgets/loading_button.dart';

/// Add or Edit product form screen.
/// Pass a [Product] via route arguments to edit; omit for adding a new product.
class ProductFormScreen extends StatefulWidget {
  const ProductFormScreen({super.key});

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _categoryController = TextEditingController();
  final _priceController = TextEditingController();

  Product? _editingProduct;
  bool _isSubmitting = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Product && _editingProduct == null) {
      _editingProduct = args;
      _nameController.text = args.name;
      _categoryController.text = args.category;
      _priceController.text = args.currentPrice.toStringAsFixed(0);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _categoryController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  bool get _isEditing => _editingProduct != null;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final name = _nameController.text.trim();
    final category = _categoryController.text.trim();
    final priceValue = double.tryParse(_priceController.text.trim()) ?? 0;

    setState(() => _isSubmitting = true);

    try {
      final productProvider = context.read<ProductProvider>();

      if (_isEditing) {
        await productProvider.updateProduct(
          id: _editingProduct!.id,
          name: name,
          category: category,
          currentPrice: priceValue,
        );
      } else {
        await productProvider.addProduct(
          name: name,
          category: category,
          currentPrice: priceValue,
        );
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isEditing
                ? 'Product updated successfully!'
                : 'Product "$name" added successfully!',
          ),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        final message =
            context.read<ProductProvider>().errorMessage ?? error.toString();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isEditing ? 'Edit Product' : 'Add Product',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        iconTheme: IconThemeData(color: colorScheme.onPrimary),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isEditing ? 'Edit Product Details' : 'New Product',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _isEditing
                          ? 'Update the product information below.'
                          : 'Fill in the details to add a new product.',
                      style: TextStyle(
                        color: colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                    const SizedBox(height: 28),
                    CustomTextField(
                      controller: _nameController,
                      label: 'Product Name',
                      hint: 'e.g. Coca-Cola',
                      prefixIcon: const Icon(Icons.label_outline),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Product name is required';
                        }
                        if (value.trim().length < 2) {
                          return 'Name must be at least 2 characters';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    CustomTextField(
                      controller: _categoryController,
                      label: 'Category',
                      hint: 'e.g. Beverage, Snacks',
                      prefixIcon: const Icon(Icons.category_outlined),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Category is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    CustomTextField(
                      controller: _priceController,
                      label: 'Current Price (BDT)',
                      hint: 'e.g. 55',
                      keyboardType: TextInputType.number,
                      prefixIcon: const Icon(Icons.attach_money_outlined),
                      validator: (value) {
                        final parsed = double.tryParse(value?.trim() ?? '');
                        if (parsed == null || parsed < 0) {
                          return 'Enter a valid price';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 32),
                    LoadingButton(
                      label: _isEditing ? 'Save Changes' : 'Add Product',
                      icon: _isEditing
                          ? Icons.save_outlined
                          : Icons.add_circle_outline,
                      isLoading: _isSubmitting,
                      onPressed: _submit,
                    ),
                    if (_isEditing) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: OutlinedButton(
                          onPressed: _isSubmitting
                              ? null
                              : () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('Cancel'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
