import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rummel_blue_theme/rummel_blue_theme.dart';

import '../../providers/dashboard_provider.dart';
import '../widgets/status_badge.dart';

class BuildsScreen extends StatefulWidget {
  const BuildsScreen({super.key});

  @override
  State<BuildsScreen> createState() => _BuildsScreenState();
}

class _BuildsScreenState extends State<BuildsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      final provider = context.read<DashboardProvider>();
      final repos = provider.repos;
      _tabController = TabController(
          length: repos.isEmpty ? 1 : repos.length, vsync: this);
      _tabController.addListener(() {
        if (!_tabController.indexIsChanging && repos.isNotEmpty) {
          provider.loadRuns(repo: repos[_tabController.index]);
          provider.loadWorkflows(repo: repos[_tabController.index]);
        }
      });
      if (repos.isNotEmpty) {
        provider.loadWorkflows(repo: repos.first);
      }
      _initialized = true;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DashboardProvider>();
    final repos = provider.repos;
    final runs = provider.runs;
    final workflows = provider.workflows;

    final successCount = runs.where((r) => r.isSuccess).length;
    final failCount = runs.where((r) => r.isFailure).length;
    final runningCount = runs.where((r) => r.isRunning).length;
    final rate = runs.isNotEmpty
        ? (successCount / runs.length * 100).round()
        : 0;

    return Column(
      children: [
        if (repos.length > 1)
          TabBar(
            controller: _tabController,
            tabs: repos.map((r) => Tab(text: r)).toList(),
          ),

        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              _MiniStat(label: 'Total', value: '${runs.length}', color: Colors.grey),
              const SizedBox(width: 8),
              _MiniStat(label: 'Pass', value: '$successCount', color: RummelBlueColors.success500),
              const SizedBox(width: 8),
              _MiniStat(label: 'Fail', value: '$failCount', color: RummelBlueColors.error500),
              const SizedBox(width: 8),
              _MiniStat(label: 'Running', value: '$runningCount', color: RummelBlueColors.primary500),
              const SizedBox(width: 8),
              _MiniStat(label: 'Rate', value: '$rate%', color: rate >= 80 ? RummelBlueColors.success500 : RummelBlueColors.warning500),
            ],
          ),
        ),

        // Trigger workflow button
        if (workflows.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.play_arrow, size: 18),
                label: const Text('Trigger Workflow'),
                onPressed: () => _showTriggerDialog(context, provider, repos),
              ),
            ),
          ),

        const SizedBox(height: 8),

        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              final repo = repos.isNotEmpty
                  ? repos[_tabController.index]
                  : 'services';
              await provider.loadRuns(repo: repo);
            },
            child: runs.isEmpty
                ? const Center(child: Text('No build data available'))
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: runs.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final run = runs[i];
                      return _RunTile(
                        run: run,
                        repo: repos.isNotEmpty
                            ? repos[_tabController.index]
                            : 'services',
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  void _showTriggerDialog(BuildContext context, DashboardProvider provider, List<String> repos) {
    final workflows = provider.workflows;
    int? selectedWorkflow = workflows.isNotEmpty ? workflows.first.id : null;
    String ref = 'main';
    final refCtrl = TextEditingController(text: ref);
    final repo = repos.isNotEmpty ? repos[_tabController.index] : 'services';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Trigger Workflow'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Repository: $repo',
                  style: TextStyle(fontSize: 12, color: Colors.grey[500])),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: selectedWorkflow,
                decoration: const InputDecoration(labelText: 'Workflow'),
                items: workflows
                    .map((w) => DropdownMenuItem(value: w.id, child: Text(w.name)))
                    .toList(),
                onChanged: (v) => selectedWorkflow = v,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: refCtrl,
                decoration: const InputDecoration(
                  labelText: 'Branch / Ref',
                  hintText: 'main',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.play_arrow, size: 18),
            label: const Text('Trigger'),
            onPressed: () async {
              if (selectedWorkflow == null) return;
              final result = await provider.triggerWorkflow(
                repo,
                selectedWorkflow!,
                ref: refCtrl.text.isNotEmpty ? refCtrl.text : 'main',
              );
              if (ctx.mounted) Navigator.pop(ctx);
              if (result['success'] == true && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Workflow triggered')));
                Future.delayed(const Duration(seconds: 2), () {
                  provider.loadRuns(repo: repo);
                });
              }
            },
          ),
        ],
      ),
    );
  }
}

