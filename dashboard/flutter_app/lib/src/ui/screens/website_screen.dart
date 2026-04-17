import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/website_content.dart';
import '../../providers/dashboard_provider.dart';

class WebsiteScreen extends StatefulWidget {
  const WebsiteScreen({super.key});

  @override
  State<WebsiteScreen> createState() => _WebsiteScreenState();
}

class _WebsiteScreenState extends State<WebsiteScreen> {
  bool _loaded = false;
  bool _saving = false;
  bool _deploying = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loaded = true;
      _refresh();
    }
  }

  Future<void> _refresh() async {
    final provider = context.read<DashboardProvider>();
    await Future.wait([
      provider.loadWebsiteContent(),
      provider.loadWebsiteStatus(),
    ]);
  }

  Future<void> _deploy() async {
    setState(() => _deploying = true);
    try {
      final result = await context.read<DashboardProvider>().deployWebsite();
      if (!mounted) return;
      if (result['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Deploy triggered — check status below')),
        );
      } else {
        _showError(result['error']?.toString() ?? 'Deploy failed');
      }
    } finally {
      if (mounted) setState(() => _deploying = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DashboardProvider>();
    final content = provider.websiteContent;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _buildHeader(provider, content)),
            if (content != null) ...[
              SliverToBoxAdapter(child: _buildHeroEditor(content)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    'Apps (${content.apps.length})',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) => _AppEditTile(
                    app: content.apps[i],
                    onSave: (updated) => _saveApp(content, i, updated),
                  ),
                  childCount: content.apps.length,
                ),
              ),
            ],
            SliverToBoxAdapter(child: _buildDeployHistory(provider)),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(DashboardProvider provider, WebsiteContent? content) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Website', style: theme.textTheme.headlineSmall),
                    const SizedBox(height: 4),
                    Text(
                      'rummel-technologies-site · content/apps.json',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (_deploying)
                const Padding(
                  padding: EdgeInsets.only(right: 12),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              FilledButton.icon(
                onPressed: (content != null && !_deploying) ? _deploy : null,
                icon: const Icon(Icons.rocket_launch, size: 18),
                label: const Text('Deploy'),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh',
                onPressed: _refresh,
              ),
            ],
          ),
          if (content == null) ...[
            const SizedBox(height: 24),
            const Center(child: CircularProgressIndicator()),
          ],
        ],
      ),
    );
  }

  Widget _buildHeroEditor(WebsiteContent content) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Hero', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              _HeroEditorForm(
                hero: content.hero,
                saving: _saving,
                onSave: (updated) => _saveHero(content, updated),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDeployHistory(DashboardProvider provider) {
    final runs = provider.websiteRuns;
    if (runs.isEmpty && provider.websiteDeployWorkflowFound == false) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.info_outline,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Deploy workflow (deploy-website.yml) not found in rummel-technologies-site. '
                    'Add it to enable one-click deploys.',
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (runs.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Recent Deploys',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final run in runs) _RunRow(run: run),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveHero(WebsiteContent current, WebsiteHero updated) async {
    setState(() => _saving = true);
    try {
      final next = WebsiteContent(
        meta: current.meta,
        hero: updated,
        signupUrl: current.signupUrl,
        loginUrl: current.loginUrl,
        apps: current.apps,
      );
      final result = await context.read<DashboardProvider>().saveWebsiteContent(next);
      if (!mounted) return;
      if (result['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Hero updated — deploy to publish')),
        );
      } else {
        _showError(result['error']?.toString() ?? 'Save failed');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveApp(WebsiteContent current, int index, AppEntry updated) async {
    setState(() => _saving = true);
    try {
      final apps = List<AppEntry>.from(current.apps);
      apps[index] = updated;
      final next = WebsiteContent(
        meta: current.meta,
        hero: current.hero,
        signupUrl: current.signupUrl,
        loginUrl: current.loginUrl,
        apps: apps,
      );
      final result = await context.read<DashboardProvider>().saveWebsiteContent(next);
      if (!mounted) return;
      if (result['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${updated.name} updated — deploy to publish')),
        );
      } else {
        _showError(result['error']?.toString() ?? 'Save failed');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

// ---------------------------------------------------------------------------
// Hero editor form
// ---------------------------------------------------------------------------

class _HeroEditorForm extends StatefulWidget {
  final WebsiteHero hero;
  final bool saving;
  final void Function(WebsiteHero) onSave;

  const _HeroEditorForm({
    required this.hero,
    required this.saving,
    required this.onSave,
  });

  @override
  State<_HeroEditorForm> createState() => _HeroEditorFormState();
}

class _HeroEditorFormState extends State<_HeroEditorForm> {
  late final TextEditingController _badgeCtrl;
  late final TextEditingController _titleCtrl;
  late final TextEditingController _subtitleCtrl;
  late final TextEditingController _primaryLabelCtrl;
  late final TextEditingController _primaryUrlCtrl;

  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _badgeCtrl = TextEditingController(text: widget.hero.badge);
    _titleCtrl = TextEditingController(text: widget.hero.title);
    _subtitleCtrl = TextEditingController(text: widget.hero.subtitle);
    _primaryLabelCtrl = TextEditingController(text: widget.hero.ctaPrimaryLabel);
    _primaryUrlCtrl = TextEditingController(text: widget.hero.ctaPrimaryUrl);
    for (final c in [_badgeCtrl, _titleCtrl, _subtitleCtrl, _primaryLabelCtrl, _primaryUrlCtrl]) {
      c.addListener(() => setState(() => _dirty = true));
    }
  }

  @override
  void dispose() {
    for (final c in [_badgeCtrl, _titleCtrl, _subtitleCtrl, _primaryLabelCtrl, _primaryUrlCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _field(_badgeCtrl, 'Badge text'),
        const SizedBox(height: 8),
        _field(_titleCtrl, 'Title'),
        const SizedBox(height: 8),
        _field(_subtitleCtrl, 'Subtitle', maxLines: 3),
        const SizedBox(height: 8),
        _field(_primaryLabelCtrl, 'Primary CTA label'),
        const SizedBox(height: 8),
        _field(_primaryUrlCtrl, 'Primary CTA URL'),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            FilledButton.tonal(
              onPressed: (_dirty && !widget.saving)
                  ? () {
                      widget.onSave(widget.hero.copyWith(
                        badge: _badgeCtrl.text,
                        title: _titleCtrl.text,
                        subtitle: _subtitleCtrl.text,
                        ctaPrimaryLabel: _primaryLabelCtrl.text,
                        ctaPrimaryUrl: _primaryUrlCtrl.text,
                      ));
                      setState(() => _dirty = false);
                    }
                  : null,
              child: widget.saving
                  ? const SizedBox(
                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _field(TextEditingController ctrl, String label, {int maxLines = 1}) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// App edit tile
// ---------------------------------------------------------------------------

class _AppEditTile extends StatefulWidget {
  final AppEntry app;
  final Future<void> Function(AppEntry) onSave;

  const _AppEditTile({required this.app, required this.onSave});

  @override
  State<_AppEditTile> createState() => _AppEditTileState();
}

class _AppEditTileState extends State<_AppEditTile> {
  bool _expanded = false;
  bool _saving = false;
  late final TextEditingController _descCtrl;
  late final TextEditingController _appStoreCtrl;
  late final TextEditingController _playStoreCtrl;
  bool _comingSoon = false;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _descCtrl = TextEditingController(text: widget.app.description);
    _appStoreCtrl = TextEditingController(text: widget.app.appStoreUrl ?? '');
    _playStoreCtrl = TextEditingController(text: widget.app.playStoreUrl ?? '');
    _comingSoon = widget.app.comingSoon;
    for (final c in [_descCtrl, _appStoreCtrl, _playStoreCtrl]) {
      c.addListener(() => setState(() => _dirty = true));
    }
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    _appStoreCtrl.dispose();
    _playStoreCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.onSave(widget.app.copyWith(
        description: _descCtrl.text,
        appStoreUrl: _appStoreCtrl.text.isEmpty ? null : _appStoreCtrl.text,
        playStoreUrl: _playStoreCtrl.text.isEmpty ? null : _playStoreCtrl.text,
        comingSoon: _comingSoon,
      ));
      setState(() => _dirty = false);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final app = widget.app;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Card(
        child: Column(
          children: [
            ListTile(
              leading: Text(app.icon, style: const TextStyle(fontSize: 24)),
              title: Text(app.name),
              subtitle: Text(
                app.tag,
                style: TextStyle(
                  color: app.tagStyle == 'hub'
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_dirty)
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.error,
                        shape: BoxShape.circle,
                      ),
                    ),
                  const SizedBox(width: 8),
                  if (app.appStoreUrl != null)
                    const Icon(Icons.apple, size: 16),
                  if (app.playStoreUrl != null)
                    const Icon(Icons.android, size: 16),
                  IconButton(
                    icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                    onPressed: () => setState(() => _expanded = !_expanded),
                  ),
                ],
              ),
              onTap: () => setState(() => _expanded = !_expanded),
            ),
            if (_expanded)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Divider(),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _descCtrl,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _appStoreCtrl,
                      decoration: const InputDecoration(
                        labelText: 'App Store URL',
                        hintText: 'https://apps.apple.com/...',
                        border: OutlineInputBorder(),
                        isDense: true,
                        prefixIcon: Icon(Icons.apple, size: 18),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _playStoreCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Google Play URL',
                        hintText: 'https://play.google.com/...',
                        border: OutlineInputBorder(),
                        isDense: true,
                        prefixIcon: Icon(Icons.android, size: 18),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      title: const Text('Coming Soon'),
                      value: _comingSoon,
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      onChanged: (val) => setState(() {
                        _comingSoon = val;
                        _dirty = true;
                      }),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          app.platforms.join(' · '),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const Spacer(),
                        FilledButton.tonal(
                          onPressed: (_dirty && !_saving) ? _save : null,
                          child: _saving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2))
                              : const Text('Save'),
                        ),
                      ],
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

// ---------------------------------------------------------------------------
// Deploy run row
// ---------------------------------------------------------------------------

class _RunRow extends StatelessWidget {
  final WebsiteDeployRun run;

  const _RunRow({required this.run});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final conclusion = run.conclusion;

    Color dot;
    if (run.status == 'in_progress' || run.status == 'queued') {
      dot = Colors.orange;
    } else if (conclusion == 'success') {
      dot = Colors.green;
    } else if (conclusion == 'failure' || conclusion == 'timed_out') {
      dot = theme.colorScheme.error;
    } else {
      dot = theme.colorScheme.onSurfaceVariant;
    }

    return InkWell(
      onTap: run.url.isNotEmpty
          ? () {
              Clipboard.setData(ClipboardData(text: run.url));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Run URL copied to clipboard')),
              );
            }
          : null,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            Expanded(
              child: Text(
                run.status == 'in_progress'
                    ? 'Running…'
                    : conclusion ?? run.status,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            if (run.duration != null)
              Text(
                run.duration!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            const SizedBox(width: 8),
            Text(
              _fmtDate(run.createdAt),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  String _fmtDate(String iso) {
    if (iso.isEmpty) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.month}/${dt.day} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }
}
