import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/leave_provider.dart';

class LeaveRequestScreen extends StatefulWidget {
  const LeaveRequestScreen({super.key});

  @override
  State<LeaveRequestScreen> createState() => _LeaveRequestScreenState();
}

class _LeaveRequestScreenState extends State<LeaveRequestScreen> {
  final _reasonController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now().add(const Duration(days: 1));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadLeaves());
  }

  Future<void> _loadLeaves() async {
    final auth = context.read<AuthProvider>();
    final profile = auth.profile;
    if (profile == null) return;

    final leaveProvider = context.read<LeaveProvider>();
    if (profile.isEmployee) {
      await leaveProvider.loadMyLeaves(profile.id);
    } else if (profile.isManager) {
      final branchId = profile.branchId;
      if (branchId != null) {
        await leaveProvider.loadBranchLeaves(branchId);
      }
    } else if (profile.isAdmin) {
      await leaveProvider.loadCompanyLeaves();
    }
  }

  Future<void> _pickDate({required bool isStart}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _startDate : _endDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
        if (_endDate.isBefore(_startDate)) _endDate = _startDate;
      } else {
        _endDate = picked;
      }
    });
  }

  Future<void> _submitLeave() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    final branchId = auth.profile?.branchId;
    final userId = auth.profile?.id;
    if (branchId == null || userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile is not ready yet.')),
      );
      return;
    }

    try {
      await context.read<LeaveProvider>().createLeaveRequest(
        branchId: branchId,
        employeeId: userId,
        startDate: _startDate,
        endDate: _endDate,
        reason: _reasonController.text.trim(),
      );
      if (!mounted) return;
      _reasonController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Leave request submitted.')),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to submit leave request.')),
        );
      }
    }
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Leave Requests'),
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
      ),
      body: Consumer<LeaveProvider>(
        builder: (context, provider, _) {
          return RefreshIndicator(
            onRefresh: _loadLeaves,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Request time off',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    InkWell(
                      onTap: () => _pickDate(isStart: true),
                      child: InputDecorator(
                        decoration: const InputDecoration(labelText: 'Start date'),
                        child: Text('${_startDate.year}-${_startDate.month.toString().padLeft(2, '0')}-${_startDate.day.toString().padLeft(2, '0')}'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () => _pickDate(isStart: false),
                      child: InputDecorator(
                        decoration: const InputDecoration(labelText: 'End date'),
                        child: Text('${_endDate.year}-${_endDate.month.toString().padLeft(2, '0')}-${_endDate.day.toString().padLeft(2, '0')}'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _reasonController,
                      minLines: 3,
                      maxLines: 6,
                      decoration: const InputDecoration(labelText: 'Reason'),
                      validator: (value) => (value == null || value.trim().isEmpty)
                          ? 'Please provide a reason'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: provider.isLoading ? null : _submitLeave,
                      icon: const Icon(Icons.event_available_outlined),
                      label: const Text('Submit Request'),
                    ),
                    const SizedBox(height: 24),
                    if (provider.requests.isNotEmpty) ...[
                      Text(
                        'Request history',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...provider.requests.take(6).map((request) => Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              title: Text(request.reason),
                              subtitle: Text('${request.startDate.toIso8601String().split('T').first} to ${request.endDate.toIso8601String().split('T').first}'),
                              trailing: Text(
                                request.statusLabel,
                                style: TextStyle(
                                  color: request.isApproved ? Colors.green : request.isRejected ? Colors.red : Colors.orange,
                                  fontWeight: FontWeight.w700,
                                ),
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
