// lib/screens/water_usage_screen.dart
//
// Changes from previous version:
//  1. Converted to StatefulWidget — fetches real data from Supabase pump_logs.
//  2. Added 4 stat blocks (Total Water, Avg Daily, Total Runtime, Avg Runtime/Day)
//     covering the last 7 days, placed above the weekly trend chart.
//  3. Added Pump Runtime bar chart (minutes/day) below the weekly trend chart.
//  4. Replaced old breakdown table with a styled Daily Log table showing
//     Date | Water Used | Runtime | Efficiency (coloured progress bar + %).
//  5. Daily Log shows up to the last 14 days; rows older than 14 days are
//     excluded client-side (the server-side purge job handles actual deletion).
//  6. Efficiency score formula: 40 % moisture improvement + 40 % water-rate
//     score + 20 % rain-contribution bonus, clamped 0–100.

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/app_state_provider.dart';
import '../utils/unit_converter.dart';
import '../theme.dart';
import '../widgets/double_back_press_wrapper.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Data model: one calendar day's aggregated pump activity
// ─────────────────────────────────────────────────────────────────────────────
class _DailyLog {
  final DateTime date;
  final double waterLitres; // total water used that day
  final int runtimeMinutes; // total pump-on time in minutes
  final double efficiency; // 0–100

