import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/product.dart';
import '../../models/shift.dart';
import '../../providers/auth_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/sales_provider.dart';
import '../../providers/shift_provider.dart';
import '../../widgets/loading_button.dart';

/// Employee screen for recording product sales transactions.
class SalesEntryScreen extends StatefulWidget {
  const SalesEntryScreen({super.key});

  @override
  State<SalesEntryScreen> createState() => _SalesEntryScreenState();
}

class _SalesEntryScreenState extends State<SalesEntryScreen> {
  Product? _selectedProduct;
  Shift? _selectedShift;
  DateTime _saleDate = DateTime.now();
  final _quantityController = TextEditingController(text: '1');
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  @override
  void dispose() {
    _quantityController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final auth = context.read<AuthProvider>();
    final branchId = auth.profile?.branchId;
    if (branchId == null) return;

    await Future.wait([
      context.read<ProductProvider>().loadProducts(),
      context.read<ShiftProvider>().loadShifts(branchId),
    ]);
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _saleDate,
      firstDate: now.subtract(const Duration(days: 30)),
      lastDate: now,
    );
    if (picked != null) setState(() => _saleDate = picked);
  }

  Future<void> _submit() async {
    if (_selectedProduct == null) {
      _showSnack('Please select a product.', isError: true);
      return;
    }
    final qty = int.tryParse(_quantityController.text.trim());
    if (qty == null || qty <= 0) {
      _showSnack('Please enter a valid quantity.', isError: true);
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final auth = context.read<AuthProvider>();
      await context.read<SalesProvider>().recordSale(
            branchId: auth.profile!.branchId!,
            shiftId: _selectedShift?.id,
            saleDate: _saleDate,
            employeeId: auth.profile!.id,
            productId: _selectedProduct!.id,
            quantity: qty,
            unitPrice: _selectedProduct!.unitPrice,
          );
      if (!mounted) return;
      _showSnack(
          '${_selectedProduct!.name} × $qty recorded! Total: ৳${(_selectedProduct!.unitPrice * qty).toStringAsFixed(2)}');
      setState(() {
        _selectedProduct = null;
        _quantityController.text = '1';
      });
    } catch (_) {
      if (mounted) _showSnack('Failed to record sale.', isError: true);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red : Colors.green,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final dateFormatter = DateFormat('EEE, dd MMM yyyy');

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Record Sale',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        iconTheme: IconThemeData(color: colorScheme.onPrimary),
      ),
      body: Consumer3<ProductProvider, ShiftProvider, SalesProvider>(
        builder: (context, productProvider, shiftProvider, salesProvider, _) {
          final products =
              productProvider.products.where((p) => p.isActive).toList();

          return SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Product ─────────────────────────────
                      _SectionHeader(
                          icon: Icons.inventory_2_outlined,
                          title: 'Product'),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<Product>(
                        value: _selectedProduct,
                        isExpanded: true,
                        menuMaxHeight: 340,
                        decoration: _dropDeco(
                            context, 'Select product', Icons.inventory_2_outlined),
                        hint: const Text('Choose a product'),
                        items: products
                            .map((p) => DropdownMenuItem<Product>(
                                  value: p,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                      Text(p.name,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w600)),
                                      Text(
                                          '৳${p.unitPrice.toStringAsFixed(2)} · ${p.category}',
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: colorScheme.primary)),
                                    ],
                                  ),
                                ))
                            .toList(),
                        selectedItemBuilder: (_) => products
                            .map((p) => Text(p.name,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)))
                            .toList(),
                        onChanged: (p) =>
                            setState(() => _selectedProduct = p),
                        itemHeight: 60,
                      ),
                      const SizedBox(height: 20),

                      // ── Quantity ─────────────────────────────
                      _SectionHeader(
                          icon: Icons.format_list_numbered,
                          title: 'Quantity'),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _quantityController,
                        keyboardType: TextInputType.number,
                        decoration: _dropDeco(context, 'Quantity',
                            Icons.format_list_numbered),
                      ),
                      const SizedBox(height: 20),

                      // ── Date & Shift ─────────────────────────
                      _SectionHeader(
                          icon: Icons.calendar_today_outlined,
                          title: 'Sale Date & Shift'),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _PickerCard(
                              icon: Icons.calendar_month_outlined,
                              label: 'Date',
                              value: dateFormatter.format(_saleDate),
                              hasValue: true,
                              onTap: _pickDate,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: shiftProvider.shifts.isEmpty
                                ? _PickerCard(
                                    icon: Icons.schedule_outlined,
                                    label: 'Shift',
                                    value: 'No shifts',
                                    hasValue: false,
                                    onTap: () {},
                                  )
                                : DropdownButtonFormField<Shift?>(
                                    value: _selectedShift,
                                    isExpanded: true,
                                    decoration: _dropDeco(
                                        context,
                                        'Shift (optional)',
                                        Icons.schedule_outlined),
                                    hint: const Text('Any shift'),
                                    items: [
                                      const DropdownMenuItem<Shift?>(
                                          value: null,
                                          child: Text('No shift')),
                                      ...shiftProvider.shifts
                                          .map((s) => DropdownMenuItem<Shift?>(
                                                value: s,
                                                child: Text(s.name,
                                                    overflow:
                                                        TextOverflow.ellipsis),
                                              )),
                                    ],
                                    onChanged: (s) =>
                                        setState(() => _selectedShift = s),
                                  ),
                          ),
                        ],
                      ),

                      // ── Preview ──────────────────────────────
                      if (_selectedProduct != null) ...[
                        const SizedBox(height: 24),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Sale Preview',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.onPrimaryContainer,
                                ),
                              ),
                              const SizedBox(height: 8),
                              _PreviewRow(
                                  label: 'Product',
                                  value: _selectedProduct!.name),
                              _PreviewRow(
                                  label: 'Unit Price',
                                  value:
                                      '৳${_selectedProduct!.unitPrice.toStringAsFixed(2)}'),
                              _PreviewRow(
                                  label: 'Quantity',
                                  value: _quantityController.text),
                              _PreviewRow(
                                label: 'Total',
                                value:
                                    '৳${(_selectedProduct!.unitPrice * (int.tryParse(_quantityController.text) ?? 0)).toStringAsFixed(2)}',
                                isTotal: true,
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 28),
                      LoadingButton(
                        label: 'Record Sale',
                        icon: Icons.point_of_sale,
                        isLoading: _isSubmitting,
                        onPressed: _submit,
                      ),

                      // ── Recent Entries ───────────────────────
                      if (salesProvider.entries.isNotEmpty) ...[
                        const SizedBox(height: 32),
                        Text(
                          'Recent Entries Today',
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 10),
                        ...salesProvider.entries.take(5).map((e) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: colorScheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(Icons.receipt_long_outlined,
                                    color: colorScheme.primary, size: 20),
                              ),
                              title: Text('${e.productName ?? 'Product'} × ${e.quantity}'),
                              subtitle: Text(
                                  DateFormat('h:mm a').format(e.recordedAt.toLocal())),
                              trailing: Text(
                                '৳${e.totalAmount.toStringAsFixed(2)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.primary,
                                ),
                              ),
                            )),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  InputDecoration _dropDeco(BuildContext ctx, String label, IconData icon) {
    final cs = Theme.of(ctx).colorScheme;
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: cs.outline.withOpacity(0.5)),
      ),
      filled: true,
      fillColor: cs.surface,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  const _SectionHeader({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Text(title,
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _PickerCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool hasValue;
  final VoidCallback onTap;
  const _PickerCard(
      {required this.icon,
      required this.label,
      required this.value,
      required this.hasValue,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border.all(
            color: hasValue
                ? cs.primary
                : cs.outline.withOpacity(0.5),
            width: hasValue ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
          color: cs.surface,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon,
              size: 18,
              color: hasValue
                  ? cs.primary
                  : cs.onSurface.withOpacity(0.5)),
          const SizedBox(height: 6),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  color: cs.onSurface.withOpacity(0.5))),
          const SizedBox(height: 2),
          Text(value,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight:
                      hasValue ? FontWeight.w600 : FontWeight.normal)),
        ]),
      ),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isTotal;
  const _PreviewRow(
      {required this.label, required this.value, this.isTotal = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Row(children: [
        SizedBox(
          width: 80,
          child: Text('$label:',
              style: TextStyle(
                  color: cs.onPrimaryContainer.withOpacity(0.7),
                  fontSize: 13)),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(value,
              style: TextStyle(
                  fontWeight:
                      isTotal ? FontWeight.bold : FontWeight.w600,
                  color: cs.onPrimaryContainer,
                  fontSize: isTotal ? 15 : 13)),
        ),
      ]),
    );
  }
}
