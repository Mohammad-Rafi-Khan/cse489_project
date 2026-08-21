import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/competition_provider.dart';
import '../../widgets/empty_state.dart';

/// Screen listing active, upcoming, and past inter-branch product competitions.
class CompetitionListScreen extends StatefulWidget {
  const CompetitionListScreen({super.key});

  @override
  State<CompetitionListScreen> createState() => _CompetitionListScreenState();
}

class _CompetitionListScreenState extends State<CompetitionListScreen> {
  String _filter = 'active'; // 'active' | 'all'

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CompetitionProvider>().loadCompetitions();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isAdmin = context.watch<AuthProvider>().profile?.isAdmin ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Branch Competitions',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        iconTheme: IconThemeData(color: colorScheme.onPrimary),
      ),
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  ChoiceChip(
                    label: const Text('Active Challenges'),
                    selected: _filter == 'active',
                    onSelected: (_) => setState(() => _filter = 'active'),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('All Competitions'),
                    selected: _filter == 'all',
                    onSelected: (_) => setState(() => _filter = 'all'),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Consumer<CompetitionProvider>(
              builder: (context, provider, _) {
                if (provider.isLoading && provider.competitions.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }

                var list = provider.competitions;
                if (_filter == 'active') {
                  list = provider.activeCompetitions;
                }

                if (list.isEmpty) {
                  return EmptyState(
                    icon: Icons.emoji_events_outlined,
                    title: _filter == 'active' ? 'No Active Competitions' : 'No Competitions Found',
                    subtitle: isAdmin
                        ? 'Create a new competition challenge to drive store performance!'
                        : 'Check back soon for new branch challenges.',
                    action: isAdmin
                        ? ElevatedButton.icon(
                            icon: const Icon(Icons.add),
                            label: const Text('Create Competition'),
                            onPressed: () => Navigator.pushNamed(context, '/competition-form')
                                .then((_) => provider.loadCompetitions()),
                          )
                        : null,
                  );
                }

                return RefreshIndicator(
                  onRefresh: () => provider.loadCompetitions(),
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: list.length,
                    itemBuilder: (context, index) {
                      final comp = list[index];
                      final dateStr =
                          '${DateFormat('dd MMM').format(comp.startDate)} – ${DateFormat('dd MMM yyyy').format(comp.endDate)}';

                      return Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 760),
                          child: Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 44,
                                        height: 44,
                                        decoration: BoxDecoration(
                                          color: colorScheme.primaryContainer,
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Icon(Icons.emoji_events, color: colorScheme.primary, size: 24),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              comp.title,
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              dateStr,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: colorScheme.onSurface.withValues(alpha: 0.6),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: comp.isActiveStatus
                                              ? Colors.green.withValues(alpha: 0.12)
                                              : Colors.grey.withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          comp.status.toUpperCase(),
                                          style: TextStyle(
                                            color: comp.isActiveStatus ? Colors.green : Colors.grey,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (comp.description != null && comp.description!.isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    Text(
                                      comp.description!,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: colorScheme.onSurface.withValues(alpha: 0.75),
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 12,
                                    runSpacing: 6,
                                    children: [
                                      _BadgeText(
                                        icon: Icons.store_outlined,
                                        text: '${comp.branches.length} Branches',
                                        color: Colors.teal,
                                      ),
                                      _BadgeText(
                                        icon: Icons.inventory_2_outlined,
                                        text: '${comp.products.length} Products',
                                        color: Colors.indigo,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 14),
                                  SizedBox(
                                    width: double.infinity,
                                    child: OutlinedButton.icon(
                                      icon: const Icon(Icons.leaderboard_outlined),
                                      label: const Text('View Live Leaderboard'),
                                      onPressed: () {
                                        Navigator.pushNamed(
                                          context,
                                          '/competition-detail',
                                          arguments: comp.id,
                                        ).then((_) => provider.loadCompetitions());
                                      },
                                    ),
                                  ),
                                ],
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
      floatingActionButton: isAdmin
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.pushNamed(context, '/competition-form')
                  .then((_) => context.read<CompetitionProvider>().loadCompetitions()),
              icon: const Icon(Icons.add),
              label: const Text('New Competition'),
            )
          : null,
    );
  }
}

class _BadgeText extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _BadgeText({required this.icon, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
        ),
      ],
    );
  }
}
