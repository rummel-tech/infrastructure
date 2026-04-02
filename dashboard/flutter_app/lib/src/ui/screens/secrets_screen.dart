import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/dashboard_provider.dart';
import '../widgets/status_badge.dart';

class SecretsScreen extends StatelessWidget {
  const SecretsScreen({super.key});

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
                    Text('${provider.environment} environment',
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
                initialValue: selectedService,
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
                    hintText: 'e.g. database_url, api_key'),
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
              if (selectedService == null || keyCtrl.text.isEmpty || valueCtrl.text.isEmpty) return;
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
