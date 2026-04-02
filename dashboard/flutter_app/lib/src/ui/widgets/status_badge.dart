import 'package:flutter/material.dart';
import 'package:rummel_blue_theme/rummel_blue_theme.dart';

class StatusBadge extends StatelessWidget {
  final String status;
  const StatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final (color, bgColor) = _colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            _label,
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  String get _label => status.replaceAll('_', ' ');

  (Color, Color) get _colors {
    switch (status) {
      case 'healthy':
      case 'success':
      case 'active':
      case 'running':
      case 'rotation':
        return (RummelBlueColors.success500, RummelBlueColors.success500.withValues(alpha: 0.15));
      case 'degraded':
      case 'warning':
      case 'timed_out':
      case 'action_required':
        return (RummelBlueColors.warning500, RummelBlueColors.warning500.withValues(alpha: 0.15));
      case 'down':
      case 'failure':
      case 'error':
      case 'stopped':
        return (RummelBlueColors.error500, RummelBlueColors.error500.withValues(alpha: 0.15));
      case 'in_progress':
      case 'queued':
      case 'pending':
        return (RummelBlueColors.primary500, RummelBlueColors.primary500.withValues(alpha: 0.15));
      default:
        return (Colors.grey, Colors.grey.withValues(alpha: 0.15));
    }
  }
}
