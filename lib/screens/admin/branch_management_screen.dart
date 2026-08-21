import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/branch.dart';
import '../../providers/branch_provider.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_button.dart';

/// Admin screen for creating, editing, and assigning managers to branches.
class BranchManagementScreen extends StatefulWidget {
  const BranchManagementScreen({super.key});

  @override
  State<BranchManagementScreen> createState() => _BranchManagementScreenState();
}

class _BranchManagementScreenState extends State<BranchManagementScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BranchProvider>().loadBranches();
      context.read<BranchProvider>().loadEligibleManagers();
    });
  }

  void _openBranchForm({Branch? branch}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BranchFormSheet(branch: branch),
    ).then((_) {
      context.read<BranchProvider>().loadBranches();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Branch Management',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        iconTheme: IconThemeData(color: colorScheme.onPrimary),
      ),
      body: Consumer<BranchProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading && provider.branches.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (provider.branches.isEmpty) {
            return EmptyState(
              icon: Icons.store_outlined,
              title: 'No Branches',
              subtitle: 'Add your first branch location.',
              action: TextButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Add Branch'),
                onPressed: () => _openBranchForm(),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () => provider.loadBranches(),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              itemCount: provider.branches.length,
              itemBuilder: (context, index) {
                final branch = provider.branches[index];

                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: Opacity(
                        opacity: branch.isActive ? 1.0 : 0.6,
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          leading: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(Icons.store, color: colorScheme.primary),
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  branch.name,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    decoration: branch.isActive ? null : TextDecoration.lineThrough,
                                  ),
                                ),
                              ),
                              if (!branch.isActive)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: colorScheme.errorContainer,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    'Inactive',
                                    style: TextStyle(color: colorScheme.onErrorContainer, fontSize: 11),
                                  ),
                                ),
                            ],
                          ),
                          subtitle: Text(branch.location ?? 'No address set'),
                          trailing: IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            tooltip: 'Edit Branch',
                            onPressed: () => _openBranchForm(branch: branch),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openBranchForm(),
        icon: const Icon(Icons.add),
        label: const Text('Add Branch'),
      ),
    );
  }
}

// ─── Branch Form Sheet ────────────────────────────────────────

class _BranchFormSheet extends StatefulWidget {
  final Branch? branch;
  const _BranchFormSheet({this.branch});

  @override
  State<_BranchFormSheet> createState() => _BranchFormSheetState();
}

class _BranchFormSheetState extends State<_BranchFormSheet> {
  final _nameController = TextEditingController();
  final _locationController = TextEditingController();
  String? _selectedManagerId;
  bool _isActive = true;
  bool _isSubmitting = false;

  bool get _isEditing => widget.branch != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      final b = widget.branch!;
      _nameController.text = b.name;
      _locationController.text = b.location ?? '';
      _selectedManagerId = b.managerId;
      _isActive = b.isActive;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Branch name is required.'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final provider = context.read<BranchProvider>();
      if (_isEditing) {
        await provider.updateBranch(
          id: widget.branch!.id,
          name: name,
          location: _locationController.text.trim().isEmpty ? null : _locationController.text.trim(),
          managerId: _selectedManagerId,
          isActive: _isActive,
        );
      } else {
        await provider.createBranch(
          name: name,
          location: _locationController.text.trim().isEmpty ? null : _locationController.text.trim(),
          managerId: _selectedManagerId,
        );
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEditing ? 'Branch updated successfully!' : 'Branch created successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save branch.'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final managers = context.watch<BranchProvider>().eligibleManagers;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _isEditing ? 'Edit Branch' : 'New Branch',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: cs.primary),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'Branch Name *',
                hintText: 'e.g. Banani Branch',
                prefixIcon: const Icon(Icons.store),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _locationController,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Location / Address',
                hintText: 'e.g. Block D, Road 11, Banani',
                prefixIcon: const Icon(Icons.location_on_outlined),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String?>(
              value: _selectedManagerId,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Assigned Manager (optional)',
                prefixIcon: const Icon(Icons.person_outline),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              hint: const Text('Select a manager'),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('No manager assigned')),
                ...managers.map((m) => DropdownMenuItem<String?>(
                      value: m.id,
                      child: Text('${m.name} (${m.email})', overflow: TextOverflow.ellipsis),
                    )),
              ],
              onChanged: (val) => setState(() => _selectedManagerId = val),
            ),
            if (_isEditing) ...[
              const SizedBox(height: 10),
              SwitchListTile(
                title: const Text('Active Branch'),
                subtitle: const Text('Inactive branches are hidden from sales and assignment'),
                value: _isActive,
                onChanged: (v) => setState(() => _isActive = v),
                contentPadding: EdgeInsets.zero,
              ),
            ],
            const SizedBox(height: 24),
            LoadingButton(
              label: _isEditing ? 'Save Changes' : 'Create Branch',
              icon: _isEditing ? Icons.save : Icons.add,
              isLoading: _isSubmitting,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}
