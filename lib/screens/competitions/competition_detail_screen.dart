import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/branch_leaderboard_entry.dart';
import '../../providers/auth_provider.dart';
import '../../providers/competition_provider.dart';

/// Screen displaying the real-time branch leaderboard and qualifying rules for a competition.
class CompetitionDetailScreen extends StatefulWidget {
  final String competitionId;
  const CompetitionDetailScreen({super.key, required this.competitionId});

  @override
  State<CompetitionDetailScreen> createState() => _CompetitionDetailScreenState();
}

class _CompetitionDetailScreenState extends State<CompetitionDetailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CompetitionProvider>().loadCompetitionDetail(widget.competitionId);
    });
  }

  Future<void> _recalculate() async {
    await context.read<CompetitionProvider>().recalculateLeaderboard(widget.competitionId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Leaderboard rankings recalculated!'), backgroundColor: Colors.green),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isAdmin = context.watch<AuthProvider>().profile?.isAdmin ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Competition Leaderboard',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        iconTheme: IconThemeData(color: colorScheme.onPrimary),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync),
            tooltip: 'Recalculate Rankings',
            onPressed: _recalculate,
          ),
        ],
      ),
      body: Consumer<CompetitionProvider>(
        builder: (context, provider, _) {
          final comp = provider.selectedCompetition;
          if (provider.isLoading && comp == null) {
            return const Center(child: CircularProgressIndicator());
          }

          if (comp == null) {
            return const Center(child: Text('Competition not found.'));
          }

          final dateStr =
              '${DateFormat('dd MMM yyyy').format(comp.startDate)} – ${DateFormat('dd MMM yyyy').format(comp.endDate)}';

          return RefreshIndicator(
            onRefresh: () => provider.loadCompetitionDetail(widget.competitionId),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 800),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Competition Header Card
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                colorScheme.primary,
                                colorScheme.primary.withValues(alpha: 0.8),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      comp.title,
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.onPrimary,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: colorScheme.onPrimary.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      comp.status.toUpperCase(),
                                      style: TextStyle(
                                        color: colorScheme.onPrimary,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                dateStr,
                                style: TextStyle(
                                  color: colorScheme.onPrimary.withValues(alpha: 0.85),
                                  fontSize: 13,
                                ),
                              ),
                              if (comp.description != null && comp.description!.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                Text(
                                  comp.description!,
                                  style: TextStyle(
                                    color: colorScheme.onPrimary.withValues(alpha: 0.9),
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Qualifying Products Card
                        Card(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.inventory_2_outlined, size: 18, color: colorScheme.primary),
                                    const SizedBox(width: 8),
                                    const Text(
                                      'Qualifying Products & Point Rules',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                ...comp.products.map((p) => Padding(
                                      padding: const EdgeInsets.only(bottom: 6),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            '• ${p.productName ?? 'Product'} (${p.productCategory ?? ''})',
                                            style: const TextStyle(fontWeight: FontWeight.w500),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.amber.shade100,
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              '${p.pointsPerUnit} pt(s) / unit',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.amber.shade900,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    )),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Leaderboard Section
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Live Branch Rankings',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                            TextButton.icon(
                              icon: const Icon(Icons.refresh, size: 16),
                              label: const Text('Recalculate'),
                              onPressed: _recalculate,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        if (comp.leaderboard.isEmpty)
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(32),
                              child: Center(
                                child: Column(
                                  children: [
                                    Icon(Icons.leaderboard_outlined,
                                        size: 48, color: colorScheme.onSurface.withValues(alpha: 0.3)),
                                    const SizedBox(height: 10),
                                    const Text('No sales recorded yet for participating branches.'),
                                    const SizedBox(height: 10),
                                    ElevatedButton(
                                      onPressed: _recalculate,
                                      child: const Text('Calculate Now'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          )
                        else
                          ...comp.leaderboard.map((entry) => _LeaderboardCard(entry: entry)),

                        // Admin Status Actions
                        if (isAdmin) ...[
                          const SizedBox(height: 28),
                          Card(
                            color: colorScheme.surfaceContainerHighest,
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Admin Controls', style: TextStyle(fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      if (comp.status != 'ended')
                                        Expanded(
                                          child: OutlinedButton(
                                            onPressed: () async {
                                              await provider.updateStatus(
                                                id: comp.id,
                                                status: 'ended',
                                                isActive: false,
                                              );
                                              if (mounted) {
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  const SnackBar(content: Text('Competition ended.')),
                                                );
                                              }
                                            },
                                            child: const Text('End Competition'),
                                          ),
                                        ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: ElevatedButton(
                                          onPressed: _recalculate,
                                          child: const Text('Recalculate Leaderboard'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
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
}

class _LeaderboardCard extends StatelessWidget {
  final BranchLeaderboardEntry entry;
  const _LeaderboardCard({required this.entry});

  Widget _rankIcon(int? rank) {
    if (rank == 1) {
      return Container(
        width: 36,
        height: 36,
        decoration: const BoxDecoration(color: Color(0xFFFFD700), shape: BoxShape.circle),
        child: const Icon(Icons.emoji_events, color: Colors.black87, size: 20),
      );
    }
    if (rank == 2) {
      return Container(
        width: 36,
        height: 36,
        decoration: const BoxDecoration(color: Color(0xFFC0C0C0), shape: BoxShape.circle),
        child: const Icon(Icons.emoji_events, color: Colors.black87, size: 20),
      );
    }
    if (rank == 3) {
      return Container(
        width: 36,
        height: 36,
        decoration: const BoxDecoration(color: Color(0xFFCD7F32), shape: BoxShape.circle),
        child: const Icon(Icons.emoji_events, color: Colors.white, size: 20),
      );
    }
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(color: Colors.grey.shade200, shape: BoxShape.circle),
      child: Center(
        child: Text(
          '#${rank ?? '-'}',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
      ),
    );
  }

  Widget _movementBadge(int movement) {
    if (movement > 0) {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.arrow_upward, size: 14, color: Colors.green),
          Text('Up', style: TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.bold)),
        ],
      );
    }
    if (movement < 0) {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.arrow_downward, size: 14, color: Colors.red),
          Text('Down', style: TextStyle(fontSize: 10, color: Colors.red, fontWeight: FontWeight.bold)),
        ],
      );
    }
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            _rankIcon(entry.currentRank),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          entry.branchName ?? 'Branch',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ),
                      _movementBadge(entry.rankMovement),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${entry.totalQualifyingQty} qualifying units sold',
                    style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.6)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${entry.totalCompetitionPoints}',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: cs.primary),
                ),
                const Text('points', style: TextStyle(fontSize: 11)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
