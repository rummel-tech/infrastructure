import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rummel_blue_theme/rummel_blue_theme.dart';

import '../../providers/dashboard_provider.dart';
import '../../models/catalog_item.dart';

class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key});

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DashboardProvider>();
    final theme = Theme.of(context);

    return Column(
      children: [
        if (provider.catalogSummary != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            child: Row(
              children: [
                _CountChip(
                  count: provider.catalogSummary!.totalFlutterApps,
                  label: 'Apps',
                  color: RummelBlueColors.primary500,
                ),
                const SizedBox(width: 8),
                _CountChip(
                  count: provider.catalogSummary!.totalBackendServices,
                  label: 'Services',
                  color: RummelBlueColors.success500,
                ),
                const SizedBox(width: 8),
                _CountChip(
                  count: provider.catalogSummary!.totalSharedPackages,
                  label: 'Packages',
                  color: RummelBlueColors.warning500,
                ),
                const SizedBox(width: 8),
                _CountChip(
                  count: provider.catalogSummary!.totalRepos,
                  label: 'Repos',
                  color: Colors.teal,
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.radar, size: 20),
                  tooltip: 'Discover repos from GitHub',
                  onPressed: () => _discoverRepos(context, provider),
                ),
              ],
            ),
          ),

        TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Flutter Apps'),
            Tab(text: 'Backends'),
            Tab(text: 'Packages'),
          ],
        ),

        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _FlutterAppsTab(apps: provider.flutterApps),
              _BackendsTab(services: provider.backendServices),
              _PackagesTab(packages: provider.sharedPackages),
            ],
          ),
        ),
      ],
    );
  }

  void _discoverRepos(BuildContext context, DashboardProvider provider) async {
    final scaffold = ScaffoldMessenger.of(context);
    scaffold.showSnackBar(
        const SnackBar(content: Text('Scanning GitHub org...')));

    final result = await provider.discoverRepos();

    if (!context.mounted) return;
    final added = result['added'] as int? ?? 0;
    final discovered = result['discovered'] as int? ?? 0;
    final newComponents = (result['new_components'] as List?)?.join(', ') ?? '';

    scaffold.hideCurrentSnackBar();
    scaffold.showSnackBar(SnackBar(
      content: Text(added > 0
          ? 'Found $discovered repos, added $added: $newComponents'
          : 'Found $discovered repos, nothing new to add'),
      duration: const Duration(seconds: 4),
    ));
  }
}

