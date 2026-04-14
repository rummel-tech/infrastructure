class MonthlyCost {
  final String start;
  final String end;
  final double amount;
  final String unit;

  MonthlyCost({
    required this.start,
    required this.end,
    required this.amount,
    required this.unit,
  });

  factory MonthlyCost.fromJson(Map<String, dynamic> json) => MonthlyCost(
        start: json['start'] ?? '',
        end: json['end'] ?? '',
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        unit: json['unit'] ?? 'USD',
      );
}

class ServiceCost {
  final String name;
  final double amount;

  ServiceCost({required this.name, required this.amount});

  factory ServiceCost.fromJson(Map<String, dynamic> json) => ServiceCost(
        name: json['name'] ?? '',
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
      );
}

class DailyCost {
  final String date;
  final double amount;

  DailyCost({required this.date, required this.amount});

  factory DailyCost.fromJson(Map<String, dynamic> json) => DailyCost(
        date: json['date'] ?? '',
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
      );
}

class TagCost {
  final String tag;
  final double amount;

  TagCost({required this.tag, required this.amount});

  factory TagCost.fromJson(Map<String, dynamic> json) => TagCost(
        tag: json['tag'] ?? '',
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
      );
}

class CostForecast {
  final double forecastedAmount;
  final String unit;
  final String periodEnd;

  CostForecast({
    required this.forecastedAmount,
    required this.unit,
    required this.periodEnd,
  });

  factory CostForecast.fromJson(Map<String, dynamic> json) => CostForecast(
        forecastedAmount:
            (json['forecasted_amount'] as num?)?.toDouble() ?? 0,
        unit: json['unit'] ?? 'USD',
        periodEnd: json['period_end'] ?? '',
      );
}
