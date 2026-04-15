import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rummel_blue_theme/rummel_blue_theme.dart';

import '../../models/ios_status.dart';
import '../../models/workflow_run.dart';
import '../../providers/dashboard_provider.dart';
import '../widgets/status_badge.dart';

class MobileScreen extends StatelessWidget {
  const MobileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DashboardProvider>();
    final apps = provider.iosApps;

    return RefreshIndicator(
      onRefresh: () => provider.loadIosStatus(),
      child: apps.isEmpty
          ? const Center(child: Text('No iOS app data available'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _IosHeader(apps: apps),
                const SizedBox(height: 16),
                for (final app in apps) ...[
                  _AppCard(app: app),
                  const SizedBox(height: 12),
                ],
              ],
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header summary row
// ---------------------------------------------------------------------------

class _IosHeader extends StatelessWidget {
  final List<IosAppStatus> apps;
  const _IosHeader({required this.apps});

  @override
  Widget build(BuildContext context) {
    final readyCount = apps.where((a) => a.secretsReady).length;
    final allReady = readyCount == apps.length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: allReady
            ? RummelBlueColors.success500.withOpacity(0.1)
            : RummelBlueColors.warning500.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: allReady ? RummelBlueColors.success500 : RummelBlueColors.warning500,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            allReady ? Icons.check_circle : Icons.warning_amber_rounded,
            color: allReady ? RummelBlueColors.success500 : RummelBlueColors.warning500,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              allReady
                  ? 'All ${ apps.length} apps ready for TestFlight'
                  : '$readyCount / ${apps.length} apps have signing secrets configured',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: allReady ? RummelBlueColors.success500 : RummelBlueColors.warning500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Per-app card
// ---------------------------------------------------------------------------

class _AppCard extends StatelessWidget {
  final IosAppStatus app;
  const _AppCard({required this.app});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final latestRun = app.latestRun;

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ---- App header ----
            Row(
              children: [
                const Icon(Icons.phone_iphone, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(app.displayName,
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      Text(app.bundleId,
                          style: TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                              color: Colors.grey[500])),
                    ],
                  ),
                ),
                _SecretsBadge(app: app),
              ],
            ),

            const SizedBox(height: 12),

            // ---- Latest run status ----
            if (latestRun != null) ...[
              _LatestRunRow(run: latestRun),
              const SizedBox(height: 12),
            ],

            // ---- Action buttons ----
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.flight_takeoff, size: 16),
                    label: const Text('Deploy to TestFlight'),
                    onPressed: app.workflowId == null
                        ? null
                        : () => _showDeployDialog(context, app),
                  ),
                ),
                if (app.recentRuns.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.history, size: 16),
                    label: const Text('History'),
                    onPressed: () => _showHistorySheet(context, app),
                  ),
                ],
              ],
            ),

            // ---- Missing secrets warning ----
            if (app.missingSecrets.isNotEmpty) ...[
              const SizedBox(height: 12),
              _MissingSecretsWarning(missing: app.missingSecrets),
            ],

            // ---- Secrets checklist ----
            if (app.secrets.isNotEmpty &&
                app.secrets.any((s) => s.present != null)) ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Text('Signing Secrets',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: Colors.grey[500], letterSpacing: 0.8)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: app.secrets.map((s) => _SecretChip(secret: s)).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showDeployDialog(BuildContext context, IosAppStatus app) {
    final refCtrl = TextEditingController(text: 'main');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.flight_takeoff, size: 20),
            const SizedBox(width: 8),
            Text('Deploy ${app.displayName}'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Bundle ID: ${app.bundleId}',
                style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    color: Colors.grey[500])),
            const SizedBox(height: 4),
            Text('Workflow: ${app.workflowName}',
                style: TextStyle(fontSize: 12, color: Colors.grey[500])),
            const SizedBox(height: 16),
            TextField(
              controller: refCtrl,
              decoration: const InputDecoration(
                labelText: 'App branch / ref',
                hintText: 'main',
              ),
            ),
            if (!app.secretsReady) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: RummelBlueColors.warning500.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        size: 16, color: RummelBlueColors.warning500),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${app.missingSecrets.length} signing secret(s) missing — build may fail',
                        style: TextStyle(
                            fontSize: 12, color: RummelBlueColors.warning500),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.flight_takeoff, size: 16),
            label: const Text('Deploy'),
            onPressed: () async {
              final ref =
                  refCtrl.text.trim().isEmpty ? 'main' : refCtrl.text.trim();
              Navigator.pop(ctx);
              final provider = context.read<DashboardProvider>();
              final result =
                  await provider.triggerIosDeploy(app.name, ref: ref);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(result['success'] == true
                      ? 'TestFlight build triggered for ${app.displayName}'
                      : 'Failed: ${result['error'] ?? 'Unknown error'}'),
                  backgroundColor: result['success'] == true
                      ? RummelBlueColors.success500
                      : RummelBlueColors.error500,
                ));
              }
              if (result['success'] == true) {
                await Future.delayed(const Duration(seconds: 3));
                if (context.mounted) {
                  context.read<DashboardProvider>().loadIosStatus();
                }
              }
            },
          ),
        ],
      ),
    );
  }

  void _showHistorySheet(BuildContext context, IosAppStatus app) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.55,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        expand: false,
        builder: (_, scrollCtrl) => Column(
          children: [
            const SizedBox(height: 8),
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Icon(Icons.history, size: 18),
                  const SizedBox(width: 8),
                  Text('${app.displayName} — Recent iOS Builds',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.separated(
                controller: scrollCtrl,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: app.recentRuns.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) => _RunTile(run: app.recentRuns[i]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Latest run row
// ---------------------------------------------------------------------------

class _LatestRunRow extends StatelessWidget {
  final WorkflowRun run;
  const _LatestRunRow({required this.run});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          _RunIcon(run: run, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Latest: ${run.displayTitle}',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Row(
                  children: [
                    Icon(Icons.commit, size: 11, color: Colors.grey[500]),
                    const SizedBox(width: 3),
                    Text(run.sha,
                        style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            color: Colors.grey[500])),
                    if (run.duration.isNotEmpty) ...[
                      const SizedBox(width: 10),
                      Icon(Icons.timer_outlined,
                          size: 11, color: Colors.grey[500]),
                      const SizedBox(width: 3),
                      Text(run.duration,
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey[500])),
                    ],
                  ],
                ),
              ],
            ),
          ),
          StatusBadge(status: run.conclusion ?? run.status),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Run tile for history sheet
