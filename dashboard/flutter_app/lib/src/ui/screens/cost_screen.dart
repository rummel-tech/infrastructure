import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rummel_blue_theme/rummel_blue_theme.dart';

import '../../providers/dashboard_provider.dart';
import '../../models/cost_data.dart';

class CostScreen extends StatelessWidget {
  const CostScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DashboardProvider>();
    final theme = Theme.of(context);

    final hasCostData = provider.monthlyCosts.isNotEmpty ||
        provider.serviceCosts.isNotEmpty ||
        provider.dailyCosts.isNotEmpty ||
        provider.tagCosts.isNotEmpty;

    return RefreshIndicator(
      onRefresh: () => provider.loadCosts(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Cloud Costs',
              style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary, letterSpacing: 1.2)),
          const SizedBox(height: 16),

          // Top-line metrics
          Row(
            children: [
              Expanded(child: _TotalCard(
                label: 'Last 30 Days',
                amount: provider.serviceCostsTotal,
              )),
              const SizedBox(width: 12),
              Expanded(child: _ForecastCard(forecast: provider.forecast)),
            ],
          ),
          const SizedBox(height: 16),

          // Daily trend
          if (provider.dailyCosts.isNotEmpty) ...[
            Text('Daily Trend (14 days)', style: theme.textTheme.titleSmall),
            const SizedBox(height: 12),
            _DailyTrendChart(days: provider.dailyCosts),
            const SizedBox(height: 24),
          ],

          // Monthly trend
          if (provider.monthlyCosts.isNotEmpty) ...[
            Text('Monthly Trend', style: theme.textTheme.titleSmall),
            const SizedBox(height: 12),
            _MonthlyChart(months: provider.monthlyCosts),
            const SizedBox(height: 24),
          ],

          // Cost by application (tag-based)
          if (provider.tagCosts.isNotEmpty) ...[
            Row(
              children: [
                Text('Cost by Application', style: theme.textTheme.titleSmall),
                const Spacer(),
                Text(
                  '\$${provider.tagCostsTotal.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _TagCostList(
              tags: provider.tagCosts,
              total: provider.tagCostsTotal,
            ),
            const SizedBox(height: 24),
          ],

          // Cost by AWS service
          if (provider.serviceCosts.isNotEmpty) ...[
            Row(
              children: [
                Text('Cost by AWS Service', style: theme.textTheme.titleSmall),
                const Spacer(),
                Text(
                  '\$${provider.serviceCostsTotal.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _ServiceCostList(
              services: provider.serviceCosts,
              total: provider.serviceCostsTotal,
            ),
          ],

          if (!hasCostData)
            const Padding(
              padding: EdgeInsets.all(48),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.attach_money, size: 48, color: Colors.grey),
                    SizedBox(height: 16),
                    Text('No cost data available',
                        style: TextStyle(color: Colors.grey)),
                    SizedBox(height: 8),
                    Text('Connect AWS credentials with Cost Explorer access',
                        style: TextStyle(color: Colors.grey, fontSize: 12)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TotalCard extends StatelessWidget {
  final String label;
  final double amount;
  const _TotalCard({required this.label, required this.amount});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.receipt_long, size: 16,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 6),
                Text(label,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Colors.grey[500], letterSpacing: 0.5)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '\$${amount.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text('USD', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
          ],
        ),
      ),
    );
  }
}

class _ForecastCard extends StatelessWidget {
  final CostForecast? forecast;
  const _ForecastCard({required this.forecast});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.trending_up, size: 16,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 6),
                Text('Month Forecast',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Colors.grey[500], letterSpacing: 0.5)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              forecast != null
                  ? '\$${forecast!.forecastedAmount.toStringAsFixed(2)}'
                  : '--',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              forecast != null ? 'Through ${forecast!.periodEnd}' : 'No forecast',
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }
}

