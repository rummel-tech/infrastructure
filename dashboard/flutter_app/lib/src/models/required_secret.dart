class RequiredSecret {
  final String name;
  final String service;
  final String key;
  final String description;
  final String status; // 'set' | 'placeholder' | 'missing'

  const RequiredSecret({
    required this.name,
    required this.service,
    required this.key,
    required this.description,
    required this.status,
  });

  factory RequiredSecret.fromJson(Map<String, dynamic> json) => RequiredSecret(
        name: json['name'] ?? '',
        service: json['service'] ?? '',
        key: json['key'] ?? '',
        description: json['description'] ?? '',
        status: json['status'] ?? 'missing',
      );

  bool get isSet => status == 'set';
  bool get isPlaceholder => status == 'placeholder';
  bool get isMissing => status == 'missing';
}

class RequiredSecretsSummary {
  final int total;
  final int set;
  final int placeholder;
  final int missing;
  final bool ready;

  const RequiredSecretsSummary({
    required this.total,
    required this.set,
    required this.placeholder,
    required this.missing,
    required this.ready,
  });

  factory RequiredSecretsSummary.fromJson(Map<String, dynamic> json) =>
      RequiredSecretsSummary(
        total: json['total'] ?? 0,
        set: json['set'] ?? 0,
        placeholder: json['placeholder'] ?? 0,
        missing: json['missing'] ?? 0,
        ready: json['ready'] ?? false,
      );
}
