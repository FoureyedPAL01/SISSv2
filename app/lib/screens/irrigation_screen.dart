import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state_provider.dart';
import '../widgets/double_back_press_wrapper.dart';

class IrrigationScreen extends StatefulWidget {
  const IrrigationScreen({super.key});

  @override
  State<IrrigationScreen> createState() => _IrrigationScreenState();
}

class _IrrigationScreenState extends State<IrrigationScreen> {
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppStateProvider>();
    final colors = Theme.of(context).colorScheme;
    final processed = _processHistory(state);

    return DoubleBackPressWrapper(
      child: Scaffold(
        backgroundColor: colors.surfaceContainerHighest,
        body: RefreshIndicator(
          onRefresh: state.refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 36),
            children: [_buildChartCard(colors, state, processed)],
          ),
        ),
      ),
    );
  }

  _ProcessedHistory _processHistory(AppStateProvider state) {
    if (state.deviceId == null) {
      return const _ProcessedHistory(spots: []);
    }

    final now = DateTime.now();
    final cutoff = now.subtract(const Duration(days: 7));
    final spots = <FlSpot>[];
    var invalidRows = 0;

    for (final row in state.sensorHistory) {
      final recordedAt = DateTime.tryParse(
        (row['recorded_at'] ?? '').toString(),
      );
      final moistureRaw = row['soil_moisture'];
      final moisture = moistureRaw is num
          ? moistureRaw.toDouble()
          : double.tryParse(moistureRaw?.toString() ?? '');

      if (recordedAt == null || moisture == null) {
        invalidRows++;
        continue;
      }

      final localRecordedAt = recordedAt.toLocal();
      if (localRecordedAt.isBefore(cutoff) || localRecordedAt.isAfter(now)) {
        continue;
      }

      final daysAgo = now.difference(localRecordedAt).inMinutes / (60 * 24);
      final x = (7.0 - daysAgo).clamp(0.0, 7.0).toDouble();
      final y = moisture.clamp(0.0, 100.0).toDouble();
      spots.add(FlSpot(x, y));
    }

    spots.sort((a, b) => a.x.compareTo(b.x));

    final error =
        spots.isEmpty &&
            state.sensorHistory.isNotEmpty &&
            invalidRows == state.sensorHistory.length
        ? 'Could not read moisture history from the available records.'
        : null;

    return _ProcessedHistory(spots: spots, error: error);
  }

  Widget _buildChartCard(
    ColorScheme colors,
    AppStateProvider state,
    _ProcessedHistory processed,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.water_drop_rounded, color: colors.primary),
                const SizedBox(width: 8),
                Text(
                  'Soil Moisture Trend (%)',
                  style: TextStyle(
                    color: colors.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 250,
              child: _buildChartBody(colors, state, processed),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChartBody(
    ColorScheme colors,
    AppStateProvider state,
    _ProcessedHistory processed,
  ) {
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (processed.error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline_rounded, color: colors.error, size: 40),
            const SizedBox(height: 8),
            Text(
              processed.error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.error),
            ),
          ],
        ),
      );
    }

    if (processed.spots.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.bar_chart_rounded,
              size: 48,
              color: colors.onSurface.withValues(alpha: 0.35),
            ),
            const SizedBox(height: 12),
            Text(
              state.deviceId == null ? 'No device linked' : 'No recent data',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: colors.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              state.deviceId == null
                  ? 'Link your ESP32 device to view irrigation history.'
                  : 'No soil moisture readings were found for the last 7 days.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.onSurface.withValues(alpha: 0.55)),
            ),
          ],
        ),
      );
    }

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: 7,
        minY: 0,
        maxY: 100,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: true,
          getDrawingHorizontalLine: (_) => FlLine(
            color: colors.outline.withValues(alpha: 0.2),
            strokeWidth: 1,
          ),
          getDrawingVerticalLine: (_) => FlLine(
            color: colors.outline.withValues(alpha: 0.2),
            strokeWidth: 1,
            dashArray: [4, 4],
          ),
        ),
        titlesData: FlTitlesData(
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 1,
              getTitlesWidget: (value, meta) {
                if (value < 1 || value > 7) {
                  return const SizedBox.shrink();
                }

                final day = DateTime.now().subtract(
                  Duration(days: (7 - value).round()),
                );
                const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

                return Text(
                  days[day.weekday - 1],
                  style: TextStyle(
                    fontSize: 10,
                    color: colors.onSurface.withValues(alpha: 0.45),
                  ),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 20,
              getTitlesWidget: (value, meta) => Text(
                '${value.toInt()}%',
                style: TextStyle(
                  fontSize: 10,
                  color: colors.onSurface.withValues(alpha: 0.45),
                ),
              ),
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: processed.spots,
            isCurved: true,
            color: colors.primary,
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) =>
                  FlDotCirclePainter(
                    radius: 3,
                    color: colors.primary,
                    strokeWidth: 1,
                    strokeColor: colors.surface,
                  ),
            ),
            belowBarData: BarAreaData(
              show: true,
              color: colors.primary.withValues(alpha: 0.15),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProcessedHistory {
  final List<FlSpot> spots;
  final String? error;

  const _ProcessedHistory({required this.spots, this.error});
}
