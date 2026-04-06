import 'package:flutter/foundation.dart';
import '../models/secret.dart';
import '../models/required_secret.dart';
import '../models/workflow_run.dart';
import '../models/ecs_service.dart';
import '../models/catalog_item.dart';
import '../models/infrastructure.dart';
import '../models/cost_data.dart';
import '../services/api_client.dart';

class DashboardProvider extends ChangeNotifier {
  final ApiClient _api;

  DashboardProvider(this._api);

  String _environment = 'staging';
  String get environment => _environment;

  List<Secret> _secrets = [];
  List<Secret> get secrets => _secrets;

  List<RequiredSecret> _requiredSecrets = [];
  List<RequiredSecret> get requiredSecrets => _requiredSecrets;

  RequiredSecretsSummary? _requiredSecretsSummary;
  RequiredSecretsSummary? get requiredSecretsSummary => _requiredSecretsSummary;

  List<EcsService> _services = [];
  List<EcsService> get services => _services;
  String _cluster = '';
  String get cluster => _cluster;

  List<WorkflowRun> _runs = [];
  List<WorkflowRun> get runs => _runs;

  List<Workflow> _workflows = [];
  List<Workflow> get workflows => _workflows;

  List<String> _configServices = [];
  List<String> get configServices => _configServices;

  List<String> _repos = [];
  List<String> get repos => _repos;

  String _githubOrg = '';
  String get githubOrg => _githubOrg;

  // Catalog state
  CatalogSummary? _catalogSummary;
  CatalogSummary? get catalogSummary => _catalogSummary;

  List<FlutterApp> _flutterApps = [];
  List<FlutterApp> get flutterApps => _flutterApps;

  List<BackendService> _backendServices = [];
  List<BackendService> get backendServices => _backendServices;

  List<SharedPackage> _sharedPackages = [];
  List<SharedPackage> get sharedPackages => _sharedPackages;

  Map<String, dynamic> _infrastructure = {};
  Map<String, dynamic> get infrastructure => _infrastructure;

  List<DependencyNode> _depNodes = [];
  List<DependencyNode> get depNodes => _depNodes;

  List<DependencyEdge> _depEdges = [];
  List<DependencyEdge> get depEdges => _depEdges;

  // Infrastructure state
  ResourceSummary? _resourceSummary;
  ResourceSummary? get resourceSummary => _resourceSummary;

  List<CloudWatchAlarm> _alarms = [];
  List<CloudWatchAlarm> get alarms => _alarms;

  List<CdnDistribution> _cdnDistributions = [];
  List<CdnDistribution> get cdnDistributions => _cdnDistributions;

  // Cost state
  List<MonthlyCost> _monthlyCosts = [];
  List<MonthlyCost> get monthlyCosts => _monthlyCosts;

  List<ServiceCost> _serviceCosts = [];
  List<ServiceCost> get serviceCosts => _serviceCosts;
  double _serviceCostsTotal = 0;
  double get serviceCostsTotal => _serviceCostsTotal;

  List<DailyCost> _dailyCosts = [];
  List<DailyCost> get dailyCosts => _dailyCosts;

  CostForecast? _forecast;
  CostForecast? get forecast => _forecast;

  bool _loading = false;
  bool get loading => _loading;

  String? _error;
  String? get error => _error;

  void setEnvironment(String env) {
    _environment = env;
    notifyListeners();
    loadAll();
  }

  Future<void> loadConfig() async {
    try {
      final data = await _api.get('/api/config');
      _configServices = (data['services'] as List?)?.cast<String>() ?? [];
      _repos = (data['repos'] as List?)?.cast<String>() ?? [];
      _githubOrg = data['github_org'] ?? '';
    } catch (e) {
      _error = e.toString();
    }
    notifyListeners();
  }

  Future<void> loadAll() async {
    _loading = true;
    _error = null;
    notifyListeners();

    await Future.wait([
      loadSecrets(),
      loadRequiredSecrets(),
      loadServices(),
      loadRuns(),
      loadCatalog(),
      loadInfrastructureSummary(),
      loadCosts(),
    ]);

    _loading = false;
    notifyListeners();
  }

  Future<void> loadSecrets() async {
    try {
      // No environment filter — platform secrets use {service}/{key} naming,
      // not an environment prefix. Filter by service via query param if needed.
      final data = await _api.get('/api/secrets');
      final list = data['secrets'] as List? ?? [];
      _secrets = list.map((s) => Secret.fromJson(s)).toList();
    } catch (e) {
      _secrets = [];
    }
    notifyListeners();
  }

