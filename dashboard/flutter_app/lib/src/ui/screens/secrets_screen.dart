import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/required_secret.dart';
import '../../providers/dashboard_provider.dart';
import '../widgets/status_badge.dart';

class SecretsScreen extends StatelessWidget {
  const SecretsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 0,
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.checklist_rounded), text: 'Required'),
              Tab(icon: Icon(Icons.key_rounded), text: 'All Secrets'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _RequiredSecretsTab(),
            _AllSecretsTab(),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Required Secrets Tab
// ---------------------------------------------------------------------------

class _RequiredSecretsTab extends StatelessWidget {
  const _RequiredSecretsTab();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DashboardProvider>();
    final required = provider.requiredSecrets;
    final summary = provider.requiredSecretsSummary;
    final theme = Theme.of(context);
    final env = provider.environment;

    final byService = <String, List<RequiredSecret>>{};
    for (final s in required) {
      byService.putIfAbsent(s.service, () => []).add(s);
    }

    return RefreshIndicator(
      onRefresh: () => provider.loadRequiredSecrets(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (summary != null) ...[
            _SummaryBanner(summary: summary, environment: env),
            const SizedBox(height: 16),
          ],
          if (required.isEmpty && !provider.loading)
            Center(
              child: Column(
                children: [
                  const SizedBox(height: 40),
                  Icon(Icons.cloud_off, size: 48, color: Colors.grey[600]),
                  const SizedBox(height: 16),
                  const Text('Could not load required secrets'),
                  const SizedBox(height: 8),
                  Text('Check AWS credentials in dashboard settings',
                      style: TextStyle(color: Colors.grey[500])),
                ],
              ),
            )
          else
            for (final entry in byService.entries) ...[
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 4),
                child: Text(entry.key,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(color: theme.colorScheme.primary)),
              ),
              Card(
                child: Column(
                  children: [
                    for (var i = 0; i < entry.value.length; i++) ...[
                      _RequiredSecretTile(secret: entry.value[i]),
                      if (i < entry.value.length - 1)
                        const Divider(height: 1),
                    ],
                  ],
                ),
              ),
            ],
        ],
      ),
    );
  }
}

class _SummaryBanner extends StatelessWidget {
  final RequiredSecretsSummary summary;
  final String environment;
  const _SummaryBanner({required this.summary, required this.environment});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final envLabel = environment[0].toUpperCase() + environment.substring(1);
    final color = summary.ready
        ? Colors.green
        : summary.missing > 0
            ? theme.colorScheme.error
            : Colors.orange;

