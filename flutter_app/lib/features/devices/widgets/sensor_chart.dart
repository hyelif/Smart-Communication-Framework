import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../widgets/app_theme.dart';
import '../device_list_controller.dart';

/// A line chart showing historical sensor data for one sensor type.
class SensorChart extends StatelessWidget {
  final SensorChartData data;

  const SensorChart({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.points.length < 2) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final color = data.color;
    final points = data.points;
    final minVal = points.map((p) => p.value).reduce((a, b) => a < b ? a : b);
    final maxVal = points.map((p) => p.value).reduce((a, b) => a > b ? a : b);
    final range = (maxVal - minVal).clamp(0.1, double.infinity);
    final padding = range * 0.15;

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
      decoration: BoxDecoration(
        color: StitchColors.surfaceLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withValues(alpha: 0.15),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title row
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 12),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${data.label} (${data.unit})',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                Text(
                  '${minVal.toStringAsFixed(1)} - ${maxVal.toStringAsFixed(1)} ${data.unit}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: StitchColors.onSurfaceVariant,
                    fontSize: 8,
                  ),
                ),
              ],
            ),
          ),
          // Chart
          SizedBox(
            height: 120,
            child: LineChart(
              LineChartData(
                minY: minVal - padding,
                maxY: maxVal + padding,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: range / 4,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: StitchColors.outlineVariant.withValues(alpha: 0.15),
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 36,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          value.toStringAsFixed(0),
                          style: const TextStyle(
                            color: StitchColors.onSurfaceVariant,
                            fontSize: 8,
                          ),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 20,
                      interval: points.length > 10
                          ? (points.length / 4).ceilToDouble()
                          : 1,
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (idx < 0 || idx >= points.length) {
                          return const SizedBox.shrink();
                        }
                        final time = points[idx].time;
                        return Text(
                          '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                          style: const TextStyle(
                            color: StitchColors.onSurfaceVariant,
                            fontSize: 8,
                          ),
                        );
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: List.generate(points.length,
                        (i) => FlSpot(i.toDouble(), points[i].value)),
                    isCurved: true,
                    color: color,
                    barWidth: 2,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: color.withValues(alpha: 0.08),
                    ),
                  ),
                ],
                lineTouchData: LineTouchData(
                  enabled: true,
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((spot) {
                        final idx = spot.spotIndex;
                        final val = points[idx].value.toStringAsFixed(1);
                        final time =
                            '${points[idx].time.hour.toString().padLeft(2, '0')}:${points[idx].time.minute.toString().padLeft(2, '0')}';
                        return LineTooltipItem(
                          '$val ${data.unit}\n$time',
                          TextStyle(
                            color: color,
                            fontWeight: FontWeight.w700,
                            fontSize: 10,
                          ),
                        );
                      }).toList();
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