class _RunTile extends StatelessWidget {
  final dynamic run;
  final String repo;
  const _RunTile({required this.run, required this.repo});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: _buildIcon(),
      title: Text(
        run.displayTitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
      subtitle: Row(
        children: [
          Icon(Icons.commit, size: 14, color: Colors.grey[500]),
          const SizedBox(width: 4),
          Text(run.sha,
              style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: Colors.grey[500])),
          const SizedBox(width: 12),
          Icon(Icons.account_tree_outlined, size: 14, color: Colors.grey[500]),
          const SizedBox(width: 4),
          Flexible(
            child: Text(run.branch,
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                overflow: TextOverflow.ellipsis),
          ),
          if (run.duration.isNotEmpty) ...[
            const SizedBox(width: 12),
            Icon(Icons.timer_outlined, size: 14, color: Colors.grey[500]),
            const SizedBox(width: 4),
            Text(run.duration,
                style: TextStyle(fontSize: 12, color: Colors.grey[500])),
          ],
        ],
      ),
      trailing: PopupMenuButton<String>(
        itemBuilder: (ctx) => [
          PopupMenuItem(value: 'status', child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              StatusBadge(status: run.conclusion ?? run.status),
              const SizedBox(width: 8),
              Text(run.actor, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
            ],
          )),
          const PopupMenuDivider(),
          if (run.isFailure)
            const PopupMenuItem(value: 'rerun', child: ListTile(
              dense: true,
              leading: Icon(Icons.replay, size: 18),
              title: Text('Rerun'),
              contentPadding: EdgeInsets.zero,
            )),
          if (run.isRunning)
            const PopupMenuItem(value: 'cancel', child: ListTile(
              dense: true,
              leading: Icon(Icons.cancel, size: 18),
              title: Text('Cancel'),
              contentPadding: EdgeInsets.zero,
            )),
          const PopupMenuItem(value: 'jobs', child: ListTile(
            dense: true,
            leading: Icon(Icons.list, size: 18),
            title: Text('View Jobs'),
            contentPadding: EdgeInsets.zero,
          )),
        ],
        onSelected: (action) => _handleAction(context, action),
      ),
    );
  }

  void _handleAction(BuildContext context, String action) async {
    final provider = context.read<DashboardProvider>();

    switch (action) {
      case 'rerun':
        final result = await provider.rerunWorkflow(repo, run.id);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(result['success'] == true
                ? 'Rerun triggered'
                : 'Failed: ${result['error']}'),
          ));
        }
        Future.delayed(const Duration(seconds: 2), () {
          provider.loadRuns(repo: repo);
        });

      case 'cancel':
        final result = await provider.cancelRun(repo, run.id);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(result['success'] == true
                ? 'Cancellation requested'
                : 'Failed: ${result['error']}'),
          ));
        }
        Future.delayed(const Duration(seconds: 2), () {
          provider.loadRuns(repo: repo);
        });

      case 'jobs':
        _showJobsDialog(context, provider);
    }
  }

  void _showJobsDialog(BuildContext context, DashboardProvider provider) async {
    final jobs = await provider.getRunJobs(repo, run.id);

    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Jobs - ${run.displayTitle}',
            style: const TextStyle(fontSize: 16)),
        content: SizedBox(
          width: double.maxFinite,
          child: jobs.isEmpty
              ? const Text('No jobs found')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: jobs.length,
                  itemBuilder: (_, i) {
                    final job = jobs[i];
                    return ExpansionTile(
                      title: Text(job['name'] ?? '',
                          style: const TextStyle(fontSize: 13)),
                      leading: Icon(
                        job['conclusion'] == 'success'
                            ? Icons.check_circle
                            : job['conclusion'] == 'failure'
                                ? Icons.cancel
                                : Icons.pending,
                        size: 18,
                        color: job['conclusion'] == 'success'
                            ? RummelBlueColors.success500
                            : job['conclusion'] == 'failure'
                                ? RummelBlueColors.error500
                                : RummelBlueColors.primary500,
                      ),
                      trailing: StatusBadge(
                          status: job['conclusion'] ?? job['status'] ?? 'unknown'),
                      children: [
                        for (final step in (job['steps'] as List?) ?? [])
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 2),
                            child: Row(
                              children: [
                                Icon(
                                  step['conclusion'] == 'success'
                                      ? Icons.check
                                      : step['conclusion'] == 'failure'
                                          ? Icons.close
                                          : step['conclusion'] == 'skipped'
                                              ? Icons.skip_next
                                              : Icons.hourglass_empty,
                                  size: 14,
                                  color: step['conclusion'] == 'success'
                                      ? RummelBlueColors.success500
                                      : step['conclusion'] == 'failure'
                                          ? RummelBlueColors.error500
                                          : Colors.grey,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(step['name'] ?? '',
                                      style: const TextStyle(fontSize: 12)),
                                ),
                              ],
                            ),
                          ),
                      ],
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

  Widget _buildIcon() {
    if (run.isSuccess) {
      return const Icon(Icons.check_circle,
          color: RummelBlueColors.success500, size: 28);
    }
    if (run.isFailure) {
      return const Icon(Icons.cancel,
          color: RummelBlueColors.error500, size: 28);
    }
    if (run.isRunning) {
      return SizedBox(
        width: 28,
        height: 28,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: RummelBlueColors.primary500,
        ),
      );
    }
    return Icon(Icons.circle_outlined, color: Colors.grey[500], size: 28);
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _MiniStat({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(fontSize: 10, color: Colors.grey[500])),
          ],
        ),
      ),
    );
  }
}
