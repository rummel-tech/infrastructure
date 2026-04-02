import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rummel_blue_theme/rummel_blue_theme.dart';

import '../../providers/dashboard_provider.dart';
import '../widgets/status_badge.dart';

class ServicesScreen extends StatelessWidget {
  const ServicesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DashboardProvider>();
    final services = provider.services;

    return RefreshIndicator(
      onRefresh: () => provider.loadServices(),
      child: services.isEmpty
          ? const Center(child: Text('No service data available'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Builder(builder: (context) {
                  final t = Theme.of(context);
                  return Text(
                    provider.cluster.isNotEmpty
                        ? provider.cluster
                        : '${provider.environment}-cluster',
                    style: t.textTheme.titleSmall?.copyWith(
                        color: t.colorScheme.primary,
                        letterSpacing: 1.0),
                  );
                }),
                const SizedBox(height: 16),
                for (final svc in services)
                  _ServiceCard(service: svc),
              ],
            ),
    );
  }
}

class _ServiceCard extends StatelessWidget {
  final dynamic service;
  const _ServiceCard({required this.service});

  @override
  Widget build(BuildContext context) {
    final statusColor = service.isHealthy
        ? RummelBlueColors.success500
        : service.isDegraded
            ? RummelBlueColors.warning500
            : service.isDown
                ? RummelBlueColors.error500
                : Colors.grey;

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
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Text(service.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
                const Spacer(),
                StatusBadge(status: service.status),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _InfoChip(
                    icon: Icons.language, label: 'Port ${service.port}'),
                const SizedBox(width: 12),
                _InfoChip(
                  icon: Icons.memory,
                  label:
                      'Tasks ${service.runningCount}/${service.desiredCount}',
                ),
                const SizedBox(width: 12),
                _InfoChip(
                  icon: Icons.cloud,
                  label: service.environment,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.article_outlined, size: 16),
                  label: const Text('Logs'),
                  onPressed: () => _showLogs(context),
                  style: TextButton.styleFrom(
                    textStyle: const TextStyle(fontSize: 12),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  icon: const Icon(Icons.info_outline, size: 16),
                  label: const Text('Tasks'),
                  onPressed: () => _showTasks(context),
                  style: TextButton.styleFrom(
                    textStyle: const TextStyle(fontSize: 12),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showLogs(BuildContext context) async {
    final provider = context.read<DashboardProvider>();
    final data = await provider.getServiceLogs(service.name);
    if (!context.mounted) return;

    final logs = (data['logs'] as List?) ?? [];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${service.name} Logs',
            style: const TextStyle(fontSize: 16)),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: logs.isEmpty
              ? const Center(child: Text('No logs available'))
              : ListView.builder(
                  itemCount: logs.length,
                  itemBuilder: (_, i) {
                    final log = logs[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        log['message']?.toString() ?? '',
                        style: const TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          height: 1.4,
                        ),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showTasks(BuildContext context) async {
    final provider = context.read<DashboardProvider>();
    final data = await provider.getServiceTasks(service.name);
    if (!context.mounted) return;

    final tasks = (data['tasks'] as List?) ?? [];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${service.name} Tasks',
            style: const TextStyle(fontSize: 16)),
        content: SizedBox(
          width: double.maxFinite,
          child: tasks.isEmpty
              ? const Text('No tasks running')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: tasks.length,
                  itemBuilder: (_, i) {
                    final task = tasks[i];
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  task['task_arn']?.toString() ?? '',
                                  style: const TextStyle(
                                      fontSize: 12, fontFamily: 'monospace'),
                                ),
                                const Spacer(),
                                StatusBadge(
                                    status: task['status']?.toString() ?? 'unknown'),
                              ],
                            ),
                            if (task['cpu'] != null || task['memory'] != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  'CPU: ${task['cpu']} · Memory: ${task['memory']}',
                                  style: TextStyle(
                                      fontSize: 11, color: Colors.grey[500]),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.grey[500]),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(fontSize: 12, color: Colors.grey[400])),
      ],
    );
  }
}
