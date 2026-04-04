import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state_provider.dart';
import '../widgets/double_back_press_wrapper.dart';

/// Irrigation history screen — shows soil moisture trends with context.
///
/// Layout:
/// 1. Summary card with current status, weekly average, and readings count
/// 2. Weekly line chart with dry/wet threshold bands
/// 3. Daily average cards showing day-over-day trends
class IrrigationScreen extends StatefulWidget {
  const IrrigationScreen({super.key});

  @override
  State<IrrigationScreen> createState() => _IrrigationScreenState();
}

class _IrrigationScreenState extends State<IrrigationScreen> {
  static const double _kDryThreshold = 30.0;
  static const double _kWetThreshold = 70.0;

  // ── Data processing ───────────────────────────────────────────────────────

  /// Returns all readings from the current ISO week (Mon–Sun), sorted oldest → newest.
  List<Map<String, dynamic>> _weekReadings(List<Map<String, dynamic>> history) {
    final now = DateTime.now();
    final weekStart = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - 1));

    return history.where((row) {
      final t = DateTime.tryParse((row['recorded_at'] ?? '').toString());
      if (t == null) return false;
      return !t.toLocal().isBefore(weekStart);
    }).toList()..sort((a, b) {
      final ta = DateTime.parse(a['recorded_at'] as String);
      final tb = DateTime.parse(b['recorded_at'] as String);
      return ta.compareTo(tb);
    });
  }

  /// Groups readings by calendar day and computes the daily average.
  Map<String, double> _dailyAverages(List<Map<String, dynamic>> readings) {
    final todayStr = _dateKey(DateTime.now());
    final Map<String, List<double>> buckets = {};

    for (final row in readings) {
      final t = DateTime.tryParse(
        (row['recorded_at'] ?? '').toString(),
      )?.toLocal();
      final v = (row['soil_moisture'] as num?)?.toDouble();
      if (t == null || v == null) continue;
      final key = _dateKey(t);
      if (key == todayStr) continue;
      buckets.putIfAbsent(key, () => []).add(v);
    }

    return {
      for (final e in buckets.entries)
        e.key: e.value.reduce((a, b) => a + b) / e.value.length,
    };
  }

  String _dateKey(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  /// Converts sorted readings to [FlSpot]s.
  List<FlSpot> _toSpots(List<Map<String, dynamic>> readings) {
    if (readings.isEmpty) return const [];
    final base = DateTime.parse(
      readings.first['recorded_at'] as String,
    ).toLocal();
    return readings.map((row) {
      final t = DateTime.parse(row['recorded_at'] as String).toLocal();
      final v = ((row['soil_moisture'] as num?)?.toDouble() ?? 0).clamp(
        0.0,
        100.0,
      );
      return FlSpot(t.difference(base).inMinutes.toDouble(), v);
    }).toList();
  }

  /// Readable time label from a minute offset.
  String _timeLabel(List<Map<String, dynamic>> readings, double minutes) {
    if (readings.isEmpty) return '';
    final base = DateTime.parse(
      readings.first['recorded_at'] as String,
    ).toLocal();
    final t = base.add(Duration(minutes: minutes.round()));
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  /// Returns the most recent reading's moisture value, or null.
  double? _latestMoisture(List<Map<String, dynamic>> readings) {
    if (readings.isEmpty) return null;
    return (readings.last['soil_moisture'] as num?)?.toDouble();
  }

  /// Returns the average of all readings, or null.
  double? _weeklyAverage(List<Map<String, dynamic>> readings) {
    if (readings.isEmpty) return null;
    final sum = readings.fold<double>(0, (acc, r) {
      return acc + ((r['soil_moisture'] as num?)?.toDouble() ?? 0);
    });
    return sum / readings.length;
  }

  /// Returns a human-readable status based on moisture value.
  String _moistureStatus(double? value) {
    if (value == null) return 'No data';
    if (value < _kDryThreshold) return 'Too Dry';
    if (value > _kWetThreshold) return 'Well Watered';
    return 'Optimal';
  }

  Color _moistureStatusColor(double? value, ColorScheme colors) {
    if (value == null) return colors.onSurface.withValues(alpha: 0.4);
    if (value < _kDryThreshold) return const Color(0xFFEF5350);
    if (value > _kWetThreshold) return const Color(0xFF4A90E2);
    return const Color(0xFF4CAF50);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppStateProvider>();
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final weekReadings = _weekReadings(state.sensorHistory);
    final spots = _toSpots(weekReadings);
    final dailyAvg = _dailyAverages(weekReadings);
    final latestMoisture = _latestMoisture(weekReadings);
    final weeklyAvg = _weeklyAverage(weekReadings);
    final status = _moistureStatus(latestMoisture);
    final statusColor = _moistureStatusColor(latestMoisture, colors);

    return DoubleBackPressWrapper(
      child: Scaffold(
        backgroundColor: colors.surfaceContainerHighest,
        body: RefreshIndicator(
          onRefresh: state.refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 36),
            children: [
              // Page title
              Text(
                'Irrigation History',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontFamily: 'Poppins',
                  fontSize: 24,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Soil moisture trends and daily averages.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),

              // Summary card
              _SummaryCard(
                latestMoisture: latestMoisture,
                weeklyAvg: weeklyAvg,
                readingsCount: weekReadings.length,
                status: status,
                statusColor: statusColor,
                colors: colors,
              ),
              const SizedBox(height: 16),

              // Weekly chart
              _WeeklyChartCard(
                readings: weekReadings,
                spots: spots,
                colors: colors,
                onTimeLabel: _timeLabel,
              ),
              const SizedBox(height: 16),

              // Daily trend cards
              if (dailyAvg.isNotEmpty) ...[
                Text(
                  'Daily Averages',
                  style: TextStyle(
                    color: colors.onSurface,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Poppins',
                  ),
                ),
                const SizedBox(height: 12),
                _DailyTrendSection(
                  dailyAvg: dailyAvg,
                  isDark: isDark,
                  colors: colors,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Summary card — current status at a glance
// ─────────────────────────────────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  final double? latestMoisture;
  final double? weeklyAvg;
  final int readingsCount;
  final String status;
  final Color statusColor;
  final ColorScheme colors;

  const _SummaryCard({
    required this.latestMoisture,
    required this.weeklyAvg,
    required this.readingsCount,
    required this.status,
    required this.statusColor,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.water_drop_rounded, color: statusColor, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  status,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Poppins',
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  latestMoisture != null
                      ? '${latestMoisture!.toStringAsFixed(1)}% current'
                      : 'No recent readings',
                  style: TextStyle(
                    color: colors.onSurface,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Poppins',
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Avg ${weeklyAvg != null ? "${weeklyAvg!.toStringAsFixed(0)}%" : "—"}',
                  style: TextStyle(
                    color: colors.onPrimaryContainer,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Poppins',
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$readingsCount readings',
                style: TextStyle(
                  color: colors.onSurface.withValues(alpha: 0.5),
                  fontSize: 11,
                  fontFamily: 'Poppins',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Weekly chart card — line chart with threshold bands
// ─────────────────────────────────────────────────────────────────────────────

class _WeeklyChartCard extends StatelessWidget {
  final List<Map<String, dynamic>> readings;
  final List<FlSpot> spots;
  final ColorScheme colors;
  final String Function(List<Map<String, dynamic>>, double) onTimeLabel;

  const _WeeklyChartCard({
    required this.readings,
    required this.spots,
    required this.colors,
    required this.onTimeLabel,
  });

  @override
  Widget build(BuildContext context) {
    final muted = colors.onSurface.withValues(alpha: 0.4);
    final gridLine = colors.onSurface.withValues(alpha: 0.07);
    final maxX = spots.isEmpty ? 1.0 : spots.last.x;

    // Determine a good x-axis interval
    double interval;
    if (maxX <= 60) {
      interval = 15;
    } else if (maxX <= 180) {
      interval = 30;
    } else if (maxX <= 360) {
      interval = 60;
    } else if (maxX <= 720) {
      interval = 120;
    } else {
      interval = 240;
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(
                Icons.show_chart_rounded,
                color: const Color(0xFF4A90E2),
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                'Moisture Trend',
                style: TextStyle(
                  color: colors.onSurface,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Poppins',
                ),
              ),
              const Spacer(),
              _LegendItem(
                color: const Color(0xFFEF5350),
                label: 'Dry',
                muted: muted,
              ),
              const SizedBox(width: 12),
              _LegendItem(
                color: const Color(0xFF4CAF50),
                label: 'Optimal',
                muted: muted,
              ),
              const SizedBox(width: 12),
              _LegendItem(
                color: const Color(0xFF4A90E2),
                label: 'Wet',
                muted: muted,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Chart
          SizedBox(
            height: 200,
            child: spots.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.water_drop_outlined,
                          size: 40,
                          color: colors.onSurface.withValues(alpha: 0.2),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No readings this week',
                          style: TextStyle(
                            color: colors.onSurface.withValues(alpha: 0.6),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Poppins',
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Start your ESP32 device to see data.',
                          style: TextStyle(
                            color: colors.onSurface.withValues(alpha: 0.4),
                            fontSize: 12,
                            fontFamily: 'Poppins',
                          ),
                        ),
                      ],
                    ),
                  )
                : RepaintBoundary(
                    child: LineChart(
                      LineChartData(
                        minX: 0,
                        maxX: maxX,
                        minY: 0,
                        maxY: 100,
                        clipData: const FlClipData.all(),
                        borderData: FlBorderData(show: false),
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                          horizontalInterval: 25,
                          getDrawingHorizontalLine: (_) => FlLine(
                            color: gridLine,
                            strokeWidth: 1,
                            dashArray: const [4, 4],
                          ),
                        ),
                        extraLinesData: ExtraLinesData(
                          horizontalLines: [
                            HorizontalLine(
                              y: 30,
                              color: const Color(
                                0xFFEF5350,
                              ).withValues(alpha: 0.5),
                              strokeWidth: 1.5,
                              dashArray: const [6, 4],
                            ),
                            HorizontalLine(
                              y: 70,
                              color: const Color(
                                0xFF4A90E2,
                              ).withValues(alpha: 0.5),
                              strokeWidth: 1.5,
                              dashArray: const [6, 4],
                            ),
                          ],
                        ),
                        titlesData: FlTitlesData(
                          topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 32,
                              interval: 25,
                              getTitlesWidget: (v, _) => Text(
                                '${v.toInt()}%',
                                style: TextStyle(
                                  color: muted,
                                  fontSize: 10,
                                  fontFamily: 'Poppins',
                                ),
                              ),
                            ),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 24,
                              interval: interval,
                              getTitlesWidget: (v, _) {
                                if (v % interval > 0.5) {
                                  return const SizedBox.shrink();
                                }
                                return Text(
                                  onTimeLabel(readings, v),
                                  style: TextStyle(
                                    color: muted,
                                    fontSize: 10,
                                    fontFamily: 'Poppins',
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        lineTouchData: LineTouchData(
                          touchTooltipData: LineTouchTooltipData(
                            getTooltipColor: (_) =>
                                colors.surfaceContainerHighest,
                            getTooltipItems: (spots) => spots
                                .map(
                                  (s) => LineTooltipItem(
                                    '${onTimeLabel(readings, s.x)}\n${s.y.toStringAsFixed(1)}%',
                                    TextStyle(
                                      color: colors.onSurface,
                                      fontSize: 12,
                                      fontFamily: 'Poppins',
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                        lineBarsData: [
                          LineChartBarData(
                            spots: spots,
                            isCurved: true,
                            curveSmoothness: 0.3,
                            color: const Color(0xFF4A90E2),
                            barWidth: 2.5,
                            isStrokeCapRound: true,
                            dotData: const FlDotData(show: false),
                            belowBarData: BarAreaData(
                              show: true,
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  const Color(
                                    0xFF4A90E2,
                                  ).withValues(alpha: 0.20),
                                  const Color(
                                    0xFF4A90E2,
                                  ).withValues(alpha: 0.02),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  final Color muted;

  const _LegendItem({
    required this.color,
    required this.label,
    required this.muted,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 3,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(color: muted, fontSize: 10, fontFamily: 'Poppins'),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Daily trend section — horizontal scrollable cards
// ─────────────────────────────────────────────────────────────────────────────

class _DailyTrendSection extends StatelessWidget {
  final Map<String, double> dailyAvg;
  final bool isDark;
  final ColorScheme colors;

  const _DailyTrendSection({
    required this.dailyAvg,
    required this.isDark,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final entries = dailyAvg.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return SizedBox(
      height: 110,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: entries.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final avg = entries[i].value;
          final label = _shortDayLabel(entries[i].key);

          // Trend arrow vs previous day
          Color trendColor = const Color(0xFF9E9E9E);
          IconData trendIcon = Icons.remove_rounded;
          if (i > 0) {
            final prev = entries[i - 1].value;
            final diff = avg - prev;
            if (diff > 2) {
              trendColor = const Color(0xFF4CAF50);
              trendIcon = Icons.trending_up_rounded;
            } else if (diff < -2) {
              trendColor = const Color(0xFFEF5350);
              trendIcon = Icons.trending_down_rounded;
            }
          }

          // Determine moisture zone color
          Color zoneColor;
          if (avg < 30) {
            zoneColor = const Color(0xFFEF5350);
          } else if (avg > 70) {
            zoneColor = const Color(0xFF4A90E2);
          } else {
            zoneColor = const Color(0xFF4CAF50);
          }

          return Container(
            width: 80,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: colors.onSurface.withValues(alpha: 0.6),
                    fontSize: 11,
                    fontFamily: 'Poppins',
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${avg.toStringAsFixed(0)}%',
                  style: TextStyle(
                    color: zoneColor,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Poppins',
                  ),
                ),
                const SizedBox(height: 4),
                Icon(trendIcon, color: trendColor, size: 16),
              ],
            ),
          );
        },
      ),
    );
  }

  String _shortDayLabel(String dateKey) {
    final dt = DateTime.tryParse(dateKey);
    if (dt == null) return '';
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[dt.weekday - 1];
  }
}
