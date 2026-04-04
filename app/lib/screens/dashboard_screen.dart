// lib/screens/dashboard_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/app_state_provider.dart';
import '../services/mqtt_service.dart';
import '../utils/unit_converter.dart';
import '../widgets/double_back_press_wrapper.dart';

// ─── Data model ───────────────────────────────────────────────────────────────

class _ChartPoint {
  final DateTime time;
  final double value;
  const _ChartPoint(this.time, this.value);
}

// ─── DashboardScreen ──────────────────────────────────────────────────────────

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  static const Color _cMoisture = Color(0xFF4A90E2);
  static const Color _cTemp     = Color(0xFFE87722);
  static const Color _cHumid    = Color(0xFF7C6FCD);
  static const Color _cFlow     = Color(0xFF00B4C4);

  // ── Chart cache ───────────────────────────────────────────────────────────
  List<_ChartPoint> _cachedMoistHist = [];
  List<_ChartPoint> _cachedTempHist  = [];
  List<_ChartPoint> _cachedHumidHist = [];
  List<Map<String, dynamic>>? _lastHistory;

  void _updateChartCache(List<Map<String, dynamic>> history) {
    if (identical(history, _lastHistory)) return;
    _lastHistory      = history;
    _cachedMoistHist  = _buildSeries(history, 'soil_moisture');
    _cachedTempHist   = _buildSeries(history, 'temperature_c');
    _cachedHumidHist  = _buildSeries(history, 'humidity');
  }

  List<_ChartPoint> _buildSeries(
    List<Map<String, dynamic>> rows,
    String field,
  ) {
    final pts = rows
        .where((r) => r['recorded_at'] != null && r[field] != null)
        .map((r) => _ChartPoint(
              DateTime.parse(r['recorded_at'] as String).toLocal(),
              (r[field] as num).toDouble(),
            ))
        .toList()
      ..sort((a, b) => a.time.compareTo(b.time));
    return _downsample(pts, maxPoints: 24);
  }

  List<_ChartPoint> _downsample(List<_ChartPoint> data, {int maxPoints = 24}) {
    if (data.length <= maxPoints) return data;
    final result = <_ChartPoint>[];
    final step = (data.length - 1) / (maxPoints - 1);
    for (var i = 0; i < maxPoints; i++) {
      result.add(data[(i * step).round().clamp(0, data.length - 1)]);
    }
    return result;
  }

  // ─────────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colorScheme = Theme.of(context).colorScheme;
    final isDark      = Theme.of(context).brightness == Brightness.dark;
    final bg          = colorScheme.surfaceContainerHighest;
    final comp        = Theme.of(context).scaffoldBackgroundColor;
    final text        = colorScheme.onSurface;
    final muted       = text.withValues(alpha: 0.45);
    final btn         = colorScheme.primary;

    return Consumer<AppStateProvider>(
      builder: (context, state, _) {
        if (state.isLoading) {
          return Scaffold(
            backgroundColor: bg,
            body: Center(child: CircularProgressIndicator(color: btn)),
          );
        }
        if (state.deviceId == null) {
          return Scaffold(
            backgroundColor: bg,
            body: Center(
              child: Text(
                'No device linked to this account.',
                style: _ts(text, size: 15),
              ),
            ),
          );
        }

        // ── Latest sensor values ───────────────────────────────────────────
        final d           = state.latestSensorData;
        final recordedAt  = d['recorded_at'] != null
            ? DateTime.tryParse(d['recorded_at'] as String)
            : null;

        final isStale = recordedAt == null ||
            DateTime.now().difference(recordedAt) > const Duration(minutes: 5);

        final moisture = isStale ? null : (d['soil_moisture'] as num?)?.toDouble();
        final tempC    = isStale ? null : (d['temperature_c']  as num?)?.toDouble();
        final humidity = isStale ? null : (d['humidity']        as num?)?.toDouble();
        final flowRate = isStale ? null : (d['flow_litres']     as num?)?.toDouble();
        final isRaining = !isStale && d['rain_detected'] == true;

        final tempDisplay = tempC != null
            ? UnitConverter.formatTemp(tempC, state.tempUnit)
            : null;

        // ── Charts Data Filter: Past 3 days excluding current day ────────
        final now = DateTime.now();
        final startOfToday = DateTime(now.year, now.month, now.day);
        final startOf3DaysAgo = startOfToday.subtract(const Duration(days: 3));

        final filteredHistory = state.sensorHistory.where((row) {
          if (row['recorded_at'] == null) return false;
          final t = DateTime.tryParse(row['recorded_at'] as String)?.toLocal();
          if (t == null) return false;
          return t.isAfter(startOf3DaysAgo) && t.isBefore(startOfToday);
        }).toList();

        _updateChartCache(filteredHistory);

        return DoubleBackPressWrapper(
          child: Scaffold(
            backgroundColor: bg,
            body: RefreshIndicator(
              color: btn,
              backgroundColor: comp,
              onRefresh: state.refresh,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 36),
                child: LayoutBuilder(
                  builder: (_, constraints) {
                    final isDesktop = constraints.maxWidth >= 700;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildProfileCard(
                          comp: comp, text: text, muted: muted,
                          cropProfile: state.activeCropProfile,
                        ),
                        const SizedBox(height: 16),
                        _buildSensorCards(
                          isDark: isDark, comp: comp, text: text, muted: muted,
                          isDesktop: isDesktop,
                          moisture: moisture, tempC: tempC,
                          humidity: humidity, flowRate: flowRate,
                          tempDisplay: tempDisplay,
                        ),
                        const SizedBox(height: 16),
                        isDesktop
                            ? _buildStatusRowDesktop(
                                comp: comp, text: text, muted: muted,
                                btn: btn, isRaining: isRaining,
                              )
                            : _buildStatusRowMobile(
                                comp: comp, text: text, muted: muted,
                                btn: btn, isRaining: isRaining,
                              ),
                        const SizedBox(height: 16),
                        _MoistureChart(
                          data: _cachedMoistHist,
                          comp: comp, text: text, muted: muted,
                          accentColor: _cMoisture,
                        ),
                        const SizedBox(height: 16),
                        _TempHumidChart(
                          tempData: _cachedTempHist,
                          humidData: _cachedHumidHist,
                          comp: comp, text: text, muted: muted,
                          cTemp: _cTemp, cHumid: _cHumid,
                        ),
                        const SizedBox(height: 8),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Sensor cards grid ─────────────────────────────────────────────────────
  Widget _buildSensorCards({
    required bool isDark, required Color comp, required Color text,
    required Color muted, required bool isDesktop,
    double? moisture, double? tempC, double? humidity, double? flowRate,
    String? tempDisplay,
  }) {
    String fmt(double? v) => v != null ? v.toStringAsFixed(1) : '—';

    final tempVal  = tempDisplay != null
        ? (RegExp(r'^([\d.]+)(°[CF])$').firstMatch(tempDisplay)?.group(1) ?? fmt(tempC))
        : fmt(tempC);

    final tempUnit = tempDisplay != null
        ? (RegExp(r'^([\d.]+)(°[CF])$').firstMatch(tempDisplay)?.group(2) ?? '')
        : (tempC != null ? '°C' : '');

    final cards = [
      _SensorCard(
          cardKey: const ValueKey('sensor_moisture'),
          isDark: isDark, comp: comp, text: text, muted: muted,
          label: 'Moisture', displayValue: fmt(moisture), unit: '%',
          numericValue: moisture, accentColor: _cMoisture,
          icon: Icons.water_drop_rounded, gaugeMax: 100),
      _SensorCard(
          cardKey: const ValueKey('sensor_temperature'),
          isDark: isDark, comp: comp, text: text, muted: muted,
          label: 'Temperature', displayValue: tempC != null ? tempVal : '—',
          unit: tempC != null ? tempUnit : '', numericValue: tempC,
          accentColor: _cTemp, icon: Icons.thermostat_rounded, gaugeMax: 50),
      _SensorCard(
          cardKey: const ValueKey('sensor_humidity'),
          isDark: isDark, comp: comp, text: text, muted: muted,
          label: 'Humidity', displayValue: fmt(humidity), unit: '%',
          numericValue: humidity, accentColor: _cHumid,
          icon: Icons.cloud_rounded, gaugeMax: 100),
      _SensorCard(
          cardKey: const ValueKey('sensor_flow'),
          isDark: isDark, comp: comp, text: text, muted: muted,
          label: 'Flow rate', displayValue: fmt(flowRate), unit: 'L/min',
          numericValue: flowRate, accentColor: _cFlow,
          icon: Icons.graphic_eq_rounded, gaugeMax: 10),
    ];

    if (isDesktop) {
      return Row(
        children: List.generate(4, (i) => Expanded(
          child: Padding(
            padding: EdgeInsets.only(left: i == 0 ? 0 : 6, right: i == 3 ? 0 : 6),
            child: cards[i],
          ),
        )),
      );
    }
    return GridView.count(
      crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12,
      childAspectRatio: 0.95, shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: cards,
    );
  }

  // ── Status rows ───────────────────────────────────────────────────────────
  Widget _buildStatusRowDesktop({
    required Color comp, required Color text, required Color muted,
    required Color btn, required bool isRaining,
  }) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _DashboardPumpCard(comp: comp, text: text, muted: muted)),
        const SizedBox(width: 12),
        Expanded(child: _buildRainCard(comp: comp, text: text, muted: muted, isRaining: isRaining)),
      ],
    ),
  );

  Widget _buildStatusRowMobile({
    required Color comp, required Color text, required Color muted,
    required Color btn, required bool isRaining,
  }) => Column(
    children: [
      _DashboardPumpCard(comp: comp, text: text, muted: muted),
      const SizedBox(height: 12),
      _buildRainCard(comp: comp, text: text, muted: muted, isRaining: isRaining),
    ],
  );

  Widget _buildRainCard({
    required Color comp, required Color text, required Color muted,
    required bool isRaining,
  }) {
    const rainingIconColor = Color(0xFF2196F3);
    const dryIconColor = Color(0xFF888888);
    final iconColor = isRaining ? rainingIconColor : dryIconColor;
    final iconBgColor = isRaining
        ? rainingIconColor.withValues(alpha: 0.15)
        : dryIconColor.withValues(alpha: 0.1);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(color: comp, borderRadius: BorderRadius.circular(16)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('RAIN STATUS', style: _ts(muted, size: 10, spacing: 0.8)),
            const SizedBox(height: 3),
            Text(isRaining ? 'RAINING' : 'NO RAIN',
                style: _ts(text, size: 16, weight: FontWeight.bold)),
          ]),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: iconBgColor, borderRadius: BorderRadius.circular(10)),
            child: Icon(
              isRaining ? Icons.umbrella_rounded : Icons.cloud_off_rounded,
              color: iconColor, size: 20,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileCard({
    required Color comp, required Color text, required Color muted,
    Map<String, dynamic>? cropProfile,
  }) {
    const iconColor = Color(0xFF4CAF50);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(color: comp, borderRadius: BorderRadius.circular(16)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('ACTIVE PROFILE', style: _ts(muted, size: 10, spacing: 0.8)),
              const SizedBox(height: 3),
              Text(cropProfile?['name'] ?? 'No profile',
                  style: _ts(text, size: 16, weight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis, maxLines: 1),
            ]),
          ),
          Flexible(
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                _profileRow(
                  'Target',
                  '${(cropProfile?['min_moisture'] as num?)?.toInt() ?? 30}%'
                  ' – '
                  '${(cropProfile?['max_moisture'] as num?)?.toInt() ?? 70}%',
                  text, muted,
                ),
                const SizedBox(height: 2),
                _profileRow(
                  'Watering',
                  '${cropProfile?['watering_minutes'] ?? 5} min',
                  text, muted,
                ),
              ]),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.local_florist_rounded, color: iconColor, size: 20),
          ),
        ],
      ),
    );
  }

  Widget _profileRow(String label, String value, Color text, Color muted) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text('$label  ', style: _ts(muted, size: 11)),
      Flexible(child: Text(value, style: _ts(text, size: 11, weight: FontWeight.bold),
          overflow: TextOverflow.ellipsis)),
    ],
  );

  // ── Shared text style helper ──────────────────────────────────────────────
  TextStyle _ts(Color color, {
    double size = 14, FontWeight weight = FontWeight.bold,
    double? spacing, String family = 'Poppins',
  }) => TextStyle(
    color: color, fontSize: size, fontWeight: weight,
    fontFamily: family, letterSpacing: spacing, decoration: TextDecoration.none,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Chart helpers — shared across both chart widgets
// ─────────────────────────────────────────────────────────────────────────────

List<FlSpot> _toSpots(List<_ChartPoint> data) {
  if (data.isEmpty) return const [];
  final base = data.first.time;
  return data
      .map((p) => FlSpot(p.time.difference(base).inMinutes.toDouble(), p.value))
      .toList();
}

double _tickInterval(double totalMinutes) {
  if (totalMinutes <= 60)   return 10;
  if (totalMinutes <= 180)  return 30;
  if (totalMinutes <= 360)  return 60;
  if (totalMinutes <= 1440) return 240; // 4 hours
  if (totalMinutes <= 2880) return 480; // 8 hours
  return 720; // 12 hours for multi-day spreads
}

String _timeLabel(List<_ChartPoint> data, double minutes) {
  if (data.isEmpty) return '';
  final t = data.first.time.add(Duration(minutes: minutes.round()));
  return '${t.day}/${t.month} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

Widget _legendDot(Color color, String label) => Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    Container(width: 18, height: 2.5,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
    const SizedBox(width: 5),
    Text(label, style: TextStyle(color: color, fontSize: 11,
        fontFamily: 'Poppins', decoration: TextDecoration.none)),
  ],
);

// ─────────────────────────────────────────────────────────────────────────────
// Soil Moisture Chart
// ─────────────────────────────────────────────────────────────────────────────
class _MoistureChart extends StatelessWidget {
  final List<_ChartPoint> data;
  final Color comp, text, muted, accentColor;

  const _MoistureChart({
    required this.data, required this.comp, required this.text,
    required this.muted, required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final spots = _toSpots(data);
    final maxX  = spots.isEmpty ? 1.0 : spots.last.x;
    final interval = _tickInterval(maxX);
    final gridColor = text.withValues(alpha: 0.07);

    return RepaintBoundary(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
        decoration: BoxDecoration(color: comp, borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text('Soil Moisture History',
                style: TextStyle(color: text, fontSize: 15,
                    fontWeight: FontWeight.bold, fontFamily: 'Poppins')),
            const SizedBox(height: 14),
            SizedBox(
              height: 180,
              child: spots.isEmpty
                  ? Center(child: Text('No data yet',
                      style: TextStyle(color: muted, fontSize: 12)))
                  : LineChart(
                      LineChartData(
                        minX: 0, maxX: maxX <= 0 ? 1 : maxX,
                        minY: 0, maxY: 100,
                        clipData: const FlClipData.all(),
                        borderData: FlBorderData(show: false),
                        gridData: FlGridData(
                          show: true, drawVerticalLine: false,
                          horizontalInterval: 25,
                          getDrawingHorizontalLine: (_) => FlLine(
                            color: gridColor, strokeWidth: 1,
                            dashArray: const [4, 4],
                          ),
                        ),
                        extraLinesData: ExtraLinesData(horizontalLines: [
                          HorizontalLine(y: 30, color: Colors.redAccent,
                              strokeWidth: 1.2, dashArray: const [6, 4]),
                          HorizontalLine(y: 70, color: accentColor.withValues(alpha: 0.7),
                              strokeWidth: 1.2, dashArray: const [6, 4]),
                        ]),
                        titlesData: FlTitlesData(
                          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true, reservedSize: 30, interval: 25,
                              getTitlesWidget: (v, _) => Text('${v.toInt()}',
                                  style: TextStyle(color: muted, fontSize: 10)),
                            ),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true, reservedSize: 35,
                              interval: interval,
                              getTitlesWidget: (v, _) {
                                if (v % interval > 0.5) return const SizedBox.shrink();
                                return Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(_timeLabel(data, v),
                                      style: TextStyle(color: muted, fontSize: 9)),
                                );
                              },
                            ),
                          ),
                        ),
                        lineTouchData: LineTouchData(
                          touchTooltipData: LineTouchTooltipData(
                            getTooltipColor: (_) => comp,
                            getTooltipItems: (spots) => spots.map((s) => LineTooltipItem(
                              '${_timeLabel(data, s.x)}\n${s.y.toStringAsFixed(1)}%',
                              TextStyle(color: text, fontSize: 11, fontFamily: 'Poppins'),
                            )).toList(),
                          ),
                        ),
                        lineBarsData: [
                          LineChartBarData(
                            spots: spots,
                            isCurved: true,
                            curveSmoothness: 0.25,
                            color: accentColor,
                            barWidth: 2.5,
                            isStrokeCapRound: true,
                            dotData: const FlDotData(show: false),
                            belowBarData: BarAreaData(
                              show: true,
                              color: accentColor.withValues(alpha: 0.12),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
            const SizedBox(height: 10),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _legendDot(Colors.redAccent, 'Dry threshold'),
              const SizedBox(width: 16),
              _legendDot(accentColor, 'Wet threshold'),
            ]),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Temperature & Humidity — dual line chart
// ─────────────────────────────────────────────────────────────────────────────
class _TempHumidChart extends StatelessWidget {
  final List<_ChartPoint> tempData, humidData;
  final Color comp, text, muted, cTemp, cHumid;

  const _TempHumidChart({
    required this.tempData, required this.humidData,
    required this.comp, required this.text, required this.muted,
    required this.cTemp, required this.cHumid,
  });

  @override
  Widget build(BuildContext context) {
    final base       = tempData.isEmpty ? null : tempData.first.time;
    final tempSpots  = _toSpots(tempData);
    final humidSpots = humidData.isEmpty
        ? const <FlSpot>[]
        : humidData.map((p) => FlSpot(
              p.time.difference(base!).inMinutes.toDouble(),
              p.value,
            )).toList();

    final maxX     = tempSpots.isEmpty ? 1.0 : tempSpots.last.x;
    final interval = _tickInterval(maxX);
    final gridColor = text.withValues(alpha: 0.07);

    return RepaintBoundary(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
        decoration: BoxDecoration(color: comp, borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text('Temperature & Humidity',
                style: TextStyle(color: text, fontSize: 15,
                    fontWeight: FontWeight.bold, fontFamily: 'Poppins')),
            const SizedBox(height: 14),
            SizedBox(
              height: 180,
              child: tempSpots.isEmpty
                  ? Center(child: Text('No data yet',
                      style: TextStyle(color: muted, fontSize: 12)))
                  : LineChart(
                      LineChartData(
                        minX: 0, maxX: maxX <= 0 ? 1 : maxX,
                        minY: 0, maxY: 100,
                        clipData: const FlClipData.all(),
                        borderData: FlBorderData(show: false),
                        gridData: FlGridData(
                          show: true, drawVerticalLine: false,
                          horizontalInterval: 25,
                          getDrawingHorizontalLine: (_) => FlLine(
                            color: gridColor, strokeWidth: 1,
                            dashArray: const [4, 4],
                          ),
                        ),
                        titlesData: FlTitlesData(
                          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true, reservedSize: 30, interval: 25,
                              getTitlesWidget: (v, _) => Text('${v.toInt()}',
                                  style: TextStyle(color: muted, fontSize: 10)),
                            ),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true, reservedSize: 35,
                              interval: interval,
                              getTitlesWidget: (v, _) {
                                if (v % interval > 0.5) return const SizedBox.shrink();
                                return Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(_timeLabel(tempData, v),
                                      style: TextStyle(color: muted, fontSize: 9)),
                                );
                              },
                            ),
                          ),
                        ),
                        lineTouchData: LineTouchData(
                          touchTooltipData: LineTouchTooltipData(
                            getTooltipColor: (_) => comp,
                            getTooltipItems: (spots) => spots.map((s) {
                              final isTemp = s.barIndex == 0;
                              return LineTooltipItem(
                                '${_timeLabel(tempData, s.x)}\n'
                                '${s.y.toStringAsFixed(1)}${isTemp ? '°C' : '%'}',
                                TextStyle(
                                  color: isTemp ? cTemp : cHumid,
                                  fontSize: 11, fontFamily: 'Poppins',
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                        lineBarsData: [
                          // Temperature
                          LineChartBarData(
                            spots: tempSpots, isCurved: true,
                            curveSmoothness: 0.25, color: cTemp,
                            barWidth: 2.5, isStrokeCapRound: true,
                            dotData: const FlDotData(show: false),
                            belowBarData: BarAreaData(
                              show: true, color: cTemp.withValues(alpha: 0.08)),
                          ),
                          // Humidity
                          LineChartBarData(
                            spots: humidSpots, isCurved: true,
                            curveSmoothness: 0.25, color: cHumid,
                            barWidth: 2.5, isStrokeCapRound: true,
                            dotData: const FlDotData(show: false),
                            belowBarData: BarAreaData(
                              show: true, color: cHumid.withValues(alpha: 0.08)),
                          ),
                        ],
                      ),
                    ),
            ),
            const SizedBox(height: 10),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _legendDot(cTemp, 'Temp (°C)'),
              const SizedBox(width: 16),
              _legendDot(cHumid, 'Humidity (%)'),
            ]),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sensor card — compact circular gauge
// ─────────────────────────────────────────────────────────────────────────────
class _SensorCard extends StatelessWidget {
  final bool isDark;
  final Color comp, text, muted, accentColor;
  final String label, displayValue, unit;
  final double? numericValue;
  final IconData icon;
  final double gaugeMax;
  final Key? cardKey;

  const _SensorCard({
    this.cardKey, required this.isDark, required this.comp, required this.text,
    required this.muted, required this.accentColor, required this.label,
    required this.displayValue, required this.unit, required this.numericValue,
    required this.icon, required this.gaugeMax,
  }) : super(key: cardKey);

  @override
  Widget build(BuildContext context) {
    final clamped = numericValue != null
        ? numericValue!.clamp(0.0, gaugeMax).toDouble()
        : 0.0;
    final progress = gaugeMax <= 0 ? 0.0 : (clamped / gaugeMax).clamp(0.0, 1.0);
    final trackColor = text.withValues(alpha: isDark ? 0.12 : 0.09);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: comp,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.25)),
        boxShadow: [BoxShadow(
          color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.04),
          blurRadius: 14, offset: const Offset(0, 4),
        )],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: progress),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutBack,
            builder: (_, v, __) => SizedBox(
              width: 50, height: 50,
              child: Stack(alignment: Alignment.center, children: [
                SizedBox.expand(child: CircularProgressIndicator(
                  value: 1.0, strokeWidth: 4, color: trackColor,
                  strokeCap: StrokeCap.round)),
                SizedBox.expand(child: CircularProgressIndicator(
                  value: v, strokeWidth: 4, color: accentColor,
                  backgroundColor: Colors.transparent, strokeCap: StrokeCap.round)),
                Icon(icon, color: accentColor, size: 16),
              ]),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(displayValue, style: const TextStyle(
                color: Colors.black87, fontSize: 14, fontWeight: FontWeight.bold,
                fontFamily: 'Poppins', decoration: TextDecoration.none)),
              const SizedBox(width: 1),
              Text(unit, style: const TextStyle(
                color: Colors.black87, fontSize: 10, fontFamily: 'Poppins',
                decoration: TextDecoration.none)),
            ],
          ),
          const SizedBox(height: 3),
          Text(label, style: const TextStyle(
            color: Colors.black87, fontSize: 9, letterSpacing: 0.3,
            fontFamily: 'Poppins', fontWeight: FontWeight.w600,
            decoration: TextDecoration.none)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dashboard pump card (embedded quick-control)
// ─────────────────────────────────────────────────────────────────────────────
const _kDashboardSafetyLimit = Duration(minutes: 2);

class _DashboardPumpCard extends StatefulWidget {
  final Color comp, text, muted;
  const _DashboardPumpCard({required this.comp, required this.text, required this.muted});

  @override
  State<_DashboardPumpCard> createState() => _DashboardPumpCardState();
}

class _DashboardPumpCardState extends State<_DashboardPumpCard> {
  bool _isRunning  = false;
  bool _isChanging = false;
  DateTime? _sessionStart;
  Duration  _elapsed = Duration.zero;
  Timer? _tickTimer;
  Timer? _safetyTimer;
  int _pwmValue = 200;

  String get _elapsedLabel {
    final s = _elapsed.inSeconds;
    final m = _elapsed.inMinutes;
    return m > 0 ? '${m}m ${s % 60}s' : '${s}s';
  }

  void _startTimers() {
    _sessionStart = DateTime.now();
    _elapsed = Duration.zero;
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed = DateTime.now().difference(_sessionStart!));
    });
    _safetyTimer = Timer(_kDashboardSafetyLimit, () async {
      if (!mounted || !_isRunning) return;
      final id = context.read<AppStateProvider>().deviceId;
      if (id != null) await _sendCommand(id, 'pump_off');
      if (mounted) {
        setState(() => _isRunning = false);
        _stopTimers();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Safety limit reached — pump stopped after 2 minutes.'),
          backgroundColor: Color(0xFFF59E0B),
          behavior: SnackBarBehavior.floating,
        ));
      }
    });
  }

  void _stopTimers() {
    _tickTimer?.cancel();
    _safetyTimer?.cancel();
    _tickTimer = _safetyTimer = null;
  }

  @override
  void dispose() { _stopTimers(); super.dispose(); }

  Future<bool> _sendCommand(String deviceId, String command, {int? pwm}) async {
    try {
      context.read<MqttService>().sendPumpCommand(
        deviceId,
        command,
        pwmValue: pwm,
      );
      await Supabase.instance.client.from('device_commands').insert({
        'device_id': deviceId,
        'command': command,
        ...?pwm != null ? {'pwm': pwm} : null,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _confirm(String title, String msg, String label, Color color) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Poppins')),
        content: Text(msg, style: const TextStyle(fontFamily: 'Poppins')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: color),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(label),
          ),
        ],
      ),
    );
    return r ?? false;
  }

  Future<void> _toggle() async {
    if (_isChanging) return;
    final id = context.read<AppStateProvider>().deviceId;
    if (id == null) return;

    if (!_isRunning) {
      final ok = await _confirm('Start Pump',
          'Start the pump manually?\nAuto-irrigation will be bypassed.\nPump stops automatically after 2 minutes.',
          'Start', const Color(0xFF2D9D5C));
      if (!ok) return;

      setState(() => _isChanging = true);
      final sent = await _sendCommand(id, 'pump_on', pwm: _pwmValue);
      if (!mounted) return;

      if (sent) {
        setState(() { _isRunning = true; _isChanging = false; });
        _startTimers();
      } else {
        setState(() => _isChanging = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Failed to reach device. Try again.'),
          behavior: SnackBarBehavior.floating));
      }
    } else {
      final ok = await _confirm('Stop Pump', 'Stop the pump and end manual override?',
          'Stop', const Color(0xFFEE4E4E));
      if (!ok) return;

      setState(() => _isChanging = true);
      await _sendCommand(id, 'pump_off');
      if (!mounted) return;

      _stopTimers();
      setState(() { _isRunning = false; _isChanging = false;
          _elapsed = Duration.zero; _sessionStart = null; });
    }
  }

  @override
  Widget build(BuildContext context) {
    const colorOn  = Color(0xFF2D9D5C);
    const colorOff = Color(0xFFEE4E4E);
    final btnColor = _isRunning ? colorOn : colorOff;

    return GestureDetector(
      onTap: _isChanging ? null : _toggle,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: widget.comp, borderRadius: BorderRadius.circular(16),
          border: Border.all(color: btnColor, width: 1.5),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('PUMP', style: TextStyle(color: widget.muted, fontSize: 10,
                    letterSpacing: 0.8, fontFamily: 'Poppins')),
                const SizedBox(height: 3),
                Text(_isRunning ? 'RUNNING' : 'IDLE',
                    style: TextStyle(color: widget.text, fontSize: 16,
                        fontWeight: FontWeight.bold, fontFamily: 'Poppins')),
                if (_isRunning) ...[
                  const SizedBox(height: 2),
                  Text(_elapsedLabel, style: const TextStyle(color: colorOn,
                      fontSize: 11, fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
                ],
                const SizedBox(height: 3),
                Text(_isRunning ? 'Tap to stop' : 'Tap to start',
                    style: TextStyle(color: widget.muted, fontSize: 10, fontFamily: 'Poppins')),
              ])),
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 46, height: 46,
                decoration: BoxDecoration(shape: BoxShape.circle, color: btnColor,
                  boxShadow: [BoxShadow(
                    color: btnColor.withValues(alpha: _isRunning ? 0.45 : 0.25),
                    blurRadius: _isRunning ? 16 : 8, spreadRadius: _isRunning ? 3 : 1)]),
                child: _isChanging
                    ? const Center(child: SizedBox(width: 22, height: 22,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5)))
                    : const Icon(Icons.power_settings_new_rounded, color: Colors.white, size: 26),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(children: [
            Text('Speed', style: TextStyle(color: widget.muted, fontSize: 10, fontFamily: 'Poppins')),
            Expanded(child: Slider(
              value: _pwmValue.toDouble(), min: 0, max: 255, divisions: 255,
              onChanged: _isRunning ? null : (v) => setState(() => _pwmValue = v.round()),
            )),
            Text('${((_pwmValue * 100) / 255).round()}%',
                style: TextStyle(color: widget.text, fontSize: 12,
                    fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
          ]),
        ]),
      ),
    );
  }
}
