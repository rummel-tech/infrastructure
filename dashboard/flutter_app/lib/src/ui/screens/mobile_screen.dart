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
// Header summary
// ---------------------------------------------------------------------------

class _IosHeader extends StatelessWidget {
  final List<IosAppStatus> apps;
  const _IosHeader({required this.apps});

  @override
  Widget build(BuildContext context) {
    final readyCount = apps.where((a) => a.testflightReady).length;
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
                  ? 'All ${apps.length} apps ready for TestFlight'
                  : '$readyCount / ${apps.length} apps fully ready for TestFlight',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: allReady
                    ? RummelBlueColors.success500
                    : RummelBlueColors.warning500,
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
                      Text(
                        app.displayName,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        app.bundleId,
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: app.bundleIdValid
                              ? Colors.grey[500]
                              : RummelBlueColors.error500,
                        ),
                      ),
                    ],
                  ),
                ),
                _ReadinessBadge(app: app),
              ],
            ),

            // ---- Readiness checklist ----
            const SizedBox(height: 12),
            _ReadinessChecklist(app: app),

            // ---- Latest run ----
            if (latestRun != null) ...[
              const SizedBox(height: 12),
              _LatestRunRow(run: latestRun),
            ],

            const SizedBox(height: 12),

            // ---- Action buttons ----
            Row(
              children: [
                if (!app.ciConfigured) ...[
                  Expanded(
                    child: FilledButton.icon(
                      icon: const Icon(Icons.build, size: 16),
                      label: const Text('Setup CI'),
                      onPressed: app.bundleIdValid
                          ? () => _showSetupCiDialog(context, app)
                          : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.flight_takeoff, size: 16),
                    label: const Text('Deploy to TestFlight'),
                    style: app.ciConfigured
                        ? null
                        : FilledButton.styleFrom(
                            backgroundColor:
                                Theme.of(context).colorScheme.surfaceContainerHighest,
                            foregroundColor: Colors.grey[500],
                          ),
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
              Text(
                'Signing Secrets',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: Colors.grey[500], letterSpacing: 0.8),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children:
                    app.secrets.map((s) => _SecretChip(secret: s)).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showSetupCiDialog(BuildContext context, IosAppStatus app) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.build, size: 20),
            const SizedBox(width: 8),
            Text('Setup CI — ${app.displayName}'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This will commit the following files to GitHub:',
              style: TextStyle(fontSize: 13, color: Colors.grey[700]),
            ),
            const SizedBox(height: 12),
            _CiFileRow(
              icon: Icons.code,
              label: 'fastlane/Fastfile',
              repo: app.name,
              exists: app.hasFastfile,
            ),
            const SizedBox(height: 4),
            _CiFileRow(
              icon: Icons.settings,
              label: 'fastlane/Appfile',
              repo: app.name,
              exists: app.hasFastfile,
            ),
            const SizedBox(height: 4),
            _CiFileRow(
              icon: Icons.play_circle_outline,
              label: '.github/workflows/deploy-${app.name.replaceAll("_", "-")}-ios.yml',
              repo: 'infrastructure',
              exists: app.hasWorkflow,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: RummelBlueColors.primary500.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Bundle ID: ${app.bundleId}',
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.build, size: 16),
            label: const Text('Generate & Commit'),
            onPressed: () async {
              Navigator.pop(ctx);
              final provider = context.read<DashboardProvider>();
              final result = await provider.setupIosCi(app.name);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(
                    result['success'] == true
                        ? 'CI files committed for ${app.displayName}'
                        : 'Failed: ${result['error'] ?? result['fastfile']?['error'] ?? 'Unknown error'}',
                  ),
                  backgroundColor: result['success'] == true
                      ? RummelBlueColors.success500
                      : RummelBlueColors.error500,
                ));
              }
            },
          ),
        ],
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
            Text(
              'Bundle ID: ${app.bundleId}',
              style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  color: Colors.grey[500]),
            ),
            const SizedBox(height: 4),
            Text(
              'Workflow: ${app.workflowName}',
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: refCtrl,
              decoration: const InputDecoration(
                labelText: 'App branch / ref',
                hintText: 'main',
              ),
            ),
            if (!app.testflightReady && app.readinessIssues.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: RummelBlueColors.warning500.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            size: 14, color: RummelBlueColors.warning500),
                        const SizedBox(width: 6),
                        Text(
                          '${app.readinessIssues.length} issue(s) may cause failure',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: RummelBlueColors.warning500),
                        ),
                      ],
                    ),
                    for (final issue in app.readinessIssues)
                      Padding(
                        padding: const EdgeInsets.only(top: 4, left: 20),
                        child: Text('• $issue',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey[600])),
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
// Readiness checklist
// ---------------------------------------------------------------------------

