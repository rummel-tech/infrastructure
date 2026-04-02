class Secret {
  final String arn;
  final String name;
  final String environment;
  final String service;
  final String key;
  final String lastChanged;
  final String lastAccessed;
  final String description;
  final bool rotationEnabled;

  Secret({
    required this.arn,
    required this.name,
    required this.environment,
    required this.service,
    required this.key,
    this.lastChanged = '',
    this.lastAccessed = '',
    this.description = '',
    this.rotationEnabled = false,
  });

  factory Secret.fromJson(Map<String, dynamic> json) => Secret(
        arn: json['arn'] ?? '',
        name: json['name'] ?? '',
        environment: json['environment'] ?? '',
        service: json['service'] ?? '',
        key: json['key'] ?? '',
        lastChanged: json['last_changed'] ?? '',
        lastAccessed: json['last_accessed'] ?? '',
        description: json['description'] ?? '',
        rotationEnabled: json['rotation_enabled'] ?? false,
      );
}