class _CountChip extends StatelessWidget {
  final int count;
  final String label;
  final Color color;
  const _CountChip({required this.count, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$count',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, color: color)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Flutter Apps tab
// ---------------------------------------------------------------------------

class _FlutterAppsTab extends StatelessWidget {
  final List<FlutterApp> apps;
  const _FlutterAppsTab({required this.apps});

  @override
  Widget build(BuildContext context) {
    if (apps.isEmpty) {
      return const Center(child: Text('Loading catalog...'));
    }

    return Scaffold(
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: apps.length,
        itemBuilder: (context, i) => _FlutterAppCard(app: apps[i]),
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'add_app',
        onPressed: () => _showAddDialog(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showAddDialog(BuildContext context) {
    final provider = context.read<DashboardProvider>();
    final nameCtrl = TextEditingController();
    final repoCtrl = TextEditingController();
    final descCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Register Flutter App'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'App name (dart package name)')),
              const SizedBox(height: 8),
              TextField(controller: repoCtrl, decoration: const InputDecoration(labelText: 'GitHub repo name')),
              const SizedBox(height: 8),
              TextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'Description')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (nameCtrl.text.isEmpty || repoCtrl.text.isEmpty) return;
              await provider.addComponent('flutter_app', {
                'name': nameCtrl.text,
                'repo': repoCtrl.text,
                'description': descCtrl.text,
                'platforms': ['web'],
                'backend': null,
                'depends_on': [],
                'has_tests': false,
              });
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Register'),
          ),
        ],
      ),
    );
  }
}

class _FlutterAppCard extends StatelessWidget {
  final FlutterApp app;
  const _FlutterAppCard({required this.app});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        leading: Icon(
          Icons.phone_iphone,
          color: app.hasBackend ? RummelBlueColors.primary500 : Colors.grey,
        ),
        title: Text(app.name,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text(app.description, maxLines: 1, overflow: TextOverflow.ellipsis),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DetailRow('Repo', app.repo),
                _DetailRow('Backend', app.backend ?? 'None (standalone)'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final p in app.platforms) _PlatformChip(platform: p),
                  ],
                ),
                if (app.dependsOn.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('Dependencies',
                      style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    children: app.dependsOn
                        .map((d) => Chip(
                              label: Text(d, style: const TextStyle(fontSize: 11)),
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                            ))
                        .toList(),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      app.hasTests ? Icons.check_circle : Icons.cancel,
                      size: 14,
                      color: app.hasTests
                          ? RummelBlueColors.success500
                          : RummelBlueColors.error500,
                    ),
                    const SizedBox(width: 4),
                    Text(app.hasTests ? 'Has tests' : 'No tests',
                        style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                    const Spacer(),
                    IconButton(
                      icon: Icon(Icons.delete_outline, size: 18,
                          color: Theme.of(context).colorScheme.error),
                      tooltip: 'Remove from registry',
                      onPressed: () => _confirmRemove(context),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _confirmRemove(BuildContext context) {
    final provider = context.read<DashboardProvider>();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove from Registry?'),
        content: Text('Remove "${app.name}" from the platform registry?\n'
            'This does not delete the repo — only un-registers it from the dashboard.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () async {
              await provider.removeComponent('flutter_app', app.name);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Backends tab
// ---------------------------------------------------------------------------

class _BackendsTab extends StatelessWidget {
  final List<BackendService> services;
  const _BackendsTab({required this.services});

  @override
  Widget build(BuildContext context) {
    if (services.isEmpty) {
      return const Center(child: Text('Loading catalog...'));
    }

    return Scaffold(
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: services.length,
        itemBuilder: (context, i) => _BackendCard(service: services[i]),
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'add_svc',
        onPressed: () => _showAddDialog(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showAddDialog(BuildContext context) {
    final provider = context.read<DashboardProvider>();
    final nameCtrl = TextEditingController();
    final repoCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final portCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Register Backend Service'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Service name')),
              const SizedBox(height: 8),
              TextField(controller: repoCtrl, decoration: const InputDecoration(labelText: 'GitHub repo name')),
              const SizedBox(height: 8),
              TextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'Description')),
              const SizedBox(height: 8),
              TextField(controller: portCtrl, decoration: const InputDecoration(labelText: 'Port'), keyboardType: TextInputType.number),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (nameCtrl.text.isEmpty || repoCtrl.text.isEmpty) return;
              await provider.addComponent('backend_service', {
                'name': nameCtrl.text,
                'repo': repoCtrl.text,
                'description': descCtrl.text,
                'language': 'python',
                'framework': 'fastapi',
                'port': int.tryParse(portCtrl.text) ?? 0,
                'has_tests': false,
                'frontend': null,
              });
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Register'),
          ),
        ],
      ),
    );
  }
}

class _BackendCard extends StatelessWidget {
  final BackendService service;
  const _BackendCard({required this.service});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        leading: const Icon(Icons.dns, color: RummelBlueColors.success500),
        title: Text(service.name,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text('${service.repo} · port ${service.port}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!service.hasTests)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(Icons.warning_amber, size: 18,
                    color: RummelBlueColors.warning500),
              ),
            const Icon(Icons.expand_more),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DetailRow('Description', service.description),
                _DetailRow('Repo', service.repo),
                _DetailRow('Stack', '${service.language} · ${service.framework}'),
                _DetailRow('Frontend', service.frontend ?? 'None'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _CapabilityChip(label: 'Tests', enabled: service.hasTests),
                    const Spacer(),
                    IconButton(
                      icon: Icon(Icons.delete_outline, size: 18,
                          color: Theme.of(context).colorScheme.error),
                      tooltip: 'Remove from registry',
                      onPressed: () => _confirmRemove(context),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _confirmRemove(BuildContext context) {
    final provider = context.read<DashboardProvider>();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove from Registry?'),
        content: Text('Remove "${service.name}" from the platform registry?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () async {
              await provider.removeComponent('backend_service', service.name);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Packages tab
// ---------------------------------------------------------------------------

class _PackagesTab extends StatelessWidget {
  final List<SharedPackage> packages;
  const _PackagesTab({required this.packages});

  @override
  Widget build(BuildContext context) {
    if (packages.isEmpty) {
      return const Center(child: Text('Loading catalog...'));
    }

    final dartPkgs = packages.where((p) => p.language == 'dart').toList();
    final pythonPkgs = packages.where((p) => p.language == 'python').toList();

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (pythonPkgs.isNotEmpty) ...[
            Text('Python Packages',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary)),
            const SizedBox(height: 8),
            for (final pkg in pythonPkgs) _PackageCard(pkg: pkg),
            const SizedBox(height: 16),
          ],
          if (dartPkgs.isNotEmpty) ...[
            Text('Dart/Flutter Packages',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary)),
            const SizedBox(height: 8),
            for (final pkg in dartPkgs) _PackageCard(pkg: pkg),
          ],
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'add_pkg',
        onPressed: () => _showAddDialog(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showAddDialog(BuildContext context) {
    final provider = context.read<DashboardProvider>();
    final nameCtrl = TextEditingController();
    final repoCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String language = 'dart';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Register Shared Package'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Package name')),
              const SizedBox(height: 8),
              TextField(controller: repoCtrl, decoration: const InputDecoration(labelText: 'GitHub repo name')),
              const SizedBox(height: 8),
              TextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'Description')),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: language,
                decoration: const InputDecoration(labelText: 'Language'),
                items: const [
                  DropdownMenuItem(value: 'dart', child: Text('Dart')),
                  DropdownMenuItem(value: 'python', child: Text('Python')),
                ],
                onChanged: (v) => language = v ?? 'dart',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (nameCtrl.text.isEmpty || repoCtrl.text.isEmpty) return;
              await provider.addComponent('shared_package', {
                'name': nameCtrl.text,
                'repo': repoCtrl.text,
                'description': descCtrl.text,
                'language': language,
                'version': '0.0.1',
                'consumers': [],
              });
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Register'),
          ),
        ],
      ),
    );
  }
}

