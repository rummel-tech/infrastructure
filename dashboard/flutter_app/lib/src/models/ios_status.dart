import 'workflow_run.dart';

class IosSecretStatus {
  final String name;
  final bool? present; // null = API unavailable (no secrets:read scope)

  IosSecretStatus({required this.name, required this.present});

  factory IosSecretStatus.fromJson(Map<String, dynamic> json) {
    return IosSecretStatus(
      name: json['name'] as String? ?? '',
      present: json['present'] as bool?,
    );
  }
}

class IosAppStatus {
  final String name;
  final String displayName;
  final String bundleId;
  final int? workflowId;
  final String workflowName;
  final List<WorkflowRun> recentRuns;
  final List<IosSecretStatus> secrets;
  final bool secretsReady;
  final List<String> missingSecrets;

  IosAppStatus({
    required this.name,
    required this.displayName,
    required this.bundleId,
    this.workflowId,
    required this.workflowName,
    required this.recentRuns,
    required this.secrets,
    required this.secretsReady,
    required this.missingSecrets,
  });

  factory IosAppStatus.fromJson(Map<String, dynamic> json) {
    final runs = (json['recent_runs'] as List? ?? [])
        .map((r) => WorkflowRun.fromJson(r as Map<String, dynamic>))
        .toList();
    final secs = (json['secrets'] as List? ?? [])
        .map((s) => IosSecretStatus.fromJson(s as Map<String, dynamic>))
        .toList();
    return IosAppStatus(
      name: json['name'] as String? ?? '',
      displayName: json['display_name'] as String? ?? '',
      bundleId: json['bundle_id'] as String? ?? '',
      workflowId: json['workflow_id'] as int?,
      workflowName: json['workflow_name'] as String? ?? '',
      recentRuns: runs,
      secrets: secs,
      secretsReady: json['secrets_ready'] == true,
      missingSecrets: (json['missing_secrets'] as List? ?? []).cast<String>(),
    );
  }

  WorkflowRun? get latestRun => recentRuns.isEmpty ? null : recentRuns.first;
}