class _DailyTrendChart extends StatelessWidget {
  final List<DailyCost> days;
  const _DailyTrendChart({required this.days});

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) return const SizedBox.shrink();

    final maxAmount = days.map((d) => d.amount).reduce((a, b) => a > b ? a : b);
    const maxHeight = 100.0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          height: maxHeight + 30,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < days.length; i++) ...[
                Expanded(
                  child: Tooltip(
                    message: '${days[i].date}\n\$${days[i].amount.toStringAsFixed(2)}',
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Container(
                          height: maxAmount > 0
                              ? (days[i].amount / maxAmount * maxHeight).clamp(2, maxHeight)
                              : 2,
                          decoration: BoxDecoration(
                            color: RummelBlueColors.primary500.withValues(alpha: 0.7),
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                          ),
                        ),
                        const SizedBox(height: 4),
                        if (i % 2 == 0)
                          Text(
                            days[i].date.substring(5),
                            style: TextStyle(fontSize: 8, color: Colors.grey[500]),
                          )
                        else
                          const SizedBox(height: 10),
                      ],
                    ),
                  ),
                ),
                if (i < days.length - 1) const SizedBox(width: 2),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MonthlyChart extends StatelessWidget {
  final List<MonthlyCost> months;
  const _MonthlyChart({required this.months});

  @override
  Widget build(BuildContext context) {
    if (months.isEmpty) return const SizedBox.shrink();

    final maxAmount = months.map((m) => m.amount).reduce((a, b) => a > b ? a : b);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            for (var i = 0; i < months.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 60,
                      child: Text(
                        months[i].start.substring(0, 7),
                        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                      ),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: maxAmount > 0 ? months[i].amount / maxAmount : 0,
                          minHeight: 16,
                          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                          color: RummelBlueColors.primary500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 70,
                      child: Text(
                        '\$${months[i].amount.toStringAsFixed(2)}',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TagCostList extends StatelessWidget {
  final List<TagCost> tags;
  final double total;
  const _TagCostList({required this.tags, required this.total});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          for (var i = 0; i < tags.length; i++) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(
                      tags[i].tag,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: total > 0 ? tags[i].amount / total : 0,
                        minHeight: 6,
                        backgroundColor: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        color: _tagColor(i),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 65,
                    child: Text(
                      '\$${tags[i].amount.toStringAsFixed(2)}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'monospace'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 40,
                    child: Text(
                      total > 0
                          ? '${(tags[i].amount / total * 100).round()}%'
                          : '',
                      textAlign: TextAlign.right,
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    ),
                  ),
                ],
              ),
            ),
            if (i < tags.length - 1) const Divider(height: 1),
          ],
        ],
      ),
    );
  }

  Color _tagColor(int index) {
    const colors = [
      RummelBlueColors.primary500,
      RummelBlueColors.success500,
      RummelBlueColors.warning500,
      Colors.teal,
      Colors.purple,
      Colors.orange,
      Colors.cyan,
      RummelBlueColors.error500,
    ];
    return colors[index % colors.length];
  }
}

class _ServiceCostList extends StatelessWidget {
  final List<ServiceCost> services;
  final double total;
  const _ServiceCostList({required this.services, required this.total});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          for (var i = 0; i < services.length; i++) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(
                      services[i].name,
                      style: const TextStyle(fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: total > 0 ? services[i].amount / total : 0,
                        minHeight: 6,
                        backgroundColor: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        color: _serviceColor(i),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 65,
                    child: Text(
                      '\$${services[i].amount.toStringAsFixed(2)}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'monospace'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 40,
                    child: Text(
                      total > 0
                          ? '${(services[i].amount / total * 100).round()}%'
                          : '',
                      textAlign: TextAlign.right,
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    ),
                  ),
                ],
              ),
            ),
            if (i < services.length - 1) const Divider(height: 1),
          ],
        ],
      ),
    );
  }

  Color _serviceColor(int index) {
    const colors = [
      RummelBlueColors.primary500,
      RummelBlueColors.success500,
      RummelBlueColors.warning500,
      RummelBlueColors.error500,
      Colors.teal,
      Colors.purple,
      Colors.orange,
      Colors.cyan,
    ];
    return colors[index % colors.length];
  }
}
