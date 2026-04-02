import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rummel_blue_theme/rummel_blue_theme.dart';

import '../../providers/dashboard_provider.dart';
import '../widgets/stat_card.dart';
import '../widgets/status_badge.dart';

class InfraScreen extends StatelessWidget {
  const InfraScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DashboardProvider>();
    final summary = provider.resourceSummary;
    final alarms = provider.alarms;
    final theme = Theme.of(context);

    return RefreshIndicator(
      onRefresh: () => provider.loadInfrastructureSummary(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '${provider.environment.toUpperCase()} Resources',
            style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary, letterSpacing: 1.2),
          ),
          const SizedBox(height: 16),

          // Summary cards
          Row(
            children: [
              Expanded(
                child: StatCard(
                  label: 'Databases',
                  value: '${summary?.databases.length ?? 0}',
                  detail: summary?.databases.isNotEmpty == true
                      ? summary!.databases.first.engine
                      : 'RDS PostgreSQL',
                  icon: Icons.storage,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StatCard(
                  label: 'Load Balancers',
                  value: '${summary?.loadBalancers.length ?? 0}',
                  detail: 'Application LB',
                  icon: Icons.swap_horiz,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: StatCard(
                  label: 'CDN Distributions',
                  value: '${summary?.cloudfrontDistributions ?? provider.cdnDistributions.length}',
                  detail: 'CloudFront',
                  icon: Icons.public,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _AlarmCard(
                  total: summary?.alarmsTotal ?? alarms.length,
                  ok: summary?.alarmsOk ?? alarms.where((a) => a.isOk).length,
                  firing: summary?.alarmsFiring ?? alarms.where((a) => a.isFiring).length,
                ),
              ),
            ],
          ),

          // Database details
          if (summary != null && summary.databases.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text('Databases', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            for (final db in summary.databases) _RdsCard(db: db),
          ],

          // Load balancers
          if (summary != null && summary.loadBalancers.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text('Load Balancers', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            for (final lb in summary.loadBalancers) _AlbCard(lb: lb),
          ],

          // CloudFront distributions
          if (provider.cdnDistributions.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text('CDN Distributions', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            Card(
              child: Column(
                children: [
                  for (var i = 0; i < provider.cdnDistributions.length; i++) ...[
                    ListTile(
                      dense: true,
                      leading: Icon(
                        provider.cdnDistributions[i].enabled
                            ? Icons.check_circle
                            : Icons.pause_circle,
                        color: provider.cdnDistributions[i].enabled
                            ? RummelBlueColors.success500
                            : Colors.grey,
                        size: 20,
                      ),
                      title: Text(
                        provider.cdnDistributions[i].aliases.isNotEmpty
                            ? provider.cdnDistributions[i].aliases.first
                            : provider.cdnDistributions[i].domain,
                        style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                      ),
                      subtitle: Text(provider.cdnDistributions[i].origin,
                          style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                      trailing: StatusBadge(status: provider.cdnDistributions[i].status.toLowerCase()),
                    ),
                    if (i < provider.cdnDistributions.length - 1)
                      const Divider(height: 1),
                  ],
                ],
              ),
            ),
          ],

          // Alarms
          if (alarms.isNotEmpty) ...[
            const SizedBox(height: 24),
            Row(
              children: [
                Text('CloudWatch Alarms', style: theme.textTheme.titleMedium),
                const Spacer(),
                Text('${alarms.where((a) => a.isFiring).length} firing',
                    style: TextStyle(
                      fontSize: 12,
                      color: alarms.any((a) => a.isFiring)
                          ? RummelBlueColors.error500
                          : Colors.grey[500],
                    )),
              ],
            ),
            const SizedBox(height: 12),
            Card(
              child: Column(
                children: [
                  for (var i = 0; i < alarms.length; i++) ...[
                    ListTile(
                      dense: true,
                      leading: Icon(
                        alarms[i].isFiring
                            ? Icons.error
                            : alarms[i].isOk
                                ? Icons.check_circle
                                : Icons.help_outline,
                        color: alarms[i].isFiring
                            ? RummelBlueColors.error500
                            : alarms[i].isOk
                                ? RummelBlueColors.success500
                                : Colors.grey,
                        size: 18,
                      ),
                      title: Text(alarms[i].name,
                          style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
                      subtitle: Text('${alarms[i].namespace} / ${alarms[i].metric}',
                          style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                      trailing: StatusBadge(status: alarms[i].state.toLowerCase()),
                    ),
                    if (i < alarms.length - 1) const Divider(height: 1),
                  ],
                ],
              ),
            ),
          ],

          // Empty state
          if (summary == null && alarms.isEmpty)
            const Padding(
              padding: EdgeInsets.all(48),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.cloud_off, size: 48, color: Colors.grey),
                    SizedBox(height: 16),
                    Text('No infrastructure data available',
                        style: TextStyle(color: Colors.grey)),
                    SizedBox(height: 8),
                    Text('Connect AWS credentials to view resources',
                        style: TextStyle(color: Colors.grey, fontSize: 12)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AlarmCard extends StatelessWidget {
  final int total;
  final int ok;
  final int firing;
  const _AlarmCard({required this.total, required this.ok, required this.firing});

  @override
  Widget build(BuildContext context) {
    final color = firing > 0 ? RummelBlueColors.error500 : RummelBlueColors.success500;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.notifications_active, size: 16,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 6),
                Text('Alarms',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Colors.grey[500], letterSpacing: 0.5)),
              ],
            ),
            const SizedBox(height: 8),
            Text('$total', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 4),
                Text(
                  firing > 0 ? '$firing firing, $ok ok' : 'All OK',
                  style: TextStyle(fontSize: 11, color: color),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RdsCard extends StatelessWidget {
  final dynamic db;
  const _RdsCard({required this.db});

  @override
  Widget build(BuildContext context) {
    final statusColor = db.isAvailable ? RummelBlueColors.success500 : RummelBlueColors.warning500;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: statusColor.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.storage, size: 20, color: statusColor),
                const SizedBox(width: 8),
                Text(db.identifier,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const Spacer(),
                StatusBadge(status: db.isAvailable ? 'healthy' : db.status),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _InfoItem(label: 'Engine', value: db.engine),
                _InfoItem(label: 'Class', value: db.instanceClass),
                _InfoItem(label: 'Storage', value: '${db.storageGb} / ${db.maxStorageGb} GB'),
                _InfoItem(label: 'Type', value: db.storageType),
                _InfoItem(label: 'Multi-AZ', value: db.multiAz ? 'Yes' : 'No'),
                _InfoItem(label: 'Backup', value: '${db.backupRetention} days'),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _BoolChip(label: 'Encrypted', value: db.encrypted),
                const SizedBox(width: 8),
                _BoolChip(label: 'Perf Insights', value: db.performanceInsights),
                const SizedBox(width: 8),
                _BoolChip(label: 'Delete Protect', value: db.deletionProtection),
              ],
            ),
            if (db.endpoint.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '${db.endpoint}:${db.port}',
                style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.grey[500]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AlbCard extends StatelessWidget {
  final dynamic lb;
  const _AlbCard({required this.lb});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.swap_horiz, size: 20, color: RummelBlueColors.primary500),
                const SizedBox(width: 8),
                Text(lb.name,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const Spacer(),
                StatusBadge(status: lb.state == 'active' ? 'healthy' : lb.state),
              ],
            ),
            const SizedBox(height: 8),
            Text(lb.dnsName,
                style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.grey[500])),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              children: [
                _InfoItem(label: 'Scheme', value: lb.scheme),
                _InfoItem(label: 'Type', value: lb.type),
                _InfoItem(label: 'AZs', value: lb.azs.join(', ')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoItem extends StatelessWidget {
  final String label;
  final String value;
  const _InfoItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[500])),
        Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
      ],
    );
  }
}

class _BoolChip extends StatelessWidget {
  final String label;
  final bool value;
  const _BoolChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final color = value ? RummelBlueColors.success500 : Colors.grey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(value ? Icons.check : Icons.close, size: 12, color: color),
          const SizedBox(width: 3),
          Text(label, style: TextStyle(fontSize: 10, color: color)),
        ],
      ),
    );
  }
}
