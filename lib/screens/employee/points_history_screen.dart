import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/points_transaction.dart';
import '../../providers/auth_provider.dart';
import '../../providers/points_provider.dart';

class PointsHistoryScreen extends StatefulWidget {
  const PointsHistoryScreen({super.key});

  @override
  State<PointsHistoryScreen> createState() => _PointsHistoryScreenState();
}

class _PointsHistoryScreenState extends State<PointsHistoryScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadHistory());
  }

  Future<void> _loadHistory() async {
    final auth = context.read<AuthProvider>();
    final userId = auth.profile?.id;
    if (userId == null) return;

    await Future.wait([
      context.read<PointsProvider>().loadUserTransactions(userId),
      auth.reloadProfile(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Points History',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        iconTheme: IconThemeData(color: colorScheme.onPrimary),
      ),
      body: Consumer2<AuthProvider, PointsProvider>(
        builder: (context, authProvider, pointsProvider, _) {
          final profile = authProvider.profile;
          final transactions = pointsProvider.transactions;

          if (pointsProvider.isLoading && transactions.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          final ledgerEntries = _buildLedgerEntries(transactions);
          final lifetimePoints =
              profile?.totalLifetimePoints ?? pointsProvider.totalEarned;

          return RefreshIndicator(
            onRefresh: _loadHistory,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _PointsSummaryCard(
                          lifetimePoints: lifetimePoints,
                          badgeName: profile?.badgeTierName ?? 'No Badge',
                          transactionCount: transactions.length,
                        ),
                        if (pointsProvider.errorMessage != null) ...[
                          const SizedBox(height: 12),
                          _MessageCard(
                            icon: Icons.error_outline,
                            title: 'Could not load points history',
                            message: pointsProvider.errorMessage!,
                            color: colorScheme.error,
                            action: TextButton.icon(
                              onPressed: _loadHistory,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Retry'),
                            ),
                          ),
                        ] else if (transactions.isEmpty) ...[
                          const SizedBox(height: 12),
                          _MessageCard(
                            icon: Icons.emoji_events_outlined,
                            title: 'No points earned yet',
                            message:
                                'Approved task completions will appear here.',
                            color: Colors.amber.shade700,
                          ),
                        ] else ...[
                          const SizedBox(height: 20),
                          Text(
                            'Achievement History',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 10),
                          ...ledgerEntries.map(
                            (entry) => _TransactionCard(entry: entry),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  List<_LedgerEntry> _buildLedgerEntries(List<PointsTransaction> transactions) {
    var runningTotal = transactions.fold<int>(
      0,
      (sum, transaction) => sum + transaction.points,
    );

    return transactions.map((transaction) {
      final entry = _LedgerEntry(
        transaction: transaction,
        runningTotal: runningTotal,
      );
      runningTotal -= transaction.points;
      return entry;
    }).toList();
  }
}

class _PointsSummaryCard extends StatelessWidget {
  final int lifetimePoints;
  final String badgeName;
  final int transactionCount;

  const _PointsSummaryCard({
    required this.lifetimePoints,
    required this.badgeName,
    required this.transactionCount,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final displayBadge = badgeName == 'No Badge'
        ? badgeName
        : '$badgeName Badge';

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: Colors.amber.shade700.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                Icons.emoji_events,
                color: Colors.amber.shade700,
                size: 30,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$lifetimePoints pts',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    displayBadge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$transactionCount achievement(s)',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurface.withValues(alpha: 0.58),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TransactionCard extends StatelessWidget {
  final _LedgerEntry entry;

  const _TransactionCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final transaction = entry.transaction;
    final formatter = DateFormat('dd MMM yyyy, h:mm a');
    final note = transaction.completionNote?.trim();
    final detailLines = [
      formatter.format(transaction.awardedAt.toLocal()),
      transaction.detailLabel,
      if (note != null && note.isNotEmpty) note,
    ];

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 10,
        ),
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.add_circle_outline, color: Colors.green),
        ),
        title: Text(
          transaction.sourceLabel,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            detailLines.join('\n'),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        trailing: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 72, maxWidth: 92),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '+${transaction.points}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${entry.runningTotal} total',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: colorScheme.onSurface.withValues(alpha: 0.58),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Color color;
  final Widget? action;

  const _MessageCard({
    required this.icon,
    required this.title,
    required this.message,
    required this.color,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Icon(icon, color: color, size: 34),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.62),
              ),
            ),
            if (action != null) ...[const SizedBox(height: 12), action!],
          ],
        ),
      ),
    );
  }
}

class _LedgerEntry {
  final PointsTransaction transaction;
  final int runningTotal;

  const _LedgerEntry({required this.transaction, required this.runningTotal});
}
