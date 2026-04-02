class RdsInstance {
  final String identifier;
  final String engine;
  final String instanceClass;
  final String status;
  final bool multiAz;
  final int storageGb;
  final int maxStorageGb;
  final String storageType;
  final String endpoint;
  final int port;
  final int backupRetention;
  final bool encrypted;
  final bool performanceInsights;
  final bool deletionProtection;

  RdsInstance({
    required this.identifier,
    required this.engine,
    required this.instanceClass,
    required this.status,
    required this.multiAz,
    required this.storageGb,
    required this.maxStorageGb,
    required this.storageType,
    required this.endpoint,
    required this.port,
    required this.backupRetention,
    required this.encrypted,
    required this.performanceInsights,
    required this.deletionProtection,
  });

  factory RdsInstance.fromJson(Map<String, dynamic> json) => RdsInstance(
        identifier: json['identifier'] ?? '',
        engine: json['engine'] ?? '',
        instanceClass: json['instance_class'] ?? '',
        status: json['status'] ?? '',
        multiAz: json['multi_az'] ?? false,
        storageGb: json['storage_gb'] ?? 0,
        maxStorageGb: json['max_storage_gb'] ?? 0,
        storageType: json['storage_type'] ?? '',
        endpoint: json['endpoint'] ?? '',
        port: json['port'] ?? 5432,
        backupRetention: json['backup_retention'] ?? 0,
        encrypted: json['encrypted'] ?? false,
        performanceInsights: json['performance_insights'] ?? false,
        deletionProtection: json['deletion_protection'] ?? false,
      );

  bool get isAvailable => status == 'available';
}

class LoadBalancer {
  final String name;
  final String dnsName;
  final String scheme;
  final String state;
  final String type;
  final List<String> azs;

  LoadBalancer({
    required this.name,
    required this.dnsName,
    required this.scheme,
    required this.state,
    required this.type,
    required this.azs,
  });

  factory LoadBalancer.fromJson(Map<String, dynamic> json) => LoadBalancer(
        name: json['name'] ?? '',
        dnsName: json['dns_name'] ?? '',
        scheme: json['scheme'] ?? '',
        state: json['state'] ?? '',
        type: json['type'] ?? '',
        azs: (json['azs'] as List?)?.cast<String>() ?? [],
      );
}

class CloudWatchAlarm {
  final String name;
  final String state;
  final String metric;
  final String namespace;
  final double threshold;
  final String stateReason;

  CloudWatchAlarm({
    required this.name,
    required this.state,
    required this.metric,
    required this.namespace,
    required this.threshold,
    required this.stateReason,
  });

  factory CloudWatchAlarm.fromJson(Map<String, dynamic> json) =>
      CloudWatchAlarm(
        name: json['name'] ?? '',
        state: json['state'] ?? '',
        metric: json['metric'] ?? '',
        namespace: json['namespace'] ?? '',
        threshold: (json['threshold'] as num?)?.toDouble() ?? 0,
        stateReason: json['state_reason'] ?? '',
      );

  bool get isOk => state == 'OK';
  bool get isFiring => state == 'ALARM';
}

class CdnDistribution {
  final String id;
  final String domain;
  final List<String> aliases;
  final String status;
  final bool enabled;
  final String origin;

  CdnDistribution({
    required this.id,
    required this.domain,
    required this.aliases,
    required this.status,
    required this.enabled,
    required this.origin,
  });

  factory CdnDistribution.fromJson(Map<String, dynamic> json) =>
      CdnDistribution(
        id: json['id'] ?? '',
        domain: json['domain'] ?? '',
        aliases: (json['aliases'] as List?)?.cast<String>() ?? [],
        status: json['status'] ?? '',
        enabled: json['enabled'] ?? false,
        origin: json['origin'] ?? '',
      );
}

class ResourceSummary {
  final List<RdsInstance> databases;
  final List<LoadBalancer> loadBalancers;
  final int cloudfrontDistributions;
  final int alarmsTotal;
  final int alarmsOk;
  final int alarmsFiring;

  ResourceSummary({
    required this.databases,
    required this.loadBalancers,
    required this.cloudfrontDistributions,
    required this.alarmsTotal,
    required this.alarmsOk,
    required this.alarmsFiring,
  });

  factory ResourceSummary.fromJson(Map<String, dynamic> json) =>
      ResourceSummary(
        databases: (json['databases'] as List? ?? [])
            .map((d) => RdsInstance.fromJson(d))
            .toList(),
        loadBalancers: (json['load_balancers'] as List? ?? [])
            .map((lb) => LoadBalancer.fromJson(lb))
            .toList(),
        cloudfrontDistributions: json['cloudfront_distributions'] ?? 0,
        alarmsTotal: json['alarms_total'] ?? 0,
        alarmsOk: json['alarms_ok'] ?? 0,
        alarmsFiring: json['alarms_firing'] ?? 0,
      );
}