    return Card(
      color: color.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              summary.ready ? Icons.check_circle : Icons.warning_amber_rounded,
              color: color,
              size: 32,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    summary.ready
                        ? 'All $envLabel secrets configured'
                        : '$envLabel secrets incomplete',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(color: color, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${summary.set} set · '
                    '${summary.placeholder} placeholder · '
                    '${summary.missing} missing',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: Colors.grey[600]),
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

class _RequiredSecretTile extends StatelessWidget {
  final RequiredSecret secret;
  const _RequiredSecretTile({required this.secret});

  @override
  Widget build(BuildContext context) {
    final (icon, color, tooltip) = switch (secret.status) {
      'set' => (Icons.check_circle, Colors.green, 'Set'),
      'placeholder' => (Icons.warning_amber_rounded, Colors.orange, 'Placeholder — needs real value'),
      _ => (Icons.cancel, Theme.of(context).colorScheme.error, 'Missing'),
    };

    return ListTile(
      dense: true,
      leading: Icon(icon, color: color, size: 20),
      title: Text(
        secret.key,
        style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        secret.description,
        style: TextStyle(fontSize: 12, color: Colors.grey[500]),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.edit_outlined, size: 18),
        tooltip: secret.isMissing ? 'Create' : 'Update',
        onPressed: () => _editSecret(context),
      ),
    );
  }

  static bool _isMultiline(String key) =>
      key.contains('pem') || key.contains('key') && key.contains('private');

  // Values that are not sensitive and should be shown as plain text
  static bool _isPlainText(String key) =>
      key.contains('cors_origins') || key.contains('cors-origins');

  static String? _hintFor(String key) {
    if (key.contains('pem') || key == 'private_key') {
      return '-----BEGIN RSA PRIVATE KEY-----\n...';
    }
    if (key.contains('database_url') || key.contains('database-url')) {
      return 'postgresql://user:pass@host:5432/db';
    }
    if (key == 'google_client_id' || key == 'google-client-id') {
      return '123456789-abc.apps.googleusercontent.com';
    }
    if (key == 'github_token' || key == 'github-token') {
      return 'ghp_xxxxxxxxxxxxxxxxxxxx';
    }
    if (key.contains('anthropic')) return 'sk-ant-api03-...';
    if (key.contains('cors_origins') || key.contains('cors-origins')) {
      return '["https://your-app.example.com","https://www.your-app.example.com"]';
    }
    return null;
  }

  void _editSecret(BuildContext context) {
    final provider = context.read<DashboardProvider>();
    final valueCtrl = TextEditingController();
    final isCreating = secret.isMissing;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isCreating ? 'Create ${secret.name}' : 'Update ${secret.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              secret.description,
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: valueCtrl,
              decoration: InputDecoration(
                labelText: 'Value',
                hintText: _hintFor(secret.key),
              ),
              obscureText: !_isMultiline(secret.key) && !_isPlainText(secret.key),
              maxLines: _isMultiline(secret.key) ? 6 : 1,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (valueCtrl.text.isEmpty) return;
              Map<String, dynamic> result;
              if (isCreating) {
                result = await provider.createSecret(
                  service: secret.service,
                  key: secret.key,
                  value: valueCtrl.text,
                  description: secret.description,
                );
              } else {
                result = await provider.updateSecret(secret.name, valueCtrl.text);
              }
              if (ctx.mounted) Navigator.pop(ctx);
              if (result['success'] == true) {
                await provider.loadRequiredSecrets();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text(isCreating ? 'Secret created' : 'Secret updated')),
                  );
                }
              } else {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(result['error']?.toString() ?? 'Failed'),
                      backgroundColor: Theme.of(context).colorScheme.error,
                    ),
                  );
                }
              }
            },
            child: Text(isCreating ? 'Create' : 'Update'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// All Secrets Tab
// ---------------------------------------------------------------------------

class _AllSecretsTab extends StatelessWidget {
  const _AllSecretsTab();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DashboardProvider>();
    final secrets = provider.secrets;
    final theme = Theme.of(context);

    final byService = <String, List>{};
    for (final s in secrets) {
      byService.putIfAbsent(s.service, () => []).add(s);
    }

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => provider.loadSecrets(),
        child: secrets.isEmpty && !provider.loading
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.key_off, size: 48, color: Colors.grey[600]),
                    const SizedBox(height: 16),
                    const Text('No secrets found'),
                    const SizedBox(height: 8),
                    Text('Check AWS credentials',
                        style: TextStyle(color: Colors.grey[500])),
                  ],
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    '${secrets.length} secrets across ${byService.length} services',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  for (final entry in byService.entries) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 4),
                      child: Text(entry.key,
                          style: theme.textTheme.titleSmall?.copyWith(
                              color: theme.colorScheme.primary)),
                    ),
                    Card(
                      child: Column(
                        children: [
                          for (var i = 0; i < entry.value.length; i++) ...[
                            _SecretTile(secret: entry.value[i]),
                            if (i < entry.value.length - 1)
                              const Divider(height: 1),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('New Secret'),
      ),
    );
  }

  void _showCreateDialog(BuildContext context) {
    final provider = context.read<DashboardProvider>();
    final keyCtrl = TextEditingController();
    final valueCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String? selectedService =
        provider.configServices.isNotEmpty ? provider.configServices.first : null;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create Secret'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: selectedService,
                decoration: const InputDecoration(labelText: 'Service'),
                items: provider.configServices
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: (v) => selectedService = v,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: keyCtrl,
                decoration: const InputDecoration(
                    labelText: 'Key',
                    hintText: 'e.g. database-url, api-key'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: valueCtrl,
                decoration: const InputDecoration(labelText: 'Value'),
                obscureText: true,
                maxLines: 1,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descCtrl,
                decoration:
                    const InputDecoration(labelText: 'Description (optional)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (selectedService == null ||
                  keyCtrl.text.isEmpty ||
                  valueCtrl.text.isEmpty) return;
              final result = await provider.createSecret(
                service: selectedService!,
                key: keyCtrl.text,
                value: valueCtrl.text,
                description: descCtrl.text,
              );
              if (ctx.mounted) Navigator.pop(ctx);
              if (result['success'] == true) {
                provider.loadSecrets();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Secret created')));
                }
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}

class _SecretTile extends StatelessWidget {
  final dynamic secret;
  const _SecretTile({required this.secret});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      title: Text(secret.key,
          style: const TextStyle(
              fontFamily: 'monospace', fontWeight: FontWeight.w600)),
      subtitle: Text(
        secret.lastChanged.isNotEmpty
            ? 'Changed: ${secret.lastChanged}'
            : 'No change history',
        style: TextStyle(fontSize: 12, color: Colors.grey[500]),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (secret.rotationEnabled)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: StatusBadge(status: 'rotation'),
            ),
          IconButton(
            icon: const Icon(Icons.visibility_outlined, size: 18),
            tooltip: 'Reveal',
            onPressed: () => _reveal(context),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 18),
            tooltip: 'Edit',
            onPressed: () => _edit(context),
          ),
          IconButton(
            icon: Icon(Icons.delete_outline,
                size: 18, color: Theme.of(context).colorScheme.error),
            tooltip: 'Delete',
            onPressed: () => _confirmDelete(context),
          ),
        ],
      ),
    );
  }

  void _reveal(BuildContext context) async {
    final provider = context.read<DashboardProvider>();
    final data = await provider.revealSecret(secret.name);
    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(secret.key),
        content: SelectableText(
          data['masked_value'] ?? data['error'] ?? 'Unknown',
          style: const TextStyle(fontFamily: 'monospace'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  void _edit(BuildContext context) {
    final provider = context.read<DashboardProvider>();
    final valueCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Update ${secret.key}'),
        content: TextField(
          controller: valueCtrl,
          decoration: const InputDecoration(labelText: 'New Value'),
          obscureText: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (valueCtrl.text.isEmpty) return;
              final result =
                  await provider.updateSecret(secret.name, valueCtrl.text);
              if (ctx.mounted) Navigator.pop(ctx);
              if (result['success'] == true) {
                provider.loadSecrets();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Secret updated')));
                }
              }
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    final provider = context.read<DashboardProvider>();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Secret?'),
        content: Text(
            'Are you sure you want to delete "${secret.name}"?\nIt will be recoverable for 7 days.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () async {
              await provider.deleteSecret(secret.name);
              if (ctx.mounted) Navigator.pop(ctx);
              provider.loadSecrets();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Secret deleted')));
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
