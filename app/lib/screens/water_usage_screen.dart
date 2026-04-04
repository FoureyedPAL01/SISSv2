// lib/screens/water_usage_screen.dart
//
// Water usage tracking with daily totals, trend charts, and activity log.

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/app_state_provider.dart';
import '../utils/unit_converter.dart';
import '../theme.dart';
import '../widgets/double_back_press_wrapper.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Data model
// ─────────────────────────────────────────────────────────────────────────────
class _DailyLog {
  final DateTime date;
  final double waterLitres;
  final int runtimeMinutes;
  final double efficiency;

  const _DailyLog({
    required this.date,
    required this.waterLitres,
    required this.runtimeMinutes,
    required this.efficiency,
  });
}

class _Acc {
  final DateTime date;
  double water = 0;
  int runtimeSecs = 0;
  bool rain = false;
  final List<double> mbList = [];
  final List<double> maList = [];
  _Acc(this.date);
}

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────
class WaterUsageScreen extends StatefulWidget {
  const WaterUsageScreen({super.key});

  @override
  State<WaterUsageScreen> createState() => _WaterUsageScreenState();
}

class _WaterUsageScreenState extends State<WaterUsageScreen> {
  bool _loading = true;
  String? _error;
  List<_DailyLog> _allLogs = [];
  List<_DailyLog> _weekFull = [];

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  double _calcEfficiency({
    required double waterLitres,
    required int runtimeMinutes,
    double? moistureBefore,
    double? moistureAfter,
    bool rainDetected = false,
  }) {
    double mScore = 50.0;
    if (moistureBefore != null && moistureAfter != null) {
      final gain = (moistureAfter - moistureBefore).clamp(0.0, 40.0);
      mScore = (gain / 40.0) * 100.0;
    }

    double wScore = 70.0;
    if (runtimeMinutes > 0) {
      final lpm = waterLitres / runtimeMinutes;
      wScore = ((1.0 - (lpm - 1.5).abs() / 3.0).clamp(0.0, 1.0)) * 100.0;
    }

    final rainBonus = rainDetected ? 100.0 : 0.0;
    return (0.4 * mScore + 0.4 * wScore + 0.2 * rainBonus).clamp(0.0, 100.0);
  }

  Future<void> _fetchData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final deviceId = context.read<AppStateProvider>().deviceId;
      if (deviceId == null) {
        setState(() => _loading = false);
        return;
      }

      final cutoff14 = DateTime.now().subtract(const Duration(days: 14));

      final rows =
          await Supabase.instance.client
                  .from('pump_logs')
                  .select(
                    'pump_on_at, duration_seconds, water_used_litres, '
                    'moisture_before, moisture_after, rain_detected',
                  )
                  .eq('device_id', deviceId)
                  .gte('pump_on_at', cutoff14.toIso8601String())
                  .order('pump_on_at', ascending: true)
              as List<dynamic>;

      final Map<String, _Acc> acc = {};

      for (final dynamic r in rows) {
        final row = r as Map<String, dynamic>;
        final dt = DateTime.parse(row['pump_on_at'] as String).toLocal();
        final key =
            '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

        acc.putIfAbsent(key, () => _Acc(DateTime(dt.year, dt.month, dt.day)));
        final a = acc[key]!;

        a.water += (row['water_used_litres'] as num?)?.toDouble() ?? 0.0;
        a.runtimeSecs += (row['duration_seconds'] as num?)?.toInt() ?? 0;
        if (row['rain_detected'] == true) a.rain = true;
        if (row['moisture_before'] != null) {
          a.mbList.add((row['moisture_before'] as num).toDouble());
        }
        if (row['moisture_after'] != null) {
          a.maList.add((row['moisture_after'] as num).toDouble());
        }
      }

      double avg(List<double> l) =>
          l.isEmpty ? 0 : l.reduce((x, y) => x + y) / l.length;

      final logs =
          acc.values
              .map(
                (a) => _DailyLog(
                  date: a.date,
                  waterLitres: a.water,
                  runtimeMinutes: a.runtimeSecs ~/ 60,
                  efficiency: _calcEfficiency(
                    waterLitres: a.water,
                    runtimeMinutes: a.runtimeSecs ~/ 60,
                    moistureBefore: a.mbList.isEmpty ? null : avg(a.mbList),
                    moistureAfter: a.maList.isEmpty ? null : avg(a.maList),
                    rainDetected: a.rain,
                  ),
                ),
              )
              .toList()
            ..sort((a, b) => a.date.compareTo(b.date));

