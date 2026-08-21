import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../providers/branch_provider.dart';
import '../../providers/competition_provider.dart';
import '../../providers/product_provider.dart';
import '../../widgets/loading_button.dart';

/// Admin screen for creating an inter-branch competition with participating branches and products.
class CompetitionFormScreen extends StatefulWidget {
  const CompetitionFormScreen({super.key});

  @override
  State<CompetitionFormScreen> createState() => _CompetitionFormScreenState();
}

class _CompetitionFormScreenState extends State<CompetitionFormScreen> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now().add(const Duration(days: 30));

  final Set<String> _selectedBranchIds = {};
  final Map<String, int> _selectedProductPoints = {}; // productId -> pointsPerUnit
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BranchProvider>().loadBranches();
      context.read<ProductProvider>().loadProducts();
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
    );
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
    }
  }

  Future<void> _submit() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a competition title.'), backgroundColor: Colors.red),
      );
      return;
    }

    if (_selectedBranchIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one participating branch.'), backgroundColor: Colors.red),
      );
      return;
    }

    if (_selectedProductPoints.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one qualifying product.'), backgroundColor: Colors.red),
      );
      return;
    }

    final productRows = _selectedProductPoints.entries
        .map((e) => {
              'product_id': e.key,
              'points_per_unit': e.value,
            })
        .toList();

    setState(() => _isSubmitting = true);
    try {
      await context.read<CompetitionProvider>().createCompetition(
            title: title,
            description: _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
            startDate: _startDate,
            endDate: _endDate,
            branchIds: _selectedBranchIds.toList(),
            products: productRows,
          );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Competition created successfully!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: ${e.toString().replaceAll('Exception: ', '')}'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final branches = context.watch<BranchProvider>().activeBranches;
    final products = context.watch<ProductProvider>().products.where((p) => p.isActive).toList();
    final dateFormatter = DateFormat('dd MMM yyyy');

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Create Competition',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        iconTheme: IconThemeData(color: colorScheme.onPrimary),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Competition Details',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _titleController,
                    decoration: InputDecoration(
                      labelText: 'Competition Title *',
                      hintText: 'e.g. August Coca-Cola Challenge',
                      prefixIcon: const Icon(Icons.emoji_events_outlined),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _descriptionController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: 'Description / Rules',
                      hintText: 'e.g. Every bottle of Coca-Cola sold earns 2 points for your branch.',
                      prefixIcon: const Icon(Icons.notes_outlined),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Date range picker card
                  Text(
                    'Timeframe Window',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: _pickDateRange,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border.all(color: colorScheme.primary, width: 2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.date_range_outlined, color: colorScheme.primary),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${dateFormatter.format(_startDate)} – ${dateFormatter.format(_endDate)}',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                              const Text('Tap to change dates', style: TextStyle(fontSize: 12)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Participating Branches Multi-Select
                  Text(
                    'Participating Branches *',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    child: Column(
                      children: branches.map((b) {
                        final isSelected = _selectedBranchIds.contains(b.id);
                        return CheckboxListTile(
                          title: Text(b.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(b.location ?? ''),
                          value: isSelected,
                          onChanged: (val) {
                            setState(() {
                              if (val == true) {
                                _selectedBranchIds.add(b.id);
                              } else {
                                _selectedBranchIds.remove(b.id);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Qualifying Products & Points
                  Text(
                    'Qualifying Products & Points Per Unit *',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    child: Column(
                      children: products.map((p) {
                        final isSelected = _selectedProductPoints.containsKey(p.id);
                        final currentPts = _selectedProductPoints[p.id] ?? 2;

                        return ListTile(
                          title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text('৳${p.unitPrice.toStringAsFixed(2)} · ${p.category}'),
                          leading: Checkbox(
                            value: isSelected,
                            onChanged: (val) {
                              setState(() {
                                if (val == true) {
                                  _selectedProductPoints[p.id] = 2; // default 2 pts
                                } else {
                                  _selectedProductPoints.remove(p.id);
                                }
                              });
                            },
                          ),
                          trailing: isSelected
                              ? DropdownButton<int>(
                                  value: currentPts,
                                  items: [1, 2, 3, 5, 10]
                                      .map((pts) => DropdownMenuItem(
                                            value: pts,
                                            child: Text('$pts pt(s)'),
                                          ))
                                      .toList(),
                                  onChanged: (newPts) {
                                    if (newPts != null) {
                                      setState(() => _selectedProductPoints[p.id] = newPts);
                                    }
                                  },
                                )
                              : null,
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 32),

                  LoadingButton(
                    label: 'Create & Start Competition',
                    icon: Icons.emoji_events,
                    isLoading: _isSubmitting,
                    onPressed: _submit,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
