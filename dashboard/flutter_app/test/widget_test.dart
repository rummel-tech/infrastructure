import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:infrastructure_dashboard/src/providers/dashboard_provider.dart';
import 'package:infrastructure_dashboard/src/services/api_client.dart';
import 'package:infrastructure_dashboard/src/ui/app.dart';

void main() {
  testWidgets('App renders MaterialApp', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => DashboardProvider(ApiClient()),
        child: const InfrastructureDashboardApp(),
      ),
    );
    expect(find.byType(MaterialApp), findsOneWidget);
  });

  testWidgets('App has correct title', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => DashboardProvider(ApiClient()),
        child: const InfrastructureDashboardApp(),
      ),
    );
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.title, 'Infrastructure Dashboard');
  });

  testWidgets('Navigation bar is present', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => DashboardProvider(ApiClient()),
        child: const InfrastructureDashboardApp(),
      ),
    );
    await tester.pump();
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('Shows all seven nav destinations on narrow screen', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => DashboardProvider(ApiClient()),
        child: const InfrastructureDashboardApp(),
      ),
    );
    await tester.pump();
    expect(find.byType(NavigationDestination), findsNWidgets(7));
  });
}
