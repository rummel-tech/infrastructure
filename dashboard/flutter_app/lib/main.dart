import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'src/providers/dashboard_provider.dart';
import 'src/services/api_client.dart';
import 'src/ui/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final apiClient = ApiClient();

  runApp(
    ChangeNotifierProvider(
      create: (_) => DashboardProvider(apiClient),
      child: const InfrastructureDashboardApp(),
    ),
  );
}
