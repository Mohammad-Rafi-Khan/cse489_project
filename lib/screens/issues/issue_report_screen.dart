import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/issue_report.dart';
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
    final profile = auth.profile;
    final branchId = profile?.branchId;

    if (branchId == null || profile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Branch information is unavailable.')),
      );
      return;
    }

    try {
      await context.read<IssueProvider>().createIssue(
            branchId: branchId,
            reportedBy: profile.id,
            reporterName: profile.name,
            reporterRole: profile.role,
            title: _titleController.text.trim(),
            description: _descriptionController.text.trim(),
            priority: _priority,
          );
      if (!mounted) return;
      _titleController.clear();
      _descriptionController.clear();
      final role = profile.role;
      final successMsg = role == 'employee'
          ? 'Issue reported to your manager.'
          : 'Issue escalated to admin.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(successMsg)),
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
    final auth = context.watch<AuthProvider>();
    final profile = auth.profile;
    final role = profile?.role ?? 'employee';

    String appBarTitle;
    if (role == 'admin') {
      appBarTitle = 'Company Issue Reports';
    } else if (role == 'manager') {
      appBarTitle = 'Issue Management';
    } else {
      appBarTitle = 'Report an Issue';
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(appBarTitle),
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
      ),
      body: Consumer<IssueProvider>(
        builder: (context, provider, _) {
          return RefreshIndicator(
            onRefresh: _loadIssues,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── SUBMIT FORM (employees & managers only) ──────────────
                if (role != 'admin') ...[
                  _RoleInfoBanner(role: role, colorScheme: colorScheme),
                  const SizedBox(height: 16),
                  Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          controller: _titleController,
                          decoration:
                              const InputDecoration(labelText: 'Issue title'),
                          validator: (value) =>
                              (value == null || value.trim().isEmpty)
                                  ? 'Please enter a title'
                                  : null,
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: _priority,
                          decoration:
                              const InputDecoration(labelText: 'Priority'),
                          items: const [
                            DropdownMenuItem(
                                value: 'low', child: Text('Low')),
                            DropdownMenuItem(
                                value: 'medium', child: Text('Medium')),
                            DropdownMenuItem(
                                value: 'high', child: Text('High')),
                            DropdownMenuItem(
                                value: 'critical',
                                child: Text('Critical')),
                          ],
                          onChanged: (value) =>
                              setState(() => _priority = value ?? 'medium'),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _descriptionController,
                          minLines: 4,
                          maxLines: 8,
                          decoration:
                              const InputDecoration(labelText: 'Description'),
                          validator: (value) =>
                              (value == null || value.trim().isEmpty)
                                  ? 'Please describe the issue'
                                  : null,
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed:
                              provider.isLoading ? null : _submitIssue,
                          icon: const Icon(Icons.report_problem_outlined),
                          label: Text(role == 'manager'
                              ? 'Escalate to Admin'
                              : 'Submit Issue'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                ],

                // ── MANAGER: two sections ────────────────────────────────
                if (role == 'manager') ...[
                  _buildManagerSections(
                      context, provider, profile?.id ?? ''),
                ],

                // ── EMPLOYEE: their own submissions ──────────────────────
                if (role == 'employee') ...[
                  _buildIssueSection(
                    context: context,
                    title: 'Your Submitted Issues',
                    issues: provider.issues,
                    showReporter: false,
                  ),
                ],

                // ── ADMIN: all company issues ────────────────────────────
                if (role == 'admin') ...[
                  _buildIssueSection(
                    context: context,
                    title: 'All Company Issues',
                    issues: provider.issues,
                    showReporter: true,
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildManagerSections(
      BuildContext context, IssueProvider provider, String managerId) {
    final myEscalations =
        provider.issues.where((i) => i.reportedBy == managerId).toList();
    final employeeIssues =
        provider.issues.where((i) => i.reportedBy != managerId).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildIssueSection(
          context: context,
          title: 'Your Escalations to Admin',
          issues: myEscalations,
          showReporter: false,
          emptyMessage: 'No escalations filed yet.',
        ),
        const SizedBox(height: 24),
        _buildIssueSection(
          context: context,
          title: 'Employee-Reported Issues',
          issues: employeeIssues,
          showReporter: true,
          emptyMessage: 'No issues reported by employees.',
        ),
      ],
    );
  }

  Widget _buildIssueSection({
    required BuildContext context,
    required String title,
    required List<IssueReport> issues,
    required bool showReporter,
    String emptyMessage = 'No issues found.',
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 8),
        if (issues.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              emptyMessage,
              style: TextStyle(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.5),
              ),
            ),
          )
        else
          ...issues.take(20).map(
                (issue) => _IssueCard(
                  issue: issue,
                  showReporter: showReporter,
                ),
              ),
      ],
    );
  }
}

// ── Role info banner ──────────────────────────────────────────────────────────

class _RoleInfoBanner extends StatelessWidget {
  final String role;
  final ColorScheme colorScheme;

  const _RoleInfoBanner({required this.role, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    final isManager = role == 'manager';
    final icon =
        isManager ? Icons.upload_outlined : Icons.report_problem_outlined;
    final heading =
        isManager ? 'Escalate an Issue to Admin' : 'Report an Issue to Your Manager';
    final subtext = isManager
        ? 'Use this form to escalate branch-level problems that require admin attention. Admin will be notified immediately.'
        : 'Describe the issue you are facing. Your branch manager will be notified immediately.';
    final color = isManager ? Colors.orange.shade700 : colorScheme.primary;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  heading,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: color,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtext,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Issue card ────────────────────────────────────────────────────────────────

class _IssueCard extends StatelessWidget {
  final IssueReport issue;
  final bool showReporter;

  const _IssueCard({required this.issue, required this.showReporter});

  Color _priorityColor(String priority) {
    switch (priority) {
      case 'critical':
        return Colors.red;
      case 'high':
        return Colors.deepOrange;
      case 'medium':
        return Colors.orange;
      default:
        return Colors.blue;
    }
  }

  @override
  Widget build(BuildContext context) {
    final pColor = _priorityColor(issue.priority);
    final subtitle = [
      issue.priority.toUpperCase(),
      if (showReporter && issue.reporterName != null)
        'by ${issue.reporterName}',
      issue.statusLabel,
    ].join(' • ');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          width: 6,
          height: 40,
          decoration: BoxDecoration(
            color: pColor,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        title: Text(
          issue.title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: Icon(
          issue.isResolved
              ? Icons.check_circle
              : issue.isInProgress
                  ? Icons.autorenew
                  : Icons.pending_actions,
          color: issue.isResolved
              ? Colors.green
              : issue.isInProgress
                  ? Colors.blue
                  : Colors.orange,
        ),
      ),
    );
  }
}
