// lib/screens/dashboard_screen.dart
//
// ─── REQUIRED DEPENDENCIES (add to pubspec.yaml) ────────────────────────────
//   fl_chart: ^1.1.1
//
// Run: flutter pub get
//
// NOTE: Charts and gauges are implemented with fl_chart widgets.
// ────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/app_state_provider.dart';
import '../services/mqtt_service.dart';
import '../utils/unit_converter.dart';

// ─── Lightweight data models ──────────────────────────────────────────────────

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
  // ── Sensor accent colors (consistent across themes) ──────────────────────────
  static const Color _cMoisture = Color(0xFF4A90E2);
  static const Color _cTemp = Color(0xFFE87722);
  static const Color _cHumid = Color(0xFF7C6FCD);
  static const Color _cFlow = Color(0xFF00B4C4);

  // Chart cache - only rebuild when sensorHistory changes
  List<_ChartPoint> _cachedMoistHist = [];
  List<_ChartPoint> _cachedTempHist = [];
  List<_ChartPoint> _cachedHumidHist = [];
  List<Map<String, dynamic>>? _lastHistory;

  void _updateChartCache(List<Map<String, dynamic>> history) {
    if (identical(history, _lastHistory)) return;
    _lastHistory = history;
    _cachedMoistHist = _buildChartFromHistory(history, 'soil_moisture');
    _cachedTempHist = _buildChartFromHistory(history, 'temperature_c');
    _cachedHumidHist = _buildChartFromHistory(history, 'humidity');
  }

  List<_ChartPoint> _buildChartFromHistory(
    List<Map<String, dynamic>> history,
    String field,
  ) {
    if (history.isEmpty) return [];
    return history.map((row) {
      final time = row['recorded_at'] != null
          ? DateTime.parse(row['recorded_at'] as String)
          : DateTime.now();
      final value = (row[field] as num?)?.toDouble() ?? 0;
      return _ChartPoint(time, value);
    }).toList();
  }

  // ─────────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = colorScheme.surfaceContainerHighest;
    final comp = Theme.of(context).scaffoldBackgroundColor;
    final text = colorScheme.onSurface;
    final muted = text.withValues(alpha: 0.45);
    final btn = colorScheme.primary;

    return Consumer<AppStateProvider>(
      builder: (context, state, _) {
        // ── Loading / no-device states ─────────────────────────────────────
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
                style: _style(text, size: 15),
              ),
            ),
          );
        }

        // ── Extract sensor data ────────────────────────────────────────────
        // Freshness check — if data older than 5 minutes, treat as no data
        final d = state.latestSensorData;
        DateTime? lastUpdated;
        if (d['recorded_at'] != null) {
          lastUpdated = DateTime.tryParse(d['recorded_at'] as String);
        }

        const staleLimit = Duration(minutes: 5);
        final isStale =
            lastUpdated == null ||
            DateTime.now().difference(lastUpdated) > staleLimit;

        final moisture = !isStale
            ? (d['soil_moisture'] as num?)?.toDouble()
            : null;
        final tempC = !isStale
            ? (d['temperature_c'] as num?)?.toDouble()
            : null;
        final humidity = !isStale ? (d['humidity'] as num?)?.toDouble() : null;
        final flowRate = !isStale
            ? (d['flow_litres'] as num?)?.toDouble()
            : null;

        final tempUnit = state.tempUnit;
        final tempDisplay = tempC != null
            ? UnitConverter.formatTemp(tempC, tempUnit)
            : null;

        final isRaining = !isStale && d['rain_detected'] == true;

        // ── Chart history (freshness filter, only show last 1 hour) ───────
        final freshHistory = state.sensorHistory.where((row) {
          if (row['recorded_at'] == null) return false;
          final t = DateTime.tryParse(row['recorded_at'] as String);
          if (t == null) return false;
          return DateTime.now().difference(t) <= const Duration(hours: 1);
        }).toList();
        _updateChartCache(freshHistory);
        final moistHist = _cachedMoistHist;
        final tempHist = _cachedTempHist;
        final humidHist = _cachedHumidHist;

        return Scaffold(
          backgroundColor: bg,
          body: RefreshIndicator(
            color: btn,
            backgroundColor: comp,
            onRefresh: () async {
              await state.refresh();
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 36),
              child: LayoutBuilder(
                builder: (_, constraints) {
                  final isDesktop = constraints.maxWidth >= 700;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── 1. Active Profile ────────────────────────────────
                      _buildProfileCard(
                        isDark: isDark,
                        comp: comp,
                        text: text,
                        muted: muted,
                        cropProfile: state.activeCropProfile,
                      ),
                      const SizedBox(height: 16),

                      // ── 2. Pump + Rain ───────────────────────────────────

                      // ── 2. Four Sensor Cards ─────────────────────────
                      _buildSensorCards(
                        isDark: isDark,
                        comp: comp,
                        text: text,
                        muted: muted,
                        isDesktop: isDesktop,
                        moisture: moisture,
                        tempC: tempC,
                        humidity: humidity,
                        flowRate: flowRate,
                        tempDisplay: tempDisplay,
                      ),
                      const SizedBox(height: 16),

                      // ── 2. Pump + Rain ───────────────────────────────────
                      isDesktop
                          ? _buildStatusRowDesktop(
                              isDark: isDark,
                              comp: comp,
                              text: text,
                              muted: muted,
                              btn: btn,
                              isRaining: isRaining,
                              flowRate: flowRate,
                            )
                          : _buildStatusRowMobile(
                              isDark: isDark,
                              comp: comp,
                              text: text,
                              muted: muted,
                              btn: btn,
                              isRaining: isRaining,
                              flowRate: flowRate,
                            ),
                      const SizedBox(height: 16),

                      // ── 3. Soil Moisture History ─────────────────────
                      _buildMoistureChart(
                        isDark: isDark,
                        comp: comp,
                        text: text,
                        muted: muted,
                        data: moistHist,
                      ),
                      const SizedBox(height: 16),

                      // ── 4. Temp & Humidity Chart ─────────────────────
                      _buildTempHumidChart(
                        isDark: isDark,
                        comp: comp,
                        text: text,
                        muted: muted,
                        tempData: tempHist,
                        humidData: humidHist,
                        currentTemp: tempC,
                      ),
                      const SizedBox(height: 8),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // 4 Sensor Cards — 4-in-a-row on desktop, 2×2 grid on mobile
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildSensorCards({
    required bool isDark,
    required Color comp,
    required Color text,
    required Color muted,
    required bool isDesktop,
    required double? moisture,
    required double? tempC,
    required double? humidity,
    required double? flowRate,
    String? tempDisplay,
  }) {
    // Split "82.4°F" → value="82.4", unit="°F"
    // If no tempDisplay, fall back to raw °C
    final tempValue = tempDisplay != null
        ? RegExp(r'^([\d.]+)(°[CF])$').firstMatch(tempDisplay)?.group(1) ??
              (tempC?.toStringAsFixed(1) ?? '—')
        : (tempC?.toStringAsFixed(1) ?? '—');

    final tempUnit = tempDisplay != null
        ? RegExp(r'^([\d.]+)(°[CF])$').firstMatch(tempDisplay)?.group(2) ?? ''
        : (tempC != null ? '°C' : '');
    String formatValue(double? v) => v != null ? v.toStringAsFixed(1) : '—';

    final cards = <_SensorCard>[
      _SensorCard(
        cardKey: const ValueKey('sensor_moisture'),
        isDark: isDark,
        comp: comp,
        text: text,
        muted: muted,
        label: 'Moisture',
        numericValue: moisture,
        displayValue: formatValue(moisture),
        unit: '%',
        accentColor: _cMoisture,
        icon: Icons.water_drop_rounded,
        gaugeMax: 100,
      ),
      _SensorCard(
        cardKey: const ValueKey('sensor_temperature'),
        isDark: isDark,
        comp: comp,
        text: text,
        muted: muted,
        label: 'Temperature',
        numericValue: tempC,
        displayValue: tempC != null ? tempValue : '—',
        unit: tempC != null ? tempUnit : '',
        accentColor: _cTemp,
        icon: Icons.thermostat_rounded,
        gaugeMax: 50,
      ),
      _SensorCard(
        cardKey: const ValueKey('sensor_humidity'),
        isDark: isDark,
        comp: comp,
        text: text,
        muted: muted,
        label: 'Humidity',
        numericValue: humidity,
        displayValue: formatValue(humidity),
        unit: '%',
        accentColor: _cHumid,
        icon: Icons.cloud_rounded,
        gaugeMax: 100,
      ),
      _SensorCard(
        cardKey: const ValueKey('sensor_flow'),
        isDark: isDark,
        comp: comp,
        text: text,
        muted: muted,
        label: 'Flow rate',
        numericValue: flowRate,
        displayValue: formatValue(flowRate),
        unit: 'L/min',
        accentColor: _cFlow,
        icon: Icons.graphic_eq_rounded,
        gaugeMax: 10,
      ),
    ];

    if (isDesktop) {
      return Row(
        children: List.generate(
          cards.length,
          (i) => Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                left: i == 0 ? 0 : 6,
                right: i == 3 ? 0 : 6,
              ),
              child: cards[i],
            ),
          ),
        ),
      );
    }

    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 0.95,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: cards,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Status Row — Desktop (pump | rain side by side)
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildStatusRowDesktop({
    required bool isDark,
    required Color comp,
    required Color text,
    required Color muted,
    required Color btn,
    required bool isRaining,
    required double? flowRate,
  }) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _DashboardPumpCard(comp: comp, text: text, muted: muted),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildRainCard(
            isDark: isDark,
            comp: comp,
            text: text,
            muted: muted,
            isRaining: isRaining,
          ),
        ),
      ],
    ),
  );

  // ─────────────────────────────────────────────────────────────────────────────
  // Status Row — Mobile (stacked)
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildStatusRowMobile({
    required bool isDark,
    required Color comp,
    required Color text,
    required Color muted,
    required Color btn,
    required bool isRaining,
    required double? flowRate,
  }) => Column(
    children: [
      _DashboardPumpCard(comp: comp, text: text, muted: muted),
      const SizedBox(height: 12),
      _buildRainCard(
        isDark: isDark,
        comp: comp,
        text: text,
        muted: muted,
        isRaining: isRaining,
      ),
    ],
  );

  // ─────────────────────────────────────────────────────────────────────────────
  // Rain Sensor Card — same layout as Pump Status (text left, icon right)
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildRainCard({
    required bool isDark,
    required Color comp,
    required Color text,
    required Color muted,
    required bool isRaining,
  }) {
    // Icon colors: blue for raining, grey for dry
    const rainingIconColor = Color(0xFF2196F3);
    const dryIconColor = Color(0xFF888888);
    final iconColor = isRaining ? rainingIconColor : dryIconColor;
    final iconBgColor = isRaining
        ? rainingIconColor.withValues(alpha: 0.15)
        : dryIconColor.withValues(alpha: 0.1);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: comp,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'RAIN STATUS',
                  style: _style(muted, size: 10, letterSpacing: 0.8),
                ),
                const SizedBox(height: 3),
                Text(
                  isRaining ? 'RAINING' : 'NO RAIN',
                  style: _style(text, size: 16, weight: FontWeight.bold),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconBgColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isRaining
                  ? Icons.umbrella_rounded
                  : Icons.cloud_off_rounded,
              color: iconColor,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Active Profile Card — like pump: label + name left, target/watering center, icon right
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildProfileCard({
    required bool isDark,
    required Color comp,
    required Color text,
    required Color muted,
    Map<String, dynamic>? cropProfile,
  }) {
    final profileName = cropProfile?['name'] ?? 'No profile';
    final minMoisture = (cropProfile?['min_moisture'] as num?)?.toInt() ?? 30;
    final maxMoisture = (cropProfile?['max_moisture'] as num?)?.toInt() ?? 70;
    const profileIconColor = Color(0xFF4CAF50);
    final iconBgColor = profileIconColor.withValues(alpha: 0.15);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: comp,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'ACTIVE PROFILE',
                  style: _style(muted, size: 10, letterSpacing: 0.8),
                ),
                const SizedBox(height: 3),
                Text(
                  profileName,
                  style: _style(text, size: 16, weight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ],
            ),
          ),
          Flexible(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _profileStatRow(
                    'Target',
                    '$minMoisture% – $maxMoisture%',
                    text,
                    muted,
                  ),
                  const SizedBox(height: 2),
                  _profileStatRow(
                    'Watering',
                    '${cropProfile?['watering_minutes'] ?? 5} min',
                    text,
                    muted,
                  ),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconBgColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.local_florist_rounded,
              color: profileIconColor,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }

  Widget _profileStatRow(String label, String value, Color text, Color muted) =>
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label  ', style: _style(muted, size: 11)),
          Flexible(
            child: Text(
              value,
              style: _style(text, size: 11, weight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );

  // ─────────────────────────────────────────────────────────────────────────────
  // Soil Moisture History Chart
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildMoistureChart({
    required bool isDark,
    required Color comp,
    required Color text,
    required Color muted,
    required List<_ChartPoint> data,
  }) {
    final gridColor = text.withValues(alpha: 0.07);
    final spots = _timeSeriesToSpots(data);
    final maxX = spots.isEmpty ? 1.0 : spots.last.x;

    return RepaintBoundary(
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
        decoration: BoxDecoration(
          color: comp,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              'Soil Moisture History',
              style: _style(
                text,
                size: 16,
                weight: FontWeight.bold,
                fontFamily: 'Poppins',
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 180,
              child: spots.isEmpty
                  ? Center(
                      child: Text(
                        'No data yet',
                        style: _style(muted, size: 12),
                      ),
                    )
                  : LineChart(
                      LineChartData(
                        minX: 0,
                        maxX: maxX <= 0 ? 1 : maxX,
                        minY: 0,
                        maxY: 100,
                        clipData: const FlClipData.all(),
                        borderData: FlBorderData(show: false),
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: true,
                          horizontalInterval: 25,
                          verticalInterval: (maxX <= 0 ? 1 : maxX) / 4,
                          getDrawingHorizontalLine: (_) => FlLine(
                            color: gridColor,
                            strokeWidth: 1,
                            dashArray: const [4, 4],
                          ),
                          getDrawingVerticalLine: (_) =>
                              FlLine(color: gridColor, strokeWidth: 1),
                        ),
                        extraLinesData: ExtraLinesData(
                          horizontalLines: [
                            HorizontalLine(
                              y: 30,
                              color: Colors.redAccent,
                              strokeWidth: 1.5,
                              dashArray: const [6, 4],
                            ),
                            HorizontalLine(
                              y: 70,
                              color: _cMoisture.withValues(alpha: 0.8),
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
                              reservedSize: 28,
                              interval: 25,
                              getTitlesWidget: (value, meta) => Text(
                                value.toInt().toString(),
                                style: _style(muted, size: 10),
                              ),
                            ),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 20,
                              interval: (maxX <= 0 ? 1 : maxX) / 3,
                              getTitlesWidget: (value, meta) => Text(
                                _timeLabelFromMinutes(data, value),
                                style: _style(muted, size: 10),
                              ),
                            ),
                          ),
                        ),
                        lineTouchData: LineTouchData(
                          touchTooltipData: LineTouchTooltipData(
                            getTooltipColor: (_) => comp,
                            getTooltipItems: (touchedSpots) => touchedSpots
                                .map(
                                  (spot) => LineTooltipItem(
                                    '${_timeLabelFromMinutes(data, spot.x)}\n${spot.y.toStringAsFixed(1)}%',
                                    _style(text, size: 12),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                        lineBarsData: [
                          LineChartBarData(
                            spots: spots,
                            isCurved: true,
                            color: _cMoisture,
                            barWidth: 2,
                            isStrokeCapRound: true,
                            dotData: const FlDotData(show: false),
                            belowBarData: BarAreaData(
                              show: true,
                              color: _cMoisture.withValues(alpha: 0.15),
                              cutOffY: 0,
                              applyCutOffY: true,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _legendItem(Colors.redAccent, 'Dry'),
                const SizedBox(width: 16),
                _legendItem(_cMoisture, 'Wet'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Temperature & Humidity — dual line chart, fixed 0–100 Y axis
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildTempHumidChart({
    required bool isDark,
    required Color comp,
    required Color text,
    required Color muted,
    required List<_ChartPoint> tempData,
    required List<_ChartPoint> humidData,
    required double? currentTemp,
  }) {
    final gridColor = text.withValues(alpha: 0.07);

    // Both series share the same timestamps — use temp as the time base
    final baseTime = tempData.isEmpty ? null : tempData.first.time;
    final tempSpots = _timeSeriesToSpots(tempData, minTime: baseTime);
    final humidSpots = _timeSeriesToSpots(humidData, minTime: baseTime);
    final maxX = tempSpots.isEmpty ? 1.0 : tempSpots.last.x;

    return RepaintBoundary(
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
        decoration: BoxDecoration(
          color: comp,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              'Temperature & Humidity',
              style: _style(
                text,
                size: 16,
                weight: FontWeight.bold,
                fontFamily: 'Poppins',
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 180,
              child: tempSpots.isEmpty
                  ? Center(
                      child: Text(
                        'No data yet',
                        style: _style(muted, size: 12),
                      ),
                    )
                  : LineChart(
                      LineChartData(
                        minX: 0,
                        maxX: maxX <= 0 ? 1 : maxX,
                        minY: 0,
                        maxY: 100,
                        clipData: const FlClipData.all(),
                        borderData: FlBorderData(show: false),
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                          horizontalInterval: 25,
                          getDrawingHorizontalLine: (_) => FlLine(
                            color: gridColor,
                            strokeWidth: 1,
                            dashArray: const [4, 4],
                          ),
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
                              reservedSize: 28,
                              interval: 25,
                              getTitlesWidget: (value, meta) => Text(
                                value.toInt().toString(),
                                style: _style(muted, size: 10),
                              ),
                            ),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 20,
                              interval: (maxX <= 0 ? 1 : maxX) / 4,
                              getTitlesWidget: (value, meta) => Text(
                                _timeLabelFromMinutes(tempData, value),
                                style: _style(muted, size: 10),
                              ),
                            ),
                          ),
                        ),
                        lineTouchData: LineTouchData(
                          touchTooltipData: LineTouchTooltipData(
                            getTooltipColor: (_) => comp,
                            getTooltipItems: (touchedSpots) => touchedSpots
                                .map(
                                  (spot) => LineTooltipItem(
                                    '${_timeLabelFromMinutes(tempData, spot.x)}\n${spot.y.toStringAsFixed(1)}',
                                    _style(text, size: 12),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                        lineBarsData: [
                          // ── Temperature ───────────────────────────────────
                          LineChartBarData(
                            spots: tempSpots,
                            isCurved: true,
                            color: _cTemp,
                            barWidth: 2,
                            isStrokeCapRound: true,
                            dotData: const FlDotData(show: false),
                            belowBarData: BarAreaData(
                              show: true,
                              color: _cTemp.withValues(alpha: 0.10),
                            ),
                          ),
                          // ── Humidity ─────────────────────────────────────
                          LineChartBarData(
                            spots: humidSpots,
                            isCurved: true,
                            color: _cHumid,
                            barWidth: 2,
                            isStrokeCapRound: true,
                            dotData: const FlDotData(show: false),
                            belowBarData: BarAreaData(
                              show: true,
                              color: _cHumid.withValues(alpha: 0.10),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _legendItem(_cTemp, 'Temp'),
                const SizedBox(width: 16),
                _legendItem(_cHumid, 'Humid'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Shared helpers
  // ─────────────────────────────────────────────────────────────────────────────

  List<FlSpot> _timeSeriesToSpots(
    List<_ChartPoint> data, {
    DateTime? minTime,
    double Function(double y)? mapY,
  }) {
    if (data.isEmpty) return const [];
    final baseTime = minTime ?? data.first.time;
    return data
        .map(
          (point) => FlSpot(
            point.time.difference(baseTime).inMinutes.toDouble(),
            mapY != null ? mapY(point.value) : point.value,
          ),
        )
        .toList();
  }

  String _timeLabelFromMinutes(List<_ChartPoint> data, double minutesOffset) {
    if (data.isEmpty) return '';
    final sorted = [...data]..sort((a, b) => a.time.compareTo(b.time));
    final base = sorted.first.time;
    final labelTime = base.add(Duration(minutes: minutesOffset.round()));
    final hh = labelTime.hour.toString().padLeft(2, '0');
    final mm = labelTime.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  TextStyle _style(
    Color color, {
    double size = 14,
    FontWeight weight = FontWeight.bold,
    double? letterSpacing,
    String fontFamily = 'Poppins',
  }) => TextStyle(
    color: color,
    fontSize: size,
    fontWeight: weight,
    fontFamily: fontFamily,
    letterSpacing: letterSpacing,
    decoration: TextDecoration.none,
  );

  Widget _legendItem(Color color, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 18,
        height: 2.5,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 5),
      Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontFamily: 'Poppins',
          decoration: TextDecoration.none,
        ),
      ),
    ],
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// _DashboardPumpCard — full pump control embedded in dashboard
// ─────────────────────────────────────────────────────────────────────────────

const _kDashboardSafetyLimit = Duration(minutes: 2);

class _DashboardPumpCard extends StatefulWidget {
  final Color comp, text, muted;
  const _DashboardPumpCard({
    required this.comp,
    required this.text,
    required this.muted,
  });

  @override
  State<_DashboardPumpCard> createState() => _DashboardPumpCardState();
}

class _DashboardPumpCardState extends State<_DashboardPumpCard> {
  bool _isRunning = false;
  bool _isChanging = false;
  DateTime? _sessionStart;
  Duration _elapsed = Duration.zero;
  Timer? _tickTimer;
  Timer? _safetyTimer;

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
      final deviceId = context.read<AppStateProvider>().deviceId;
      if (deviceId != null) await _sendCommand(deviceId, 'pump_off');
      if (mounted) {
        setState(() {
          _isRunning = false;
        });
        _stopTimers();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Safety limit reached — pump stopped after 2 minutes.',
            ),
            backgroundColor: Color(0xFFF59E0B),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    });
  }

  void _stopTimers() {
    _tickTimer?.cancel();
    _safetyTimer?.cancel();
    _tickTimer = null;
    _safetyTimer = null;
  }

  @override
  void dispose() {
    _stopTimers();
    super.dispose();
  }

  Future<bool> _sendCommand(String deviceId, String command) async {
    try {
      context.read<MqttService>().sendPumpCommand(deviceId, command);
      await Supabase.instance.client.from('device_commands').insert({
        'device_id': deviceId,
        'command': command,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
    required Color confirmColor,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontFamily: 'Poppins',
          ),
        ),
        content: Text(message, style: const TextStyle(fontFamily: 'Poppins')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: confirmColor),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _toggle() async {
    if (_isChanging) return;
    final deviceId = context.read<AppStateProvider>().deviceId;
    if (deviceId == null) return;

    if (!_isRunning) {
      final ok = await _confirm(
        title: 'Start Pump',
        message:
            'Start the pump manually?\n'
            'Auto-irrigation will be bypassed.\n'
            'Pump stops automatically after 2 minutes.',
        confirmLabel: 'Start',
        confirmColor: const Color(0xFF2D9D5C),
      );
      if (!ok) return;
      setState(() => _isChanging = true);
      final sent = await _sendCommand(deviceId, 'pump_on');
      if (!mounted) return;
      if (sent) {
        setState(() {
          _isRunning = true;
          _isChanging = false;
        });
        _startTimers();
      } else {
        setState(() => _isChanging = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to reach device. Try again.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } else {
      final ok = await _confirm(
        title: 'Stop Pump',
        message: 'Stop the pump and end manual override?',
        confirmLabel: 'Stop',
        confirmColor: const Color(0xFFEE4E4E),
      );
      if (!ok) return;
      setState(() => _isChanging = true);
      await _sendCommand(deviceId, 'pump_off');
      if (!mounted) return;
      _stopTimers();
      setState(() {
        _isRunning = false;
        _isChanging = false;
        _elapsed = Duration.zero;
        _sessionStart = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const colorOn = Color(0xFF2D9D5C);
    const colorOff = Color(0xFFEE4E4E);
    final btnColor = _isRunning ? colorOn : colorOff;

    return GestureDetector(
      onTap: _isChanging ? null : _toggle,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: widget.comp,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: btnColor, width: 1.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'PUMP',
                    style: TextStyle(
                      color: widget.muted,
                      fontSize: 10,
                      letterSpacing: 0.8,
                      fontFamily: 'Poppins',
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _isRunning ? 'RUNNING' : 'IDLE',
                    style: TextStyle(
                      color: widget.text,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Poppins',
                    ),
                  ),
                  if (_isRunning) ...[
                    const SizedBox(height: 2),
                    Text(
                      _elapsedLabel,
                      style: TextStyle(
                        color: colorOn,
                        fontSize: 11,
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 3),
                  Text(
                    _isRunning ? 'Tap to stop' : 'Tap to start',
                    style: TextStyle(
                      color: widget.muted,
                      fontSize: 10,
                      fontFamily: 'Poppins',
                    ),
                  ),
                ],
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: btnColor,
                boxShadow: [
                  BoxShadow(
                    color: btnColor.withValues(alpha: _isRunning ? 0.45 : 0.25),
                    blurRadius: _isRunning ? 16 : 8,
                    spreadRadius: _isRunning ? 3 : 1,
                  ),
                ],
              ),
              child: _isChanging
                  ? const Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      ),
                    )
                  : const Icon(
                      Icons.power_settings_new_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _SensorCard — radial gauge only, no sparkline, circle centered
// ─────────────────────────────────────────────────────────────────────────────

class _SensorCard extends StatelessWidget {
  final bool isDark;
  final Color comp, text, muted, accentColor;
  final String label, displayValue, unit;
  final double? numericValue; // nullable — null means no data
  final IconData icon;
  final double gaugeMax;
  final Key? cardKey;

  const _SensorCard({
    required this.isDark,
    required this.comp,
    required this.text,
    required this.muted,
    required this.accentColor,
    required this.label,
    required this.displayValue,
    required this.numericValue,
    required this.unit,
    required this.icon,
    required this.gaugeMax,
    this.cardKey,
  });

  @override
  Widget build(BuildContext context) {
    final clamped = numericValue != null
        ? numericValue!.clamp(0.0, gaugeMax).toDouble()
        : 0.0;
    final progress = gaugeMax <= 0 ? 0.0 : (clamped / gaugeMax).clamp(0.0, 1.0);
    final trackColor = text.withValues(alpha: isDark ? 0.12 : 0.09);
    final hasData = numericValue != null;
    final display = hasData ? displayValue : '0';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: comp,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: progress),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutBack,
            builder: (context, animatedProgress, _) => SizedBox(
              width: 50,
              height: 50,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox.expand(
                    child: CircularProgressIndicator(
                      value: 1.0,
                      strokeWidth: 4,
                      color: trackColor,
                      strokeCap: StrokeCap.round,
                    ),
                  ),
                  SizedBox.expand(
                    child: CircularProgressIndicator(
                      value: animatedProgress,
                      strokeWidth: 4,
                      color: accentColor,
                      backgroundColor: Colors.transparent,
                      strokeCap: StrokeCap.round,
                    ),
                  ),
                  Icon(icon, color: accentColor, size: 16),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                display,
                style: TextStyle(
                  color: Colors.black87,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Poppins',
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(width: 1),
              Text(
                unit,
                style: TextStyle(
                  color: Colors.black87,
                  fontSize: 10,
                  fontFamily: 'Poppins',
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              color: Colors.black87,
              fontSize: 9,
              letterSpacing: 0.3,
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }
}
