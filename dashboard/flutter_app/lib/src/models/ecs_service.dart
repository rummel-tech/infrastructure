class EcsService {
  final String name;
  final int port;
  final String environment;
  final String status;
  final int runningCount;
  final int desiredCount;

  EcsService({
    required this.name,
    required this.port,
    required this.environment,
    required this.status,
    required this.runningCount,
    required this.desiredCount,
  });

  factory EcsService.fromJson(Map<String, dynamic> json) => EcsService(
        name: json['name'] ?? '',
        port: json['port'] ?? 0,
        environment: json['environment'] ?? '',
        status: json['status'] ?? 'unknown',
        runningCount: json['running_count'] ?? 0,
        desiredCount: json['desired_count'] ?? 0,
      );

  bool get isHealthy => status == 'healthy';
  bool get isDegraded => status == 'degraded';
  bool get isDown => status == 'down' || status == 'not_deployed';
}