  Future<void> loadRequiredSecrets() async {
    try {
      final data = await _api.get('/api/secrets/required',
          params: {'environment': _environment});
      final list = data['secrets'] as List? ?? [];
      _requiredSecrets = list.map((s) => RequiredSecret.fromJson(s)).toList();
      final summary = data['summary'];
      if (summary != null) {
        _requiredSecretsSummary = RequiredSecretsSummary.fromJson(summary);
      }
    } catch (e) {
      _requiredSecrets = [];
      _requiredSecretsSummary = null;
    }
    notifyListeners();
  }

  Future<void> loadServices() async {
    try {
      final data = await _api.get('/api/services',
          params: {'environment': _environment});
      final list = data['services'] as List? ?? [];
      _services = list.map((s) => EcsService.fromJson(s)).toList();
      _cluster = data['cluster'] ?? '';
    } catch (e) {
      _services = [];
    }
    notifyListeners();
  }

  Future<void> loadRuns({String? repo}) async {
    try {
      final repoName = repo ?? (_repos.isNotEmpty ? _repos.first : 'services');
      final data = await _api.get('/api/deployments/runs/$repoName',
          params: {'per_page': '30'});
      final list = data['runs'] as List? ?? [];
      _runs = list.map((r) => WorkflowRun.fromJson(r)).toList();
    } catch (e) {
      _runs = [];
    }
    notifyListeners();
  }

  Future<void> loadWorkflows({String? repo}) async {
    try {
      final repoName = repo ?? (_repos.isNotEmpty ? _repos.first : 'services');
      final data = await _api.get('/api/deployments/workflows/$repoName');
      final list = data['workflows'] as List? ?? [];
      _workflows = list.map((w) => Workflow.fromJson(w)).toList();
    } catch (e) {
      _workflows = [];
    }
    notifyListeners();
  }

  Future<void> loadCatalog() async {
    try {
      final data = await _api.get('/api/catalog');

      final summary = data['summary'];
      if (summary != null) {
        _catalogSummary = CatalogSummary.fromJson(summary);
      }

      _githubOrg = data['github_org'] ?? _githubOrg;

      final apps = data['flutter_apps'] as List? ?? [];
      _flutterApps = apps.map((a) => FlutterApp.fromJson(a)).toList();

      final svcs = data['backend_services'] as List? ?? [];
      _backendServices = svcs.map((s) => BackendService.fromJson(s)).toList();

      final pkgs = data['shared_packages'] as List? ?? [];
      _sharedPackages = pkgs.map((p) => SharedPackage.fromJson(p)).toList();

      _infrastructure = (data['infrastructure'] as Map<String, dynamic>?) ?? {};

      final depData = await _api.get('/api/catalog/dependencies');
      final nodes = depData['nodes'] as List? ?? [];
      _depNodes = nodes.map((n) => DependencyNode.fromJson(n)).toList();
      final edges = depData['edges'] as List? ?? [];
      _depEdges = edges.map((e) => DependencyEdge.fromJson(e)).toList();
    } catch (e) {
      _catalogSummary = null;
      _flutterApps = [];
      _backendServices = [];
      _sharedPackages = [];
    }
    notifyListeners();
  }

  // ------------------------------------------------------------------
  // Infrastructure
  // ------------------------------------------------------------------

  Future<void> loadInfrastructureSummary() async {
    try {
      final data = await _api.get('/api/infrastructure/summary',
          params: {'environment': _environment});
      _resourceSummary = ResourceSummary.fromJson(data);
    } catch (e) {
      _resourceSummary = null;
    }
    try {
      final alarmData = await _api.get('/api/infrastructure/alarms',
          params: {'environment': _environment});
      final list = alarmData['alarms'] as List? ?? [];
      _alarms = list.map((a) => CloudWatchAlarm.fromJson(a)).toList();
    } catch (e) {
      _alarms = [];
    }
    try {
      final cdnData = await _api.get('/api/infrastructure/cdn');
      final list = cdnData['distributions'] as List? ?? [];
      _cdnDistributions = list.map((d) => CdnDistribution.fromJson(d)).toList();
    } catch (e) {
      _cdnDistributions = [];
    }
    notifyListeners();
  }

  Future<Map<String, dynamic>> getRdsMetrics(String identifier, {int hours = 6}) async {
    return _api.get('/api/infrastructure/rds/$identifier/metrics',
        params: {'hours': hours.toString()});
  }

  Future<Map<String, dynamic>> getAlbMetrics(String lbName, {int hours = 6}) async {
    return _api.get('/api/infrastructure/alb/$lbName/metrics',
        params: {'hours': hours.toString()});
  }

  // ------------------------------------------------------------------
  // Costs
  // ------------------------------------------------------------------