      final today = DateTime.now();
      final weekFull = List.generate(7, (i) {
        final day = DateTime(
          today.year,
          today.month,
          today.day,
        ).subtract(Duration(days: 6 - i));
        return logs.firstWhere(
          (l) =>
              l.date.year == day.year &&
              l.date.month == day.month &&
              l.date.day == day.day,
          orElse: () => _DailyLog(
            date: day,
            waterLitres: 0,
            runtimeMinutes: 0,
            efficiency: 0,
          ),
        );
      });

      if (!mounted) return;
      setState(() {
        _allLogs = logs;
        _weekFull = weekFull;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load data: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final appColors = Theme.of(context).extension<AppColors>()!;

    return DoubleBackPressWrapper(
      child: Scaffold(
        backgroundColor: colors.surfaceContainerHighest,
        body: RefreshIndicator(
          color: colors.primary,
          onRefresh: _fetchData,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? _buildError(colors)
              : _buildBody(colors: colors, appColors: appColors),
        ),
      ),
    );
  }

  Widget _buildError(ColorScheme colors) => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.warning, color: colors.error, size: 40),
        const SizedBox(height: 8),
        Text(_error!, textAlign: TextAlign.center),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _fetchData,
          icon: const Icon(Icons.refresh),
          label: const Text('Retry'),
        ),
      ],
    ),
  );

  Widget _buildBody({
    required ColorScheme colors,
    required AppColors appColors,
  }) {
    final muted = colors.onSurface.withValues(alpha: 0.5);
    final volUnit = context.read<AppStateProvider>().volumeUnit;

    // Aggregate stats
    final totalL = _weekFull.fold(0.0, (s, l) => s + l.waterLitres);
    final totalM = _weekFull.fold(0, (s, l) => s + l.runtimeMinutes);
    final avgDayL = totalL / 7.0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 36),
      children: [
        // Summary row
        _SummaryRow(
          totalWater: UnitConverter.formatVolume(totalL, volUnit),
          avgDaily: UnitConverter.formatVolume(avgDayL, volUnit),
          totalRuntime: '${(totalM / 60.0).toStringAsFixed(1)} hrs',
          colors: colors,
        ),
        const SizedBox(height: 16),

        // Bar chart
        _WeeklyBarChart(
          weekFull: _weekFull,
          colors: colors,
          appColors: appColors,
          muted: muted,
          volUnit: volUnit,
        ),
        const SizedBox(height: 16),

        // Daily log
        _DailyLogTable(
          allLogs: _allLogs,
          colors: colors,
          muted: muted,
          volUnit: volUnit,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Summary row — 3 compact stat pills
// ─────────────────────────────────────────────────────────────────────────────

class _SummaryRow extends StatelessWidget {
  final String totalWater;
  final String avgDaily;
  final String totalRuntime;
  final ColorScheme colors;

  const _SummaryRow({
    required this.totalWater,
    required this.avgDaily,
    required this.totalRuntime,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _StatItem(
            icon: Icons.water_drop_rounded,
            value: totalWater,
            label: 'Total (7d)',
            color: const Color(0xFF4A90E2),
            colors: colors,
          ),
          _divider(colors),
          _StatItem(
            icon: Icons.show_chart_rounded,
            value: avgDaily,
            label: 'Avg/Day',
            color: const Color(0xFF4CAF50),
            colors: colors,
          ),
          _divider(colors),
          _StatItem(
            icon: Icons.timer_rounded,
            value: totalRuntime,
            label: 'Runtime (7d)',
            color: const Color(0xFF7C3AED),
            colors: colors,
          ),
        ],
      ),
    );
  }

  Widget _divider(ColorScheme colors) => Container(
    height: 32,
    width: 1,
    color: colors.onSurface.withValues(alpha: 0.1),
  );
}

