import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rummel_blue_theme/rummel_blue_theme.dart';

import '../providers/dashboard_provider.dart';
import 'screens/main_shell.dart';

class InfrastructureDashboardApp extends StatelessWidget {
  const InfrastructureDashboardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Infrastructure Dashboard',
      debugShowCheckedModeBanner: false,
      theme: RummelBlueTheme.dark(),
      home: const _AppLoader(),
    );
  }
}

class _AppLoader extends StatefulWidget {
  const _AppLoader();

  @override
  State<_AppLoader> createState() => _AppLoaderState();
}

class _AppLoaderState extends State<_AppLoader> {
  @override
  void initState() {
    super.initState();
    final provider = context.read<DashboardProvider>();
    provider.loadConfig().then((_) => provider.loadAll());
  }

  @override
  Widget build(BuildContext context) {
    return const MainShell();
  }
}
