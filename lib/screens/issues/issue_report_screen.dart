import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/issue_provider.dart';

class IssueReportScreen extends StatefulWidget {
  const IssueReportScreen({super.key});

  @override
  State<IssueReportScreen> createState() => _IssueReportScreenState();
}

class _IssueReportScreenState extends State<IssueReportScreen> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  String _priority = 'medium';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadIssues());
  }

  Future<void> _loadIssues() async {
    final auth = context.read<AuthProvider>();
    final profile = auth.profile;
    if (profile == null) return;

    final issueProvider = context.read<IssueProvider>();
    if (profile.isEmployee) {
      await issueProvider.loadMyIssues(profile.id);
    } else if (profile.isManager) {
      final branchId = profile.branchId;
      if (branchId != null) {
        await issueProvider.loadBranchIssues(branchId);
      }
    } else if (profile.isAdmin) {
      await issueProvider.loadCompanyIssues();
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submitIssue() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    final branchId = auth.profile?.branchId;
    if (branchId == null || auth.profile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Branch information is unavailable.')),
      );
      return;
    }

    try {
      await context.read<IssueProvider>().createIssue(
        branchId: branchId,
        reportedBy: auth.profile!.id,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        priority: _priority,
      );
      if (!mounted) return;
      _titleController.clear();
      _descriptionController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Issue reported successfully.')),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to create issue report.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Issue Reporting'),
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
      ),
      body: Consumer<IssueProvider>(
        builder: (context, provider, _) {
          return RefreshIndicator(
            onRefresh: _loadIssues,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Report a branch issue',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _titleController,
                      decoration: const InputDecoration(labelText: 'Issue title'),
                      validator: (value) => (value == null || value.trim().isEmpty)
                          ? 'Please enter a title'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _priority,
                      decoration: const InputDecoration(labelText: 'Priority'),
                      items: const [
                        DropdownMenuItem(value: 'low', child: Text('Low')),
                        DropdownMenuItem(value: 'medium', child: Text('Medium')),
                        DropdownMenuItem(value: 'high', child: Text('High')),
                        DropdownMenuItem(value: 'critical', child: Text('Critical')),
                      ],
                      onChanged: (value) => setState(() => _priority = value ?? 'medium'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _descriptionController,
                      minLines: 4,
                      maxLines: 8,
                      decoration: const InputDecoration(labelText: 'Description'),
                      validator: (value) => (value == null || value.trim().isEmpty)
                          ? 'Please describe the issue'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: provider.isLoading ? null : _submitIssue,
                      icon: const Icon(Icons.report_problem_outlined),
                      label: const Text('Submit Issue'),
                    ),
                    const SizedBox(height: 24),
                    if (provider.issues.isNotEmpty) ...[
                      Text(
                        'Recent reports',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...provider.issues.take(6).map((issue) => Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              title: Text(issue.title),
                              subtitle: Text('${issue.priority.toUpperCase()} • ${issue.statusLabel}'),
                              trailing: Icon(
                                issue.isResolved ? Icons.check_circle : Icons.pending_actions,
                                color: issue.isResolved ? Colors.green : Colors.orange,
                              ),
                            ),
                          )),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