class _StatItem extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;
  final ColorScheme colors;

  const _StatItem({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: colors.onSurface,
            fontSize: 14,
            fontWeight: FontWeight.bold,
            fontFamily: 'Poppins',
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            color: colors.onSurface.withValues(alpha: 0.5),
            fontSize: 9,
            fontFamily: 'Poppins',
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Weekly bar chart — daily water usage
// ─────────────────────────────────────────────────────────────────────────────

class _WeeklyBarChart extends StatelessWidget {
  final List<_DailyLog> weekFull;
  final ColorScheme colors;
  final AppColors appColors;
  final Color muted;
  final String volUnit;

  const _WeeklyBarChart({
    required this.weekFull,
    required this.colors,
    required this.appColors,
    required this.muted,
    required this.volUnit,
  });

  @override
  Widget build(BuildContext context) {
    if (weekFull.isEmpty) {
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
            Row(
              children: [
                Icon(
                  Icons.bar_chart_rounded,
                  color: appColors.infoBlue,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  'Daily Consumption',
                  style: TextStyle(
                    color: colors.onSurface,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Poppins',
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Center(
              child: Column(
                children: [
                  Icon(
                    Icons.water_drop_outlined,
                    size: 40,
                    color: colors.onSurface.withValues(alpha: 0.2),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No water usage this week',
                    style: TextStyle(
                      color: colors.onSurface.withValues(alpha: 0.6),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Poppins',
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Start your pump to see daily consumption.',
                    style: TextStyle(
                      color: colors.onSurface.withValues(alpha: 0.4),
                      fontSize: 12,
                      fontFamily: 'Poppins',
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final maxY = weekFull
        .map((e) => e.waterLitres)
        .reduce((a, b) => a > b ? a : b);
    final avgWater =
        weekFull.fold(0.0, (sum, log) => sum + log.waterLitres) /
        weekFull.length;
    final chartMaxY = (maxY * 1.3).clamp(1.0, double.infinity);

    return RepaintBoundary(
      child: Container(
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
            // Header with average
            Row(
              children: [
                Icon(
                  Icons.bar_chart_rounded,
                  color: appColors.infoBlue,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Daily Consumption',
                    style: TextStyle(
                      color: colors.onSurface,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Poppins',
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: appColors.infoBlue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Avg ${UnitConverter.formatVolume(avgWater, volUnit)}',
                    style: TextStyle(
                      color: appColors.infoBlue,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Poppins',
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Chart
            SizedBox(
              height: 200,
              child: LineChart(
                LineChartData(
                  minY: 0,
                  maxY: chartMaxY,
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipColor: (_) => colors.surfaceContainerHighest,
                      getTooltipItems: (touchedSpots) =>
                          touchedSpots.map((spot) {
                            final log = weekFull[spot.x.toInt()];
                            final water = UnitConverter.formatVolume(
                              log.waterLitres,
                              volUnit,
                            );
                            final dateStr = '${log.date.month}/${log.date.day}';
                            return LineTooltipItem(
                              '$dateStr\n$water',
                              TextStyle(
                                color: appColors.infoBlue,
                                fontSize: 11,
                                fontFamily: 'Poppins',
                                fontWeight: FontWeight.w600,
                                decoration: TextDecoration.none,
                              ),
                            );
                          }).toList(),
                    ),
                  ),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (v, _) {
                          final i = v.toInt();
                          if (i < 0 || i >= weekFull.length) {
                            return const SizedBox();
                          }
                          const abbr = [
                            'Mo',
                            'Tu',
                            'We',
                            'Th',
                            'Fr',
                            'Sa',
                            'Su',
                          ];
                          return Text(
                            abbr[weekFull[i].date.weekday - 1],
                            style: TextStyle(color: muted, fontSize: 11),
                          );
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        getTitlesWidget: (v, _) => Text(
                          v.toInt().toString(),
                          style: TextStyle(color: muted, fontSize: 10),
                        ),
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (_) => FlLine(
                      color: muted.withValues(alpha: 0.15),
                      strokeWidth: 1,
                      dashArray: const [4, 4],
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: weekFull
                          .asMap()
                          .entries
                          .map(
                            (e) =>
                                FlSpot(e.key.toDouble(), e.value.waterLitres),
                          )
                          .toList(),
                      isCurved: true,
                      curveSmoothness: 0.3,
                      color: appColors.infoBlue,
                      barWidth: 3,
                      isStrokeCapRound: true,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, barData, index) =>
                            FlDotCirclePainter(
                              radius: 5,
                              color: weekFull[index].waterLitres > 0
                                  ? appColors.infoBlue
                                  : appColors.infoBlue.withValues(alpha: 0.3),
                              strokeWidth: 2,
                              strokeColor: colors.surface,
                            ),
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            appColors.infoBlue.withValues(alpha: 0.25),
                            appColors.infoBlue.withValues(alpha: 0.02),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Daily log table — compact, scrollable
// ─────────────────────────────────────────────────────────────────────────────

class _DailyLogTable extends StatelessWidget {
  final List<_DailyLog> allLogs;
  final ColorScheme colors;
  final Color muted;
  final String volUnit;

  const _DailyLogTable({
    required this.allLogs,
    required this.colors,
    required this.muted,
    required this.volUnit,
  });

  @override
  Widget build(BuildContext context) {
    final rows = allLogs.reversed.toList();

    return Container(
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Icon(Icons.history_rounded, color: muted, size: 16),
                const SizedBox(width: 6),
                Text(
                  'Daily Log',
                  style: TextStyle(
                    color: colors.onSurface,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    fontFamily: 'Poppins',
                    decoration: TextDecoration.none,
                  ),
                ),
                const Spacer(),
                Text(
                  'Last 14 days',
                  style: TextStyle(
                    color: muted,
                    fontSize: 11,
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
          ),

          // Table header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text('DATE', style: _headerStyle(muted)),
                ),
                Expanded(
                  flex: 2,
                  child: Text('WATER', style: _headerStyle(muted)),
                ),
                Expanded(
                  flex: 2,
                  child: Text('TIME', style: _headerStyle(muted)),
                ),
                Expanded(
                  flex: 3,
                  child: Text('EFFICIENCY', style: _headerStyle(muted)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),

          // Rows
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text(
                  'No pump activity in the last 14 days.',
                  style: TextStyle(color: muted),
                ),
              ),
            )
          else
            ...rows.map((log) => _logRow(log, colors, muted)),

          const SizedBox(height: 8),
        ],
      ),
    );
  }

  TextStyle _headerStyle(Color muted) => TextStyle(
    color: muted,
    fontSize: 10,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.5,
  );

  Widget _logRow(_DailyLog log, ColorScheme colors, Color muted) {
    final dateStr =
        '${log.date.month.toString().padLeft(2, '0')}-${log.date.day.toString().padLeft(2, '0')}';
    final waterStr = UnitConverter.formatVolume(log.waterLitres, volUnit);
    final runtimeStr = log.runtimeMinutes >= 60
        ? '${(log.runtimeMinutes / 60.0).toStringAsFixed(1)}h'
        : '${log.runtimeMinutes}m';
    final effPct = log.efficiency.round();

    Color effColor;
    if (effPct >= 75) {
      effColor = AppTheme.teal;
    } else if (effPct >= 50) {
      effColor = const Color(0xFFF97316);
    } else {
      effColor = colors.error;
    }

    return Column(
      children: [
        Divider(height: 1, color: muted.withValues(alpha: 0.15)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              // Date
              Expanded(
                flex: 3,
                child: Text(
                  dateStr,
                  style: TextStyle(
                    color: colors.onSurface,
                    fontSize: 13,
                    fontFamily: 'Poppins',
                  ),
                ),
              ),
              // Water
              Expanded(
                flex: 2,
                child: Text(
                  waterStr,
                  style: TextStyle(
                    color: colors.onSurface,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Poppins',
                  ),
                ),
              ),
              // Runtime
              Expanded(
                flex: 2,
                child: Text(
                  runtimeStr,
                  style: TextStyle(
                    color: muted,
                    fontSize: 13,
                    fontFamily: 'Poppins',
                  ),
                ),
              ),
              // Efficiency
              Expanded(
                flex: 3,
                child: Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: log.efficiency / 100.0,
                          backgroundColor: muted.withValues(alpha: 0.15),
                          color: effColor,
                          minHeight: 6,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 30,
                      child: Text(
                        '$effPct%',
                        style: TextStyle(
                          color: effColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
