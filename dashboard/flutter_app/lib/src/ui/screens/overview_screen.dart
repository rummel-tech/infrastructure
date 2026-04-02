import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rummel_blue_theme/rummel_blue_theme.dart';

import '../../providers/dashboard_provider.dart';
import '../widgets/stat_card.dart';
import '../widgets/status_badge.dart';

class OverviewScreen extends StatelessWidget {
  const OverviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DashboardProvider>();

    if (provider.loading && provider.services.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final healthy = provider.services.where((s) => s.isHealthy).length;
    final degraded = provider.services.where((s) => s.isDegraded).length;
    final down = provider.services.where((s) => s.isDown).length;
    final successRuns = provider.runs.where((r) => r.isSuccess).length;
    final catalog = provider.catalogSummary;

    return RefreshIndicator(
      onRefresh: () => provider.loadAll(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Text(
                '${provider.environment.toUpperCase()} Environment',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      letterSpacing: 1.2,
                    ),
              ),
              const Spacer(),
              if (provider.githubOrg.isNotEmpty)
                Text(provider.githubOrg,
                    style: TextStyle(fontSize: 12, color: Colors.grey[500])),
            ],
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: StatCard(
                  label: 'Flutter Apps',
                  value: '${catalog?.totalFlutterApps ?? provider.flutterApps.length}',
                  detail: '${catalog?.appsWithBackend ?? 0} full-stack, ${catalog?.appsStandalone ?? 0} standalone',
                  icon: Icons.phone_iphone,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StatCard(
                  label: 'Backend Services',
                  value: '${catalog?.totalBackendServices ?? provider.services.length}',
                  detail: '$healthy healthy, $degraded degraded, $down down',
                  icon: Icons.dns,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: StatCard(
                  label: 'Secrets',
                  value: '${provider.secrets.length}',
                  detail: provider.environment,
                  icon: Icons.key,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StatCard(
                  label: 'Builds',
                  value: provider.runs.isNotEmpty
                      ? '$successRuns/${provider.runs.length}'
                      : '-',
                  detail: 'passed / total',
                  icon: Icons.rocket_launch,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: StatCard(
                  label: 'Shared Packages',
                  value: '${catalog?.totalSharedPackages ?? provider.sharedPackages.length}',
                  detail: 'Dart + Python libraries',
                  icon: Icons.inventory_2,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StatCard(
                  label: 'Repositories',
                  value: '${catalog?.totalRepos ?? provider.repos.length}',
                  detail: 'Across GitHub org',
                  icon: Icons.source,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: StatCard(
                  label: '30-Day Cost',
                  value: provider.serviceCostsTotal > 0
                      ? '\$${provider.serviceCostsTotal.toStringAsFixed(2)}'
                      : '--',
                  detail: provider.forecast != null
                      ? 'Forecast: \$${provider.forecast!.forecastedAmount.toStringAsFixed(2)}'
                      : 'AWS Cost Explorer',
                  icon: Icons.attach_money,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StatCard(
                  label: 'Alarms',
                  value: provider.resourceSummary != null
                      ? '${provider.resourceSummary!.alarmsTotal}'
                      : '${provider.alarms.length}',
                  detail: provider.alarms.any((a) => a.isFiring)
                      ? '${provider.alarms.where((a) => a.isFiring).length} firing'
                      : 'All OK',
                  icon: Icons.notifications_active,
                ),
              ),
            ],
          ),

          // Test coverage
          if (catalog != null) ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Backend Test Coverage',
                        style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 12),
                    _CoverageBar(
                      label: 'Services with tests',
                      covered: catalog.servicesWithTests,
                      total: catalog.totalBackendServices,
                    ),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 24),

          Text('Service Health',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                for (final svc in provider.services) ...[
                  ListTile(
                    dense: true,
                    leading: Icon(
                      svc.isHealthy
                          ? Icons.check_circle
                          : svc.isDegraded
                              ? Icons.warning
                              : Icons.error,
                      color: svc.isHealthy
                          ? RummelBlueColors.success500
                          : svc.isDegraded
                              ? RummelBlueColors.warning500
                              : RummelBlueColors.error500,
                      size: 20,
                    ),
                    title: Text(svc.name,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('Port ${svc.port}'),
                    trailing: StatusBadge(status: svc.status),
                  ),
                  if (svc != provider.services.last) const Divider(height: 1),
                ],
                if (provider.services.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('No service data available',
                        style: TextStyle(color: Colors.grey)),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          Text('Recent Builds',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                for (final run in provider.runs.take(5)) ...[
                  ListTile(
                    dense: true,
                    leading: Icon(
                      run.isSuccess
                          ? Icons.check_circle
                          : run.isFailure
                              ? Icons.cancel
                              : run.isRunning
                                  ? Icons.pending
                                  : Icons.circle_outlined,
                      color: run.isSuccess
                          ? RummelBlueColors.success500
                          : run.isFailure
                              ? RummelBlueColors.error500
                              : run.isRunning
                                  ? RummelBlueColors.primary500
                                  : Colors.grey,
                      size: 20,
                    ),
                    title: Text(
                      run.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    subtitle: Text('${run.branch} · ${run.sha} · ${run.duration}'),
                    trailing: StatusBadge(status: run.conclusion ?? run.status),
                  ),
                  if (run != provider.runs.take(5).last) const Divider(height: 1),
                ],
                if (provider.runs.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('No build data available',
                        style: TextStyle(color: Colors.grey)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CoverageBar extends StatelessWidget {
  final String label;
  final int covered;
  final int total;
  const _CoverageBar({
    required this.label,
    required this.covered,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final pct = total > 0 ? covered / total : 0.0;
    final color = pct >= 0.8
        ? RummelBlueColors.success500
        : pct >= 0.5
            ? RummelBlueColors.warning500
            : RummelBlueColors.error500;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
            Text('$covered / $total',
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600, color: color)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 6,
            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            color: color,
          ),
        ),
      ],
    );
  }
}
