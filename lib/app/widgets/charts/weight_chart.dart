import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../data/repos/trends_repo.dart';
import '../../design/design.dart';
import '../pet_card.dart';
import '../pet_section_header.dart';

/// Phase 6 task 6.12 — weight time-series chart for the SOUL profile.
///
/// Renders [WeightObservation] points as a sage-tinted line chart
/// with circular dots at each measurement. Thin axis grid lines for
/// readability. Empty / single-point states render a calm "not enough
/// data" message rather than a blank canvas.
///
/// The widget is layout-naive — it sizes to its width and a fixed
/// 180dp height. Wrap in PetCard in the calling layout for surface
/// treatment.
class WeightChart extends StatelessWidget {
  const WeightChart({super.key, required this.observations});
  final List<WeightObservation> observations;

  @override
  Widget build(BuildContext context) {
    return PetCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PetSectionHeader(title: 'Weight over time'),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.m,
              0,
              Spacing.m,
              Spacing.m,
            ),
            child: SizedBox(
              height: 180,
              child: _buildBody(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (observations.length < 2) {
      return Center(
        child: Text(
          observations.isEmpty
              ? 'Log a weight in chat — "Loki weighed 14.2 kg today"'
                  ' — and the trend will appear here.'
              : 'One measurement so far — log another to see the trend.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.6),
              ),
        ),
      );
    }
    final points = <FlSpot>[
      for (var i = 0; i < observations.length; i++)
        FlSpot(
          observations[i].ts.millisecondsSinceEpoch.toDouble(),
          observations[i].kg,
        ),
    ];
    final minX = points.first.x;
    final maxX = points.last.x;
    var minY = points.map((p) => p.y).reduce((a, b) => a < b ? a : b);
    var maxY = points.map((p) => p.y).reduce((a, b) => a > b ? a : b);
    // Pad the y-range so the line doesn't kiss the edges.
    final pad = (maxY - minY) * 0.15;
    minY = (minY - pad).clamp(0.0, double.infinity);
    maxY = maxY + pad;
    return LineChart(
      LineChartData(
        minX: minX,
        maxX: maxX,
        minY: minY,
        maxY: maxY,
        gridData: FlGridData(
          drawVerticalLine: false,
          horizontalInterval: ((maxY - minY) / 4).clamp(0.1, 10000),
          getDrawingHorizontalLine: (_) => FlLine(
            color: scheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          rightTitles: const AxisTitles(),
          topTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              interval: ((maxY - minY) / 4).clamp(0.1, 10000),
              getTitlesWidget: (value, _) => Text(
                value.toStringAsFixed(1),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.55),
                    ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: (maxX - minX) / 3,
              getTitlesWidget: (value, _) => Padding(
                padding: const EdgeInsets.only(top: Spacing.xs),
                child: Text(
                  _formatX(value),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.55),
                      ),
                ),
              ),
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: points,
            color: scheme.primary,
            dotData: FlDotData(
              getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                radius: 3,
                color: scheme.primary,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              color: scheme.primary.withValues(alpha: 0.08),
            ),
          ),
        ],
      ),
    );
  }

  String _formatX(double msSinceEpoch) {
    final d = DateTime.fromMillisecondsSinceEpoch(
      msSinceEpoch.round(),
    );
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }
}