class _PackageCard extends StatelessWidget {
  final SharedPackage pkg;
  const _PackageCard({required this.pkg});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        leading: Icon(
          pkg.language == 'dart' ? Icons.flutter_dash : Icons.code,
          color: RummelBlueColors.warning500,
        ),
        title: Text(pkg.name,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text('${pkg.repo} · v${pkg.version} · ${pkg.consumers.length} consumers'),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DetailRow('Description', pkg.description),
                _DetailRow('Repo', pkg.repo),
                const SizedBox(height: 8),
                Text('Used by',
                    style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: pkg.consumers
                      .map((c) => Chip(
                            label: Text(c, style: const TextStyle(fontSize: 11)),
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                          ))
                      .toList(),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      icon: Icon(Icons.delete_outline, size: 18,
                          color: Theme.of(context).colorScheme.error),
                      tooltip: 'Remove from registry',
                      onPressed: () {
                        final provider = context.read<DashboardProvider>();
                        showDialog(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Remove from Registry?'),
                            content: Text('Remove "${pkg.name}" from the platform registry?'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                              FilledButton(
                                style: FilledButton.styleFrom(
                                    backgroundColor: Theme.of(context).colorScheme.error),
                                onPressed: () async {
                                  await provider.removeComponent('shared_package', pkg.name);
                                  if (ctx.mounted) Navigator.pop(ctx);
                                },
                                child: const Text('Remove'),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared widgets
// ---------------------------------------------------------------------------

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(label,
                style: TextStyle(fontSize: 12, color: Colors.grey[500])),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
          ),
        ],
      ),
    );
  }
}

class _PlatformChip extends StatelessWidget {
  final String platform;
  const _PlatformChip({required this.platform});

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (platform) {
      'ios' => (Icons.apple, Colors.grey),
      'android' => (Icons.android, Colors.green),
      'web' => (Icons.language, Colors.blue),
      'linux' => (Icons.computer, Colors.orange),
      'macos' => (Icons.desktop_mac, Colors.grey),
      'windows' => (Icons.desktop_windows, Colors.cyan),
      _ => (Icons.device_unknown, Colors.grey),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(platform, style: TextStyle(fontSize: 10, color: color)),
        ],
      ),
    );
  }
}

class _CapabilityChip extends StatelessWidget {
  final String label;
  final bool enabled;
  const _CapabilityChip({required this.label, required this.enabled});

  @override
  Widget build(BuildContext context) {
    final color = enabled ? RummelBlueColors.success500 : RummelBlueColors.error500;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(enabled ? Icons.check_circle : Icons.cancel, size: 14, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, color: color)),
        ],
      ),
    );
  }
}
