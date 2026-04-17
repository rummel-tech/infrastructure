import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/dashboard_provider.dart';
import 'overview_screen.dart';
import 'catalog_screen.dart';
import 'secrets_screen.dart';
import 'builds_screen.dart';
import 'services_screen.dart';
import 'infra_screen.dart';
import 'cost_screen.dart';
import 'mobile_screen.dart';
import 'website_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    OverviewScreen(),
    CatalogScreen(),
    SecretsScreen(),
    BuildsScreen(),
    ServicesScreen(),
    InfraScreen(),
    CostScreen(),
    MobileScreen(),
    WebsiteScreen(),
  ];

  static const _destinations = [
    _NavItem(icon: Icons.dashboard_outlined, selected: Icons.dashboard, label: 'Overview'),
    _NavItem(icon: Icons.apps_outlined, selected: Icons.apps, label: 'Catalog'),
    _NavItem(icon: Icons.key_outlined, selected: Icons.key, label: 'Secrets'),
    _NavItem(icon: Icons.rocket_launch_outlined, selected: Icons.rocket_launch, label: 'Builds'),
    _NavItem(icon: Icons.dns_outlined, selected: Icons.dns, label: 'Services'),
    _NavItem(icon: Icons.cloud_outlined, selected: Icons.cloud, label: 'Infra'),
    _NavItem(icon: Icons.attach_money, selected: Icons.attach_money, label: 'Costs'),
    _NavItem(icon: Icons.phone_iphone_outlined, selected: Icons.phone_iphone, label: 'Mobile'),
    _NavItem(icon: Icons.language_outlined, selected: Icons.language, label: 'Website'),
  ];

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DashboardProvider>();
    final theme = Theme.of(context);
    final isWide = MediaQuery.of(context).size.width > 800;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Infrastructure'),
        actions: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: provider.environment,
                icon: const Icon(Icons.expand_more, size: 18),
                isDense: true,
                style: theme.textTheme.labelLarge,
                items: const [
                  DropdownMenuItem(value: 'staging', child: Text('Staging')),
                  DropdownMenuItem(value: 'production', child: Text('Production')),
                ],
                onChanged: (val) {
                  if (val != null) provider.setEnvironment(val);
                },
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh all',
            onPressed: () => provider.loadAll(),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: isWide
          ? Row(
              children: [
                NavigationRail(
                  selectedIndex: _currentIndex,
                  onDestinationSelected: (i) => setState(() => _currentIndex = i),
                  labelType: NavigationRailLabelType.all,
                  destinations: [
                    for (final d in _destinations)
                      NavigationRailDestination(
                        icon: Icon(d.icon),
                        selectedIcon: Icon(d.selected),
                        label: Text(d.label),
                      ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: IndexedStack(index: _currentIndex, children: _screens)),
              ],
            )
          : IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: isWide
          ? null
          : NavigationBar(
              selectedIndex: _currentIndex,
              onDestinationSelected: (i) => setState(() => _currentIndex = i),
              destinations: [
                for (final d in _destinations)
                  NavigationDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selected),
                    label: d.label,
                  ),
              ],
            ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final IconData selected;
  final String label;
  const _NavItem({required this.icon, required this.selected, required this.label});
}