class _ReadinessChecklist extends StatelessWidget {
  final IosAppStatus app;
  const _ReadinessChecklist({required this.app});

  @override
  Widget build(BuildContext context) {
    final checks = [
      _Check('Bundle ID', app.bundleIdValid),
      _Check('Workflow', app.hasWorkflow),
      _Check('Fastfile', app.hasFastfile),
      _Check('Build #', app.buildNumberSet),
      _Check('Secrets', app.secretsReady),
    ];

    return Row(
      children: checks.map((c) => Expanded(child: _CheckPill(check: c))).toList(),
    );
  }
}

class _Check {
  final String label;
  final bool passed;
  const _Check(this.label, this.passed);
}

class _CheckPill extends StatelessWidget {
  final _Check check;
  const _CheckPill({required this.check});

  @override
  Widget build(BuildContext context) {
    final color =
        check.passed ? RummelBlueColors.success500 : RummelBlueColors.error500;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Column(
        children: [
          Icon(
            check.passed ? Icons.check_circle : Icons.cancel,
            size: 14,
            color: color,
          ),
          const SizedBox(height: 2),
          Text(
            check.label,
            style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Readiness badge (header pill)
// ---------------------------------------------------------------------------

class _ReadinessBadge extends StatelessWidget {
  final IosAppStatus app;
  const _ReadinessBadge({required this.app});

  @override
  Widget build(BuildContext context) {
    if (app.testflightReady) {
      return Chip(
        label: const Text('Ready',
            style: TextStyle(fontSize: 10, color: RummelBlueColors.success500)),
        avatar: const Icon(Icons.check_circle,
            size: 14, color: RummelBlueColors.success500),
        side: const BorderSide(color: RummelBlueColors.success500),
        backgroundColor: RummelBlueColors.success500.withOpacity(0.08),
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
      );
    }
    final count = app.readinessIssues.length;
    return Chip(
      label: Text('$count issue${count == 1 ? '' : 's'}',
          style: const TextStyle(fontSize: 10, color: RummelBlueColors.warning500)),
      avatar: const Icon(Icons.warning_amber_rounded,
          size: 14, color: RummelBlueColors.warning500),
      side: const BorderSide(color: RummelBlueColors.warning500),
      backgroundColor: RummelBlueColors.warning500.withOpacity(0.08),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
    );
  }
}

// ---------------------------------------------------------------------------
// CI file row (in setup dialog)
// ---------------------------------------------------------------------------

class _CiFileRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String repo;
  final bool exists;

  const _CiFileRow({
    required this.icon,
    required this.label,
    required this.repo,
    required this.exists,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.grey[500]),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          exists ? 'update' : 'create',
          style: TextStyle(
            fontSize: 10,
            color: exists ? RummelBlueColors.warning500 : RummelBlueColors.success500,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
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
                          style:
                              TextStyle(fontSize: 11, color: Colors.grey[500])),
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
// Run tile (history sheet)
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
// Missing secrets warning
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
// Secret chip
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
// Run icon
// ---------------------------------------------------------------------------

class _RunIcon extends StatelessWidget {
  final WorkflowRun run;
  final double size;
  const _RunIcon({required this.run, required this.size});

  @override
  Widget build(BuildContext context) {
    if (run.isSuccess) {
      return Icon(Icons.check_circle,
          color: RummelBlueColors.success500, size: size);
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
