import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:your_app/models/tank_models.dart';
import 'package:your_app/tank_detail/widgets/mini_parameter_card.dart';

class TankOverviewTab extends StatelessWidget {
  const TankOverviewTab({
    super.key,
    required this.cardColor,
    required this.loading,
    required this.tank,
    required this.latestTemp,
    required this.latestPh,
    required this.latestTds,
    required this.series,
    required this.onSeriesChanged,
    required this.dismissedKeys,
    required this.onDismissWarningKey,
    required this.seriesColor,
    required this.spotsFor,
    required this.chartDataFor,
    required this.mostRecentReadingIdFor,
    required this.onCreateTaskForReading,
    required this.onRefreshAll,
  });

  final Color cardColor;
  final bool loading;
  final Tank tank;
  final ParameterReading? latestTemp;
  final ParameterReading? latestPh;
  final ParameterReading? latestTds;

  final ParamType series;
  final ValueChanged<ParamType> onSeriesChanged;

  final Set<String> dismissedKeys;
  final ValueChanged<String> onDismissWarningKey;

  final Color Function(ParamType) seriesColor;
  final List<FlSpot> Function(ParamType) spotsFor;
  final LineChartData Function(ParamType) chartDataFor;

  final String? Function(ParamType) mostRecentReadingIdFor;
  final void Function({String? readingId, String? suggestedTitle})
      onCreateTaskForReading;

  final Future<void> Function() onRefreshAll;

  static const _danger = Color(0xFFE74C3C);

  @override
  Widget build(BuildContext context) {
    final tiles = [
      latestTemp,
      latestPh,
      latestTds,
    ].whereType<ParameterReading>().toList();

    bool oor(ParameterReading r) =>
        r.value < r.goodRange.start || r.value > r.goodRange.end;
    String keyFor(ParameterReading r) =>
        '${r.type.name}@${r.timestamp.toIso8601String()}';

    final tempOOR = latestTemp != null &&
        oor(latestTemp!) &&
        !dismissedKeys.contains(keyFor(latestTemp!));
    final phOOR = latestPh != null &&
        oor(latestPh!) &&
        !dismissedKeys.contains(keyFor(latestPh!));
    final tdsOOR = latestTds != null &&
        oor(latestTds!) &&
        !dismissedKeys.contains(keyFor(latestTds!));

    return SafeArea(
      bottom: true,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          if (tiles.isNotEmpty)
            Row(
              children: List.generate(tiles.length, (i) {
                final reading = tiles[i];
                final selected = reading.type == series;
                final showBadge =
                    (reading.type == ParamType.temperature && tempOOR) ||
                        (reading.type == ParamType.ph && phOOR) ||
                        (reading.type == ParamType.tds && tdsOOR);
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: i == tiles.length - 1 ? 0 : 12,
                    ),
                    child: GestureDetector(
                      onTap: () => onSeriesChanged(reading.type),
                      child: MiniParameterCard(
                        reading: reading,
                        color: seriesColor(reading.type),
                        selected: selected,
                        showBadge: showBadge,
                      ),
                    ),
                  ),
                );
              }),
            )
          else
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'No recent measurements',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          const SizedBox(height: 12),

          // Warning banner
          _buildWarningBanner(
            tempOOR: tempOOR,
            phOOR: phOOR,
            tdsOOR: tdsOOR,
            keyFor: keyFor,
            oor: oor,
          ),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: SizedBox(
              height: 260,
              child: loading
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.teal),
                    )
                  : spotsFor(series).isEmpty
                      ? const Center(
                          child: Text(
                            'No data for selected parameter',
                            style: TextStyle(color: Colors.white54),
                          ),
                        )
                      : LineChart(chartDataFor(series)),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white24),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: onRefreshAll,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh'),
          ),
        ],
      ),
    );
  }

  Widget _buildWarningBanner({
    required bool tempOOR,
    required bool phOOR,
    required bool tdsOOR,
    required String Function(ParameterReading) keyFor,
    required bool Function(ParameterReading) oor,
  }) {
    ParameterReading? r;
    if (series == ParamType.temperature) r = latestTemp;
    if (series == ParamType.ph) r = latestPh;
    if (series == ParamType.tds) r = latestTds;
    if (r == null) return const SizedBox.shrink();

    final isOOR = oor(r);
    final k = keyFor(r);
    if (!isOOR || dismissedKeys.contains(k)) {
      return const SizedBox.shrink();
    }

    final text =
        '${_labelForParam(r.type)} out of range: ${_formatValue(r)} (${r.unit}). Target ${_formatRange(r.goodRange)}';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _danger.withOpacity(0.12),
        border: Border.all(color: _danger),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: const [
            Icon(Icons.error_outline, color: _danger),
            SizedBox(width: 8),
            Text(
              'Warning',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Text(
            text,
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white24),
                ),
                onPressed: () => onDismissWarningKey(k),
                child: const Text('Dismiss'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () {
                  final title =
                      'Fix ${_labelForParam(r!.type)} (${_formatValue(r)} ${r.unit}) • Target ${_formatRange(r.goodRange)}';
                  final readingId = mostRecentReadingIdFor(series);
                  onCreateTaskForReading(
                    suggestedTitle: title,
                    readingId: readingId,
                  );
                },
                icon: const Icon(Icons.add_task),
                label: const Text('Set Task'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _labelForParam(ParamType t) =>
      t == ParamType.temperature ? 'Temperature' : t == ParamType.ph ? 'pH' : 'TDS';

  static String _formatRange(RangeValues r) =>
      '${r.start.toStringAsFixed(1)}–${r.end.toStringAsFixed(1)}';

  static String _formatValue(ParameterReading r) {
    if (r.type == ParamType.ph) return r.value.toStringAsFixed(2);
    if (r.type == ParamType.tds) return r.value.toStringAsFixed(0);
    return r.value.toStringAsFixed(1);
  }
}