// ---------------------------------------------------------------------------

class _RunTile extends StatelessWidget {
  final WorkflowRun run;
  const _RunTile({required this.run});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: _RunIcon(run: run, size: 22),
      title: Text(run.displayTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      subtitle: Row(
        children: [
          Icon(Icons.commit, size: 12, color: Colors.grey[500]),
          const SizedBox(width: 3),
          Text(run.sha,
              style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: Colors.grey[500])),
          if (run.duration.isNotEmpty) ...[
            const SizedBox(width: 10),
            Icon(Icons.timer_outlined, size: 12, color: Colors.grey[500]),
            const SizedBox(width: 3),
            Text(run.duration,
                style: TextStyle(fontSize: 11, color: Colors.grey[500])),
          ],
        ],
      ),
      trailing: StatusBadge(status: run.conclusion ?? run.status),
    );
  }
}

// ---------------------------------------------------------------------------
// Secrets badge (compact pill on card header)
// ---------------------------------------------------------------------------

class _SecretsBadge extends StatelessWidget {
  final IosAppStatus app;
  const _SecretsBadge({required this.app});

  @override
  Widget build(BuildContext context) {
    // If secrets API was unavailable, all present == null
    if (app.secrets.every((s) => s.present == null)) {
      return Chip(
        label: const Text('Secrets unknown',
            style: TextStyle(fontSize: 10)),
        avatar: const Icon(Icons.help_outline, size: 14),
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
      );
    }
    if (app.secretsReady) {
      return Chip(
        label: const Text('Signing ready',
            style: TextStyle(fontSize: 10, color: RummelBlueColors.success500)),
        avatar: const Icon(Icons.check_circle, size: 14,
            color: RummelBlueColors.success500),
        side: const BorderSide(color: RummelBlueColors.success500),
        backgroundColor: RummelBlueColors.success500.withOpacity(0.08),
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
      );
    }
    return Chip(
      label: Text('${app.missingSecrets.length} missing',
          style: const TextStyle(fontSize: 10, color: RummelBlueColors.error500)),
      avatar: const Icon(Icons.error_outline, size: 14,
          color: RummelBlueColors.error500),
      side: const BorderSide(color: RummelBlueColors.error500),
      backgroundColor: RummelBlueColors.error500.withOpacity(0.08),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
    );
  }
}

// ---------------------------------------------------------------------------
// Missing secrets warning box
// ---------------------------------------------------------------------------

class _MissingSecretsWarning extends StatelessWidget {
  final List<String> missing;
  const _MissingSecretsWarning({required this.missing});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: RummelBlueColors.error500.withOpacity(0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: RummelBlueColors.error500.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.error_outline,
                  size: 14, color: RummelBlueColors.error500),
              const SizedBox(width: 6),
              const Text('Missing GitHub Actions secrets:',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: RummelBlueColors.error500)),
            ],
          ),
          const SizedBox(height: 6),
          for (final s in missing)
            Padding(
              padding: const EdgeInsets.only(left: 20, bottom: 2),
              child: Text('• $s',
                  style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: Colors.grey[600])),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Individual secret chip
// ---------------------------------------------------------------------------

class _SecretChip extends StatelessWidget {
  final IosSecretStatus secret;
  const _SecretChip({required this.secret});

  @override
  Widget build(BuildContext context) {
    final present = secret.present;
    final color = present == null
        ? Colors.grey
        : present
            ? RummelBlueColors.success500
            : RummelBlueColors.error500;
    final icon = present == null
        ? Icons.help_outline
        : present
            ? Icons.check
            : Icons.close;
    return Chip(
      label: Text(secret.name, style: TextStyle(fontSize: 10, color: color)),
      avatar: Icon(icon, size: 12, color: color),
      side: BorderSide(color: color.withOpacity(0.5)),
      backgroundColor: color.withOpacity(0.06),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

// ---------------------------------------------------------------------------
// Run icon helper
// ---------------------------------------------------------------------------

class _RunIcon extends StatelessWidget {
  final WorkflowRun run;
  final double size;
  const _RunIcon({required this.run, required this.size});

  @override
  Widget build(BuildContext context) {
    if (run.isSuccess) {
      return Icon(Icons.check_circle, color: RummelBlueColors.success500, size: size);
    }
    if (run.isFailure) {
      return Icon(Icons.cancel, color: RummelBlueColors.error500, size: size);
    }
    if (run.isRunning) {
      return SizedBox(
        width: size,
        height: size,
        child: CircularProgressIndicator(
            strokeWidth: 2, color: RummelBlueColors.primary500),
      );
    }
    return Icon(Icons.circle_outlined, color: Colors.grey[500], size: size);
  }
}
