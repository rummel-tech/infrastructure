class CatalogSummary {
  final int totalFlutterApps;
  final int totalBackendServices;
  final int totalSharedPackages;
  final int totalRepos;
  final int appsWithBackend;
  final int appsStandalone;
  final int servicesWithTests;
  final int servicesWithoutTests;
  final int totalWorkflows;

  CatalogSummary({
    required this.totalFlutterApps,
    required this.totalBackendServices,
    required this.totalSharedPackages,
    required this.totalRepos,
    required this.appsWithBackend,
    required this.appsStandalone,
    required this.servicesWithTests,
    required this.servicesWithoutTests,
    required this.totalWorkflows,
  });

  factory CatalogSummary.fromJson(Map<String, dynamic> json) => CatalogSummary(
        totalFlutterApps: json['total_flutter_apps'] ?? 0,
        totalBackendServices: json['total_backend_services'] ?? 0,
        totalSharedPackages: json['total_shared_packages'] ?? 0,
        totalRepos: json['total_repos'] ?? 0,
        appsWithBackend: json['apps_with_backend'] ?? 0,
        appsStandalone: json['apps_standalone'] ?? 0,
        servicesWithTests: json['services_with_tests'] ?? 0,
        servicesWithoutTests: json['services_without_tests'] ?? 0,
        totalWorkflows: json['total_workflows'] ?? 0,
      );
}

class FlutterApp {
  final String name;
  final String repo;
  final String description;
  final List<String> platforms;
  final String? backend;
  final List<String> dependsOn;
  final bool hasTests;

  FlutterApp({
    required this.name,
    required this.repo,
    required this.description,
    required this.platforms,
    this.backend,
    required this.dependsOn,
    required this.hasTests,
  });

  factory FlutterApp.fromJson(Map<String, dynamic> json) => FlutterApp(
        name: json['name'] ?? '',
        repo: json['repo'] ?? '',
        description: json['description'] ?? '',
        platforms: (json['platforms'] as List?)?.cast<String>() ?? [],
        backend: json['backend'],
        dependsOn: (json['depends_on'] as List?)?.cast<String>() ?? [],
        hasTests: json['has_tests'] ?? false,
      );

  bool get hasBackend => backend != null && backend!.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'name': name,
        'repo': repo,
        'description': description,
        'platforms': platforms,
        'backend': backend,
        'depends_on': dependsOn,
        'has_tests': hasTests,
      };
}

class BackendService {
  final String name;
  final String repo;
  final String language;
  final String framework;
  final int port;
  final String description;
  final bool hasTests;
  final String? frontend;

  BackendService({
    required this.name,
    required this.repo,
    required this.language,
    required this.framework,
    required this.port,
    required this.description,
    required this.hasTests,
    this.frontend,
  });

  factory BackendService.fromJson(Map<String, dynamic> json) => BackendService(
        name: json['name'] ?? '',
        repo: json['repo'] ?? '',
        language: json['language'] ?? '',
        framework: json['framework'] ?? '',
        port: json['port'] ?? 0,
        description: json['description'] ?? '',
        hasTests: json['has_tests'] ?? false,
        frontend: json['frontend'],
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'repo': repo,
        'description': description,
        'language': language,
        'framework': framework,
        'port': port,
        'has_tests': hasTests,
        'frontend': frontend,
      };
}

class SharedPackage {
  final String name;
  final String repo;
  final String language;
  final String description;
  final String version;
  final List<String> consumers;

  SharedPackage({
    required this.name,
    required this.repo,
    required this.language,
    required this.description,
    required this.version,
    required this.consumers,
  });

  factory SharedPackage.fromJson(Map<String, dynamic> json) => SharedPackage(
        name: json['name'] ?? '',
        repo: json['repo'] ?? '',
        language: json['language'] ?? '',
        description: json['description'] ?? '',
        version: json['version'] ?? '',
        consumers: (json['consumers'] as List?)?.cast<String>() ?? [],
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'repo': repo,
        'description': description,
        'language': language,
        'version': version,
        'consumers': consumers,
      };
}

class DependencyNode {
  final String id;
  final String type;
  final String group;
  final String repo;

  DependencyNode({
    required this.id,
    required this.type,
    required this.group,
    required this.repo,
  });

  factory DependencyNode.fromJson(Map<String, dynamic> json) =>
      DependencyNode(
        id: json['id'] ?? '',
        type: json['type'] ?? '',
        group: json['group'] ?? '',
        repo: json['repo'] ?? '',
      );
}

class DependencyEdge {
  final String from;
  final String to;
  final String type;

  DependencyEdge({
    required this.from,
    required this.to,
    required this.type,
  });

  factory DependencyEdge.fromJson(Map<String, dynamic> json) =>
      DependencyEdge(
        from: json['from'] ?? '',
        to: json['to'] ?? '',
        type: json['type'] ?? '',
      );
}
