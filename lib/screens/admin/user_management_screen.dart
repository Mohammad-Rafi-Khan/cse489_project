import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/user_profile.dart';
import '../../providers/branch_provider.dart';
import '../../providers/user_management_provider.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_button.dart';

/// Admin screen for managing users, roles (Employee, Manager, Admin),
/// branch assignments, and account active/inactive statuses.
class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  String _searchQuery = '';
  String _roleFilter = 'all';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<UserManagementProvider>().loadUsers();
      context.read<BranchProvider>().loadBranches();
    });
  }

  void _openEditUserDialog(UserProfile user) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditUserSheet(user: user),
    ).then((_) {
      context.read<UserManagementProvider>().loadUsers();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'User & Role Management',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        iconTheme: IconThemeData(color: colorScheme.onPrimary),
      ),
      body: Column(
        children: [
          // Search & Filter header
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                children: [
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'Search by name or email...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                    onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final r in [
                          ('all', 'All Roles'),
                          ('employee', 'Employees'),
                          ('manager', 'Managers'),
                          ('admin', 'Admins'),
                        ])
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(r.$2),
                              selected: _roleFilter == r.$1,
                              onSelected: (val) => setState(() => _roleFilter = r.$1),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Consumer<UserManagementProvider>(
              builder: (context, provider, _) {
                if (provider.isLoading && provider.users.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }

                var list = provider.users;
                if (_roleFilter != 'all') {
                  list = list.where((u) => u.role == _roleFilter).toList();
                }
                if (_searchQuery.isNotEmpty) {
                  list = list
                      .where((u) =>
                          u.name.toLowerCase().contains(_searchQuery) ||
                          u.email.toLowerCase().contains(_searchQuery))
                      .toList();
                }

                if (list.isEmpty) {
                  return EmptyState(
                    icon: Icons.people_outline,
                    title: 'No Users Found',
                    subtitle: 'Try changing your search query or filters.',
                    action: TextButton.icon(
                      icon: const Icon(Icons.refresh),
                      label: const Text('Refresh'),
                      onPressed: () => provider.loadUsers(),
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () => provider.loadUsers(),
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: list.length,
                    itemBuilder: (context, index) {
                      final user = list[index];
                      final roleColor = user.isAdmin
                          ? Colors.purple
                          : (user.isManager ? Colors.teal : Colors.blue);

                      return Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 760),
                          child: Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: Opacity(
                              opacity: user.isActive ? 1.0 : 0.6,
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                leading: CircleAvatar(
                                  backgroundColor: roleColor.withValues(alpha: 0.15),
                                  child: Text(
                                    user.name.isNotEmpty ? user.name[0].toUpperCase() : 'U',
                                    style: TextStyle(color: roleColor, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        user.name,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          decoration: user.isActive ? null : TextDecoration.lineThrough,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: roleColor.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        user.role.toUpperCase(),
                                        style: TextStyle(
                                          color: roleColor,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    if (!user.isActive) ...[
                                      const SizedBox(width: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: colorScheme.errorContainer,
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Text(
                                          'INACTIVE',
                                          style: TextStyle(color: colorScheme.onErrorContainer, fontSize: 10),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(user.email),
                                    const SizedBox(height: 2),
                                    Row(
                                      children: [
                                        Icon(Icons.store, size: 12, color: colorScheme.primary),
                                        const SizedBox(width: 4),
                                        Text(
                                          user.branchName ?? 'No Branch Assigned',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: colorScheme.primary,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Icon(Icons.emoji_events, size: 12, color: Colors.amber.shade800),
                                        const SizedBox(width: 4),
                                        Text(
                                          '${user.totalLifetimePoints} pts (${user.badgeTierName})',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.amber.shade900,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.edit_outlined),
                                  tooltip: 'Edit Role & Branch',
                                  onPressed: () => _openEditUserDialog(user),
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
          ),
        ],
      ),
    );
  }
}

// ─── Edit User Sheet ──────────────────────────────────────────

class _EditUserSheet extends StatefulWidget {
  final UserProfile user;
  const _EditUserSheet({required this.user});

  @override
  State<_EditUserSheet> createState() => _EditUserSheetState();
}

class _EditUserSheetState extends State<_EditUserSheet> {
  final _nameController = TextEditingController();
  late String _role;
  String? _branchId;
  late bool _isActive;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.user.name;
    _role = widget.user.role;
    _branchId = widget.user.branchId;
    _isActive = widget.user.isActive;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _isSubmitting = true);
    try {
      await context.read<UserManagementProvider>().updateUser(
            id: widget.user.id,
            name: _nameController.text.trim(),
            role: _role,
            branchId: _branchId,
            isActive: _isActive,
          );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User profile updated!'), backgroundColor: Colors.green),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update user.'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final branches = context.watch<BranchProvider>().branches;

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
              'Edit User: ${widget.user.name}',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: cs.primary),
            ),
            const SizedBox(height: 4),
            Text(widget.user.email, style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6), fontSize: 13)),
            const SizedBox(height: 20),
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'Full Name',
                prefixIcon: const Icon(Icons.person),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              value: _role,
              decoration: InputDecoration(
                labelText: 'Role',
                prefixIcon: const Icon(Icons.shield_outlined),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              items: const [
                DropdownMenuItem(value: 'employee', child: Text('Employee')),
                DropdownMenuItem(value: 'manager', child: Text('Manager')),
                DropdownMenuItem(value: 'admin', child: Text('Admin')),
              ],
              onChanged: (val) => setState(() => _role = val ?? 'employee'),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String?>(
              value: _branchId,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Assigned Branch',
                prefixIcon: const Icon(Icons.store),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              hint: const Text('Select a branch'),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('No Branch Assigned')),
                ...branches.map((b) => DropdownMenuItem<String?>(
                      value: b.id,
                      child: Text('${b.name} (${b.location ?? ''})', overflow: TextOverflow.ellipsis),
                    )),
              ],
              onChanged: (val) => setState(() => _branchId = val),
            ),
            const SizedBox(height: 10),
            SwitchListTile(
              title: const Text('Active Account'),
              subtitle: const Text('Inactive users are prevented from logging in'),
              value: _isActive,
              onChanged: (v) => setState(() => _isActive = v),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 24),
            LoadingButton(
              label: 'Save Changes',
              icon: Icons.save,
              isLoading: _isSubmitting,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}
