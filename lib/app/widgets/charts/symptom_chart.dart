import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../data/repos/trends_repo.dart';
import '../../design/design.dart';
import '../pet_card.dart';
import '../pet_section_header.dart';

/// Phase 6 task 6.12 — symptom-frequency chart.
///
/// Horizontal-ish bar chart of how often each known symptom keyword
/// has appeared in the pet's journal. Renders one bar per
/// [SymptomFrequency], with the count to the right of the bar. Sorted
/// descending by [frequencies] (the repo handles ordering).
///
/// The data source is an FTS5 keyword query, NOT the red-flag screener
/// (CLAUDE.md §10 keeps the screener chat-only). This chart is a
/// retrospective "what's been on your mind lately" surface — never an
/// alert, never a diagnosis. If every count is 0 ("all clear"), the
/// chart shows a calm empty state.
class SymptomChart extends StatelessWidget {
  const SymptomChart({super.key, required this.frequencies});
  final List<SymptomFrequency> frequencies;

  @override
  Widget build(BuildContext context) {
    return PetCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PetSectionHeader(title: 'What’s come up'),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.m,
              0,
              Spacing.m,
              Spacing.m,
            ),
            child: _buildBody(context),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasAny = frequencies.any((f) => f.count > 0);
    if (!hasAny) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: Spacing.s),
        child: Text(
          'No vomiting, lethargy, scratching, limping, or diarrhea '
          'mentioned in the journal yet. PetPal will track these as '
          'they come up.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.6),
              ),
        ),
      );
    }
    final maxCount =
        frequencies.fold<int>(0, (m, f) => f.count > m ? f.count : m);
    return SizedBox(
      height: 24.0 * frequencies.length + 12,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: (maxCount + 1).toDouble(),
          barGroups: [
            for (var i = 0; i < frequencies.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: frequencies[i].count.toDouble(),
                    color: scheme.primary.withValues(alpha: 0.7),
                    width: 14,
                    borderRadius: const BorderRadius.all(
                      Radius.circular(2),
                    ),
                  ),
                ],
              ),
          ],
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            rightTitles: const AxisTitles(),
            topTitles: const AxisTitles(),
            leftTitles: const AxisTitles(),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (value, _) {
                  final i = value.round();
                  if (i < 0 || i >= frequencies.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: Spacing.xs),
                    child: Text(
                      '${frequencies[i].label} (${frequencies[i].count})',
                      style:
                          Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: scheme.onSurface
                                    .withValues(alpha: 0.55),
                              ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