  const _DailyLog({
    required this.date,
    required this.waterLitres,
    required this.runtimeMinutes,
    required this.efficiency,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Internal accumulator — collects multiple pump_log rows for the same day
// ─────────────────────────────────────────────────────────────────────────────
class _Acc {
  final DateTime date;
  double water = 0;
  int runtimeSecs = 0;
  bool rain = false;
  final List<double> mbList = []; // moisture_before samples
  final List<double> maList = []; // moisture_after  samples
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

  // _allLogs  → last 14 days (for Daily Log table)
  // _weekFull → exactly 7 slots (Mon–Sun of last 7 days, zero-filled if no data)
  List<_DailyLog> _allLogs = [];
  List<_DailyLog> _weekFull = [];

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  // ── Efficiency formula ────────────────────────────────────────────────────
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

  // ── Fetch + aggregate pump_logs ───────────────────────────────────────────
  Future<void> _fetchData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final deviceId = context.read<AppStateProvider>().deviceId;
      if (deviceId == null) {
        setState(() {
          _loading = false;
        });
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

      // ── Aggregate each pump-log row into its calendar day ─────────────────
      final Map<String, _Acc> acc = {};

      for (final dynamic r in rows) {
        final row = r as Map<String, dynamic>;
        final dt = DateTime.parse(row['pump_on_at'] as String).toLocal();
        final key =
            '${dt.year}-'
            '${dt.month.toString().padLeft(2, '0')}-'
            '${dt.day.toString().padLeft(2, '0')}';

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

      // ── Convert accumulators → _DailyLog objects ──────────────────────────
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

      // ── Build 7-slot week (zero-filled for empty days) ─────────────────
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

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final appColors = Theme.of(context).extension<AppColors>()!;
    final textTheme = Theme.of(context).textTheme;
    final volUnit = context.watch<AppStateProvider>().volumeUnit;

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
              : _buildBody(
                  colors: colors,
                  appColors: appColors,
                  textTheme: textTheme,
                  volUnit: volUnit,
                ),
        ),
      ),
    );
  }

  // ── Error state ───────────────────────────────────────────────────────────
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

  // ── Main content ──────────────────────────────────────────────────────────
  Widget _buildBody({
    required ColorScheme colors,
    required AppColors appColors,
    required TextTheme textTheme,
    required String volUnit,
  }) {
    // ── 7-day aggregate values for stat blocks ────────────────────────────
    final totalL = _weekFull.fold(0.0, (s, l) => s + l.waterLitres);
    final totalM = _weekFull.fold(0, (s, l) => s + l.runtimeMinutes);
    final avgDayL = totalL / 7.0;
    final avgDayM = totalM ~/ 7;

    final totalDisp = UnitConverter.formatVolume(totalL, volUnit);
    final avgDayDisp = UnitConverter.formatVolume(avgDayL, volUnit);
    final totalRtHrs = totalM / 60.0;

    // Muted text colour (semi-transparent on-surface)
    final muted = colors.onSurface.withValues(alpha: 0.5);

    final spots = _weekFull
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.efficiency.clamp(0, 100)))
        .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 36),
      children: [
        // ── Stat cards ──────────────────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: _StatCard(
                icon: Icons.water_drop,
                iconColor: appColors.infoBlue,
                value: totalDisp,
                label: 'TOTAL WATER (7d)',
                colors: colors,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatCard(
                icon: Icons.trending_up,
                iconColor: AppTheme.teal,
                value: avgDayDisp,
                label: 'AVG DAILY',
                colors: colors,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _StatCard(
                icon: Icons.timer,
                iconColor: const Color(0xFF7C3AED),
                value: '${totalRtHrs.toStringAsFixed(1)} hrs',
                label: 'TOTAL RUNTIME (7d)',
                colors: colors,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatCard(
                icon: Icons.access_time,
                iconColor: const Color(0xFFF59E0B),
                value: '$avgDayM min',
                label: 'AVG RUNTIME/DAY',
                colors: colors,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // ── Efficiency trend chart ──────────────────────────────────────
        _ChartCard(
          colors: colors,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ChartHeader(
                icon: Icons.show_chart,
                iconColor: appColors.infoBlue,
                title: 'Efficiency Trend',
                subtitle: 'Last 7 days',
                colors: colors,
                muted: muted,
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 200,
                child: LineChart(
                  LineChartData(
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      getDrawingHorizontalLine: (_) => FlLine(
                        color: muted.withValues(alpha: 0.25),
                        strokeWidth: 1,
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
                          getTitlesWidget: (v, _) {
                            final i = v.toInt();
                            if (i < 0 || i >= _weekFull.length) {
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
                              abbr[_weekFull[i].date.weekday - 1],
                              style: TextStyle(color: muted, fontSize: 11),
                            );
                          },
                        ),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 36,
                          getTitlesWidget: (v, _) => Text(
                            v.toInt().toString(),
                            style: TextStyle(color: muted, fontSize: 10),
                          ),
                        ),
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    lineBarsData: [
                      LineChartBarData(
                        spots: spots,
                        isCurved: true,
                        color: appColors.infoBlue,
                        barWidth: 3,
                        isStrokeCapRound: true,
                        dotData: const FlDotData(show: false),
                        belowBarData: BarAreaData(
                          show: true,
                          color: appColors.infoBlueBackground,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ── Pump Runtime bar chart ──────────────────────────────────────
        _buildBarChart(colors: colors, muted: muted),
        const SizedBox(height: 16),

        // ── Daily Log table ─────────────────────────────────────────────
        _buildDailyLogTable(colors: colors, muted: muted, volUnit: volUnit),
      ],
    );
  }

  // ── Pump Runtime — Bar Chart ──────────────────────────────────────────────
  Widget _buildBarChart({required ColorScheme colors, required Color muted}) {
    const barColor = AppTheme.teal;

    final groups = _weekFull
        .asMap()
        .entries
        .map(
          (e) => BarChartGroupData(
            x: e.key,
            barRods: [
              BarChartRodData(
                toY: e.value.runtimeMinutes.toDouble(),
                color: barColor,
                width: 18,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(4),
                ),
              ),
            ],
          ),
        )
        .toList();

    final maxRuntime = _weekFull.isEmpty
        ? 0
        : _weekFull
              .map((l) => l.runtimeMinutes)
              .reduce((a, b) => a > b ? a : b);
    final maxY = (maxRuntime * 1.35).ceilToDouble().clamp(
      30.0,
      double.infinity,
    );

    return _ChartCard(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ChartHeader(
            icon: Icons.timer,
            iconColor: barColor,
            title: 'Pump Runtime per Day',
            subtitle: 'Minutes',
            colors: colors,
            muted: muted,
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 180,
            child: BarChart(
              BarChartData(
                maxY: maxY,
                barGroups: groups,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: muted.withValues(alpha: 0.25),
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
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
                      getTitlesWidget: (v, _) {
                        final i = v.toInt();
                        if (i < 0 || i >= _weekFull.length) {
                          return const SizedBox();
                        }
                        const abbr = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];
                        return Text(
                          abbr[_weekFull[i].date.weekday - 1],
                          style: TextStyle(color: muted, fontSize: 11),
                        );
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 36,
                      getTitlesWidget: (v, _) => Text(
                        v.toInt().toString(),
                        style: TextStyle(color: muted, fontSize: 10),
                      ),
                    ),
                  ),
                ),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (group) => colors.surface,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                        BarTooltipItem(
                          '${rod.toY.toInt()} min',
                          TextStyle(
                            color: colors.onSurface,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Daily Log Table ───────────────────────────────────────────────────────
  Widget _buildDailyLogTable({
    required ColorScheme colors,
    required Color muted,
    required String volUnit,
  }) {
    final rows = _allLogs.reversed.toList();

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: muted.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Text(
                  'Daily Log',
                  style: TextStyle(
                    color: colors.onSurface,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const Spacer(),
                Text(
                  'Last 14 days',
                  style: TextStyle(color: muted, fontSize: 11),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _LogRowLayout(
              date: Text(
                'DATE',
                style: TextStyle(
                  color: muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              water: Text(
                'WATER USED',
                style: TextStyle(
                  color: muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              runtime: Text(
                'RUNTIME',
                style: TextStyle(
                  color: muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              efficiency: Text(
                'EFFICIENCY',
                style: TextStyle(
                  color: muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),

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
            ...rows.map(
              (log) => _buildLogRow(
                log: log,
                colors: colors,
                muted: muted,
                volUnit: volUnit,
              ),
            ),

          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // ── One row in the Daily Log table ────────────────────────────────────────
  Widget _buildLogRow({
    required _DailyLog log,
    required ColorScheme colors,
    required Color muted,
    required String volUnit,
  }) {
    final dateStr =
        '${log.date.year}-'
        '${log.date.month.toString().padLeft(2, '0')}-'
        '${log.date.day.toString().padLeft(2, '0')}';

    final waterStr = UnitConverter.formatVolume(log.waterLitres, volUnit);

    final runtimeStr = log.runtimeMinutes >= 60
        ? '${(log.runtimeMinutes / 60.0).toStringAsFixed(1)} hrs'
        : '${log.runtimeMinutes} min';

    final effPct = log.efficiency.round();

    final Color barColor;
    if (effPct >= 75) {
      barColor = AppTheme.teal;
    } else if (effPct >= 50) {
      barColor = const Color(0xFFF97316);
    } else {
      barColor = colors.error;
    }

    return Column(
      children: [
        Divider(height: 1, color: muted.withValues(alpha: 0.2)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: _LogRowLayout(
            date: Text(
              dateStr,
              style: TextStyle(color: colors.onSurface, fontSize: 13),
            ),
            water: Text(
              waterStr,
              style: TextStyle(
                color: colors.onSurface,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
            runtime: Text(
              runtimeStr,
              style: TextStyle(color: muted, fontSize: 13),
            ),
            efficiency: Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: log.efficiency / 100.0,
                      backgroundColor: muted.withValues(alpha: 0.2),
                      color: barColor,
                      minHeight: 8,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 34,
                  child: Text(
                    '$effPct%',
                    style: TextStyle(color: muted, fontSize: 12),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helper: enforces the 4-column proportions used by both header and data rows.
// flex: 3 | 2 | 2 | 3
// ─────────────────────────────────────────────────────────────────────────────
class _LogRowLayout extends StatelessWidget {
  final Widget date, water, runtime, efficiency;
  const _LogRowLayout({
    required this.date,
    required this.water,
    required this.runtime,
    required this.efficiency,
  });

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(flex: 3, child: date),
      Expanded(flex: 2, child: water),
      Expanded(flex: 2, child: runtime),
      Expanded(flex: 3, child: efficiency),
    ],
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable card wrapper for charts
// ─────────────────────────────────────────────────────────────────────────────
class _ChartCard extends StatelessWidget {
  final Widget child;
  final ColorScheme colors;
  const _ChartCard({required this.child, required this.colors});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: colors.surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: colors.onSurface.withValues(alpha: 0.1)),
    ),
    child: child,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable header row used inside chart cards
// ─────────────────────────────────────────────────────────────────────────────
class _ChartHeader extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title, subtitle;
  final ColorScheme colors;
  final Color muted;

  const _ChartHeader({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.colors,
    required this.muted,
  });

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, color: iconColor, size: 20),
      const SizedBox(width: 8),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.onSurface,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: muted, fontSize: 12),
            ),
          ],
        ),
      ),
    ],
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Stat block card widget (icon + large value + label)
// ─────────────────────────────────────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String value, label;
  final ColorScheme colors;

  const _StatCard({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: colors.surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: colors.onSurface.withValues(alpha: 0.1)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: iconColor, size: 20),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            color: colors.onSurface,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            color: colors.onSurface.withValues(alpha: 0.5),
            fontSize: 10,
          ),
        ),
      ],
    ),
  );
}