  Future<void> loadCosts() async {
    try {
      final monthly = await _api.get('/api/costs/monthly', params: {'months': '6'});
      _monthlyCosts = (monthly['months'] as List? ?? [])
          .map((m) => MonthlyCost.fromJson(m))
          .toList();
    } catch (e) {
      _monthlyCosts = [];
    }
    try {
      final bySvc = await _api.get('/api/costs/by-service', params: {'days': '30'});
      _serviceCosts = (bySvc['services'] as List? ?? [])
          .map((s) => ServiceCost.fromJson(s))
          .toList();
      _serviceCostsTotal = (bySvc['total'] as num?)?.toDouble() ?? 0;
    } catch (e) {
      _serviceCosts = [];
      _serviceCostsTotal = 0;
    }
    try {
      final daily = await _api.get('/api/costs/daily', params: {'days': '14'});
      _dailyCosts = (daily['days'] as List? ?? [])
          .map((d) => DailyCost.fromJson(d))
          .toList();
    } catch (e) {
      _dailyCosts = [];
    }
    try {
      final fc = await _api.get('/api/costs/forecast');
      if (fc['error'] == null) {
        _forecast = CostForecast.fromJson(fc);
      }
    } catch (e) {
      _forecast = null;
    }
    notifyListeners();
  }

  // ------------------------------------------------------------------
  // Registry CRUD
  // ------------------------------------------------------------------

  Future<Map<String, dynamic>> addComponent(String componentType, Map<String, dynamic> data) async {
    final result = await _api.post('/api/catalog/components', body: {
      'component_type': componentType,
      'data': data,
    });
    if (result['success'] == true) await loadCatalog();
    return result;
  }

  Future<Map<String, dynamic>> updateComponent(String componentType, String name, Map<String, dynamic> updates) async {
    final result = await _api.put('/api/catalog/components/$name', body: {
      'component_type': componentType,
      'updates': updates,
    });
    if (result['success'] == true) await loadCatalog();
    return result;
  }

  Future<Map<String, dynamic>> removeComponent(String componentType, String name) async {
    final result = await _api.delete('/api/catalog/components/$componentType/$name');
    if (result['success'] == true) await loadCatalog();
    return result;
  }

  Future<Map<String, dynamic>> discoverRepos() async {
    final result = await _api.post('/api/catalog/discover');
    if ((result['added'] as int? ?? 0) > 0) await loadCatalog();
    return result;
  }

  // ------------------------------------------------------------------
  // Secrets CRUD
  // ------------------------------------------------------------------

  Future<Map<String, dynamic>> createSecret({
    required String service,
    required String key,
    required String value,
    String description = '',
    String? environment,
  }) async {
    // Creates as {environment}/{service}/{key} matching ECS task definition paths.
    return _api.post('/api/secrets', body: {
      'environment': environment ?? _environment,
      'service': service,
      'key': key,
      'value': value,
      'description': description,
    });
  }

  Future<Map<String, dynamic>> updateSecret(String name, String value) async {
    return _api.put('/api/secrets/${Uri.encodeComponent(name)}',
        body: {'value': value});
  }

  Future<Map<String, dynamic>> deleteSecret(String name) async {
    return _api.delete('/api/secrets/${Uri.encodeComponent(name)}');
  }

  Future<Map<String, dynamic>> revealSecret(String name) async {
    return _api.get('/api/secrets/${Uri.encodeComponent(name)}/reveal');
  }

  // ------------------------------------------------------------------
  // Deployment actions
  // ------------------------------------------------------------------

  Future<Map<String, dynamic>> triggerWorkflow(
      String repo, int workflowId, {String ref = 'main', Map<String, dynamic>? inputs}) async {
    return _api.post('/api/deployments/trigger/$repo/$workflowId',
        body: {'ref': ref, 'inputs': inputs});
  }

  Future<Map<String, dynamic>> rerunWorkflow(String repo, int runId) async {
    return _api.post('/api/deployments/runs/$repo/$runId/rerun');
  }

  Future<Map<String, dynamic>> cancelRun(String repo, int runId) async {
    return _api.post('/api/deployments/runs/$repo/$runId/cancel');
  }

  Future<List<Map<String, dynamic>>> getRunJobs(String repo, int runId) async {
    final data = await _api.get('/api/deployments/runs/$repo/$runId/jobs');
    return (data['jobs'] as List?)?.cast<Map<String, dynamic>>() ?? [];
  }

  Future<Map<String, dynamic>> getServiceLogs(String serviceName) async {
    return _api.get('/api/services/$serviceName/logs',
        params: {'environment': _environment, 'limit': '100'});
  }

  Future<Map<String, dynamic>> getServiceTasks(String serviceName) async {
    return _api.get('/api/services/$serviceName/tasks',
        params: {'environment': _environment});
  }

  Future<Map<String, dynamic>> compareEnvironments() async {
    return _api.get('/api/deployments/compare');
  }
}
