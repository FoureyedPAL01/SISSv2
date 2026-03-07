// lib/screens/dashboard_screen.dart
//
// ─── REQUIRED DEPENDENCIES (add to pubspec.yaml) ────────────────────────────
//   fl_chart: ^1.1.1
//
// Run: flutter pub get
//
// NOTE: Charts and gauges are implemented with fl_chart widgets.
// ────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../providers/app_state_provider.dart';
import '../utils/unit_converter.dart';

// ─── Lightweight data models ──────────────────────────────────────────────────

class _SparkPoint {
  final int x;
  final double y;
  const _SparkPoint(this.x, this.y);
}

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

class _DashboardScreenState extends State<DashboardScreen> {
  // ── Sensor accent colors (consistent across themes) ──────────────────────────
  static const Color _cMoisture = Color(0xFF4A90E2);
  static const Color _cTemp = Color(0xFFE87722);
  static const Color _cHumid = Color(0xFF7C6FCD);
  static const Color _cFlow = Color(0xFF00B4C4);

  List<_SparkPoint> _buildSparkFromHistory(
    List<Map<String, dynamic>> history,
    String field,
    int points,
  ) {
    debugPrint(
      '[DEBUG] Building sparkline for $field, history length: ${history.length}',
    );
    if (history.isEmpty) {
      debugPrint('[DEBUG] History EMPTY - showing zeros instead of mock data');
      return List.generate(points, (i) => _SparkPoint(i, 0));
    }
    final data = history.length > points
        ? history.sublist(history.length - points)
        : history;
    final result = <_SparkPoint>[];
    for (var i = 0; i < points; i++) {
      if (i < data.length) {
        final value = (data[i][field] as num?)?.toDouble() ?? 0;
        result.add(_SparkPoint(i, value));
      } else {
        result.add(_SparkPoint(i, 0));
      }
    }
    return result;
  }

  List<_ChartPoint> _buildChartFromHistory(
    List<Map<String, dynamic>> history,
    String field,
  ) {
    debugPrint(
      '[DEBUG] Building chart for $field, history length: ${history.length}',
    );
    if (history.isEmpty) {
      debugPrint(
        '[DEBUG] History EMPTY - showing empty chart instead of mock data',
      );
      return [];
    }
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
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = colorScheme.background;
    final comp = colorScheme.surfaceContainerHighest;
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
        debugPrint('[DEBUG] latestSensorData: ${state.latestSensorData}');
        debugPrint(
          '[DEBUG] sensorHistory count: ${state.sensorHistory.length}',
        );

        final d = state.latestSensorData;
        final moisture = (d['soil_moisture'] as num? ?? 0).toDouble();
        final tempC = (d['temperature_c'] as num? ?? 28).toDouble();
        final humidity = (d['humidity'] as num? ?? 0).toDouble();
        final flowLpm = (d['flow_litres'] as num? ?? 0).toDouble();

        final tempUnit = state.tempUnit;
        final tempDisplay = UnitConverter.formatTemp(tempC, tempUnit);

        final temp = tempC;
        final flowRate = flowLpm;

        final isRaining = d['rain_detected'] == true;

        debugPrint(
          '[DEBUG] Moisture: $moisture, Temp: $temp, Humidity: $humidity, Flow: $flowLpm',
        );

        // TODO: pull pumpRunning from state.pumpStatus when available
        const pumpRunning = false;

        // ── Sparkline data ──────────────────────────────────────────────
        final moistSpark = _buildSparkFromHistory(
          state.sensorHistory,
          'soil_moisture',
          20,
        );
        final tempSpark = _buildSparkFromHistory(
          state.sensorHistory,
          'temperature_c',
          20,
        );
        final humidSpark = _buildSparkFromHistory(
          state.sensorHistory,
          'humidity',
          20,
        );
        final flowSpark = _buildSparkFromHistory(
          state.sensorHistory,
          'flow_litres',
          20,
        );

        // ── Chart history ────────────────────────────────────────────────
        final moistHist = _buildChartFromHistory(
          state.sensorHistory,
          'soil_moisture',
        );
        final tempHist = _buildChartFromHistory(
          state.sensorHistory,
          'temperature_c',
        );
        final humidHist = _buildChartFromHistory(
          state.sensorHistory,
          'humidity',
        );

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
                      // ── Dashboard header ─────────────────────────────
                      _buildHeader(text, muted, btn),
                      const SizedBox(height: 20),

                      // ── 4 Sensor cards ───────────────────────────────
                      _buildSensorCards(
                        isDark: isDark,
                        comp: comp,
                        text: text,
                        muted: muted,
                        isDesktop: isDesktop,
                        moisture: moisture,
                        temp: temp,
                        humidity: humidity,
                        flowRate: flowRate,
                        moistSpark: moistSpark,
                        tempSpark: tempSpark,
                        humidSpark: humidSpark,
                        flowSpark: flowSpark,
                        tempDisplay: tempDisplay,
                      ),
                      const SizedBox(height: 16),

                      // ── Moisture chart + side cards ─────────────────────
                      isDesktop
                          ? _buildMiddleDesktop(
                              isDark: isDark,
                              comp: comp,
                              text: text,
                              muted: muted,
                              btn: btn,
                              isRaining: isRaining,
                              pumpRunning: pumpRunning,
                              flowRate: flowRate,
                              moistHist: moistHist,
                            )
                          : _buildMiddleMobile(
                              isDark: isDark,
                              comp: comp,
                              text: text,
                              muted: muted,
                              btn: btn,
                              isRaining: isRaining,
                              pumpRunning: pumpRunning,
                              flowRate: flowRate,
                              moistHist: moistHist,
                            ),
                      const SizedBox(height: 16),

                      // ── Moisture chart + side cards ──────────────────
                      isDesktop
                          ? _buildMiddleDesktop(
                              isDark: isDark,
                              comp: comp,
                              text: text,
                              muted: muted,
                              btn: btn,
                              isRaining: isRaining,
                              pumpRunning: pumpRunning,
                              flowRate: flowRate,
                              moistHist: moistHist,
                            )
                          : _buildMiddleMobile(
                              isDark: isDark,
                              comp: comp,
                              text: text,
                              muted: muted,
                              btn: btn,
                              isRaining: isRaining,
                              pumpRunning: pumpRunning,
                              flowRate: flowRate,
                              moistHist: moistHist,
                            ),
                      const SizedBox(height: 16),

                      // ── Temp & Humidity chart ────────────────────────
                      _buildTempHumidChart(
                        isDark: isDark,
                        comp: comp,
                        text: text,
                        muted: muted,
                        tempData: tempHist,
                        humidData: humidHist,
                        currentTemp: temp,
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
  // Header
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildHeader(Color text, Color muted, Color btn) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Dashboard',
        style: _style(
          text,
          size: 28,
          weight: FontWeight.bold,
          fontFamily: 'Bungee',
        ),
      ),
      const SizedBox(height: 3),
      Row(
        children: [
          Text(
            'Real-time monitoring · ',
            style: _style(muted, size: 13, fontFamily: 'Merriweather'),
          ),
          Text(
            'Main Field Node',
            style: _style(
              btn,
              size: 13,
              weight: FontWeight.w600,
              fontFamily: 'Merriweather',
            ),
          ),
        ],
      ),
    ],
  );

  // ─────────────────────────────────────────────────────────────────────────────
  // 4 Sensor Cards — 4-in-a-row on desktop, 2×2 grid on mobile
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildSensorCards({
    required bool isDark,
    required Color comp,
    required Color text,
    required Color muted,
    required bool isDesktop,
    required double moisture,
    required double temp,
    required double humidity,
    required double flowRate,
    required List<_SparkPoint> moistSpark,
    required List<_SparkPoint> tempSpark,
    required List<_SparkPoint> humidSpark,
    required List<_SparkPoint> flowSpark,
    String? tempDisplay,
  }) {
    final cards = <_SensorCard>[
      _SensorCard(
        isDark: isDark,
        comp: comp,
        text: text,
        muted: muted,
        label: 'SOIL MOISTURE',
        value: moisture.toStringAsFixed(1),
        unit: '%',
        accentColor: _cMoisture,
        icon: PhosphorIcons.drop(),
        sparkData: moistSpark,
        gaugeMax: 100,
      ),
      _SensorCard(
        isDark: isDark,
        comp: comp,
        text: text,
        muted: muted,
        label: 'TEMPERATURE',
        value: tempDisplay ?? temp.toStringAsFixed(1),
        unit: tempDisplay != null ? '' : '°C',
        accentColor: _cTemp,
        icon: PhosphorIcons.thermometer(),
        sparkData: tempSpark,
        gaugeMax: 50,
      ),
      _SensorCard(
        isDark: isDark,
        comp: comp,
        text: text,
        muted: muted,
        label: 'HUMIDITY',
        value: humidity.toStringAsFixed(1),
        unit: '%',
        accentColor: _cHumid,
        icon: PhosphorIcons.cloud(),
        sparkData: humidSpark,
        gaugeMax: 100,
      ),
      _SensorCard(
        isDark: isDark,
        comp: comp,
        text: text,
        muted: muted,
        label: 'FLOW RATE',
        value: flowRate.toStringAsFixed(1),
        unit: 'L/min',
        accentColor: _cFlow,
        // NOTE: change to PhosphorIcons.waveform() if your version supports it
        icon: PhosphorIcons.waveform(),
        sparkData: flowSpark,
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
      childAspectRatio: 0.82,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: cards,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Middle section — Desktop (chart left, cards right)
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildMiddleDesktop({
    required bool isDark,
    required Color comp,
    required Color text,
    required Color muted,
    required Color btn,
    required bool isRaining,
    required bool pumpRunning,
    required double flowRate,
    required List<_ChartPoint> moistHist,
  }) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        flex: 62,
        child: _buildMoistureChart(
          isDark: isDark,
          comp: comp,
          text: text,
          muted: muted,
          data: moistHist,
        ),
      ),
      const SizedBox(width: 16),
      SizedBox(
        width: 295,
        child: Column(
          children: [
            _buildPumpCard(
              isDark: isDark,
              comp: comp,
              text: text,
              muted: muted,
              btn: btn,
              running: pumpRunning,
              flow: flowRate,
            ),
            const SizedBox(height: 12),
            _buildRainCard(
              isDark: isDark,
              comp: comp,
              text: text,
              muted: muted,
              isRaining: isRaining,
            ),
            const SizedBox(height: 12),
            _buildProfileCard(
              isDark: isDark,
              comp: comp,
              text: text,
              muted: muted,
            ),
          ],
        ),
      ),
    ],
  );

  // ─────────────────────────────────────────────────────────────────────────────
  // Middle section — Mobile (stacked)
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildMiddleMobile({
    required bool isDark,
    required Color comp,
    required Color text,
    required Color muted,
    required Color btn,
    required bool isRaining,
    required bool pumpRunning,
    required double flowRate,
    required List<_ChartPoint> moistHist,
  }) => Column(
    children: [
      _buildMoistureChart(
        isDark: isDark,
        comp: comp,
        text: text,
        muted: muted,
        data: moistHist,
      ),
      const SizedBox(height: 12),
      _buildPumpCard(
        isDark: isDark,
        comp: comp,
        text: text,
        muted: muted,
        btn: btn,
        running: pumpRunning,
        flow: flowRate,
      ),
      const SizedBox(height: 12),
      _buildRainCard(
        isDark: isDark,
        comp: comp,
        text: text,
        muted: muted,
        isRaining: isRaining,
      ),
      const SizedBox(height: 12),
      _buildProfileCard(isDark: isDark, comp: comp, text: text, muted: muted),
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

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
      decoration: _cardDeco(comp, text),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Soil Moisture History',
                style: _style(
                  text,
                  size: 16,
                  weight: FontWeight.bold,
                  fontFamily: 'Bungee',
                ),
              ),
              const Spacer(),
              _legendItem(Colors.redAccent, 'Dry (30%)'),
              const SizedBox(width: 14),
              _legendItem(_cMoisture, 'Wet (70%)'),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 210,
            child: spots.isEmpty
                ? Center(
                    child: Text('No data yet', style: _style(muted, size: 12)),
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
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Pump Status Card
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildPumpCard({
    required bool isDark,
    required Color comp,
    required Color text,
    required Color muted,
    required Color btn,
    required bool running,
    required double flow,
  }) {
    final bgColor = running
        ? Theme.of(
            context,
          ).colorScheme.secondaryContainer.withValues(alpha: isDark ? 0.55 : 1)
        : comp;
    final statusColor = running ? btn : muted;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: running
              ? btn.withValues(alpha: 0.35)
              : text.withValues(alpha: 0.07),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PUMP STATUS',
                  style: _style(muted, size: 11, letterSpacing: 0.9),
                ),
                const SizedBox(height: 4),
                Text(
                  running ? 'RUNNING' : 'IDLE',
                  style: _style(statusColor, size: 22, weight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  running ? 'Irrigating...' : 'Tap to override',
                  style: _style(muted, size: 13),
                ),
                const SizedBox(height: 6),
                RichText(
                  text: TextSpan(
                    text: 'Flow: ',
                    style: _style(muted, size: 13),
                    children: [
                      TextSpan(
                        text: '${flow.toStringAsFixed(2)} L/min',
                        style: _style(text, size: 13, weight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Override button
          GestureDetector(
            onTap: () {
              // TODO: state.togglePump()
            },
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: btn,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: btn.withValues(alpha: 0.45),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(
                PhosphorIcons.lightning(PhosphorIconsStyle.fill),
                color: Colors.white,
                size: 26,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Rain Sensor Card
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildRainCard({
    required bool isDark,
    required Color comp,
    required Color text,
    required Color muted,
    required bool isRaining,
  }) => Container(
    padding: const EdgeInsets.all(18),
    decoration: _cardDeco(comp, text),
    child: Row(
      children: [
        Icon(
          isRaining
              ? PhosphorIcons.cloudRain(PhosphorIconsStyle.fill)
              : PhosphorIcons.cloud(PhosphorIconsStyle.fill),
          color: isRaining ? _cMoisture : muted,
          size: 38,
        ),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isRaining ? 'Raining' : 'No Rain',
              style: _style(text, size: 16, weight: FontWeight.bold),
            ),
            const SizedBox(height: 2),
            Text(
              'Sensor: ${isRaining ? "wet" : "dry"}',
              style: _style(muted, size: 13),
            ),
          ],
        ),
      ],
    ),
  );

  // ─────────────────────────────────────────────────────────────────────────────
  // Active Profile Card
  // TODO: connect state.activeProfile when available in AppStateProvider
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildProfileCard({
    required bool isDark,
    required Color comp,
    required Color text,
    required Color muted,
  }) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: _cardDeco(comp, text),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ACTIVE PROFILE',
          style: _style(muted, size: 11, letterSpacing: 0.9),
        ),
        const SizedBox(height: 6),
        Text('Wheat', style: _style(text, size: 18, weight: FontWeight.bold)),
        const SizedBox(height: 12),
        _profileRow('Target range', '30% – 70%', text, muted),
        const SizedBox(height: 5),
        _profileRow('Kc coefficient', '1.15', text, muted),
      ],
    ),
  );

  Widget _profileRow(String label, String value, Color text, Color muted) =>
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: _style(muted, size: 13)),
          Text(value, style: _style(text, size: 13)),
        ],
      );

  // ─────────────────────────────────────────────────────────────────────────────
  // Temperature & Humidity Dual-Axis Chart
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildTempHumidChart({
    required bool isDark,
    required Color comp,
    required Color text,
    required Color muted,
    required List<_ChartPoint> tempData,
    required List<_ChartPoint> humidData,
    required double currentTemp,
  }) {
    final gridColor = text.withValues(alpha: 0.07);
    // Dynamic Y range for temperature axis
    final tempMin = (currentTemp - 2).floorToDouble();
    final tempMax = (currentTemp + 2).ceilToDouble();
    final tempInterval = ((tempMax - tempMin) / 4).ceilToDouble();
    final allData = [...tempData, ...humidData]
      ..sort((a, b) => a.time.compareTo(b.time));
    final tempRange = (tempMax - tempMin) <= 0 ? 1.0 : (tempMax - tempMin);
    final tempSpots = _timeSeriesToSpots(
      tempData,
      minTime: allData.isEmpty ? null : allData.first.time,
    );
    final humidSpots = _timeSeriesToSpots(
      humidData,
      minTime: allData.isEmpty ? null : allData.first.time,
      mapY: (y) => tempMin + (y.clamp(0, 100) / 100) * tempRange,
    );
    final maxX = <double>[
      tempSpots.isEmpty ? 0 : tempSpots.last.x,
      humidSpots.isEmpty ? 0 : humidSpots.last.x,
    ].reduce((a, b) => a > b ? a : b);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
      decoration: _cardDeco(comp, text),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Temperature & Humidity',
                style: _style(
                  text,
                  size: 16,
                  weight: FontWeight.bold,
                  fontFamily: 'Bungee',
                ),
              ),
              const Spacer(),
              _legendItem(_cTemp, 'Temp C'),
              const SizedBox(width: 14),
              _legendItem(_cHumid, 'Humidity %'),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 240,
            child: allData.isEmpty
                ? Center(
                    child: Text('No data yet', style: _style(muted, size: 12)),
                  )
                : LineChart(
                    LineChartData(
                      minX: 0,
                      maxX: maxX <= 0 ? 1 : maxX,
                      minY: tempMin,
                      maxY: tempMax,
                      borderData: FlBorderData(show: false),
                      clipData: const FlClipData.all(),
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: true,
                        horizontalInterval: tempInterval > 0 ? tempInterval : 1,
                        verticalInterval: (maxX <= 0 ? 1 : maxX) / 4,
                        getDrawingHorizontalLine: (_) => FlLine(
                          color: gridColor,
                          strokeWidth: 1,
                          dashArray: const [4, 4],
                        ),
                        getDrawingVerticalLine: (_) => FlLine(
                          color: gridColor,
                          strokeWidth: 1,
                          dashArray: const [4, 4],
                        ),
                      ),
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 34,
                            interval: tempInterval > 0 ? tempInterval : 1,
                            getTitlesWidget: (value, meta) => Text(
                              value.toStringAsFixed(0),
                              style: _style(muted, size: 10),
                            ),
                          ),
                        ),
                        rightTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 34,
                            interval: tempRange / 4,
                            getTitlesWidget: (value, meta) {
                              final humid =
                                  ((value - tempMin) / tempRange) * 100;
                              return Text(
                                humid.clamp(0, 100).toStringAsFixed(0),
                                style: _style(muted, size: 10),
                              );
                            },
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 20,
                            interval: (maxX <= 0 ? 1 : maxX) / 3,
                            getTitlesWidget: (value, meta) => Text(
                              _timeLabelFromMinutes(allData, value),
                              style: _style(muted, size: 10),
                            ),
                          ),
                        ),
                      ),
                      lineTouchData: LineTouchData(
                        touchTooltipData: LineTouchTooltipData(
                          getTooltipColor: (_) => comp,
                          getTooltipItems: (spots) => spots
                              .map(
                                (spot) => LineTooltipItem(
                                  '${_timeLabelFromMinutes(allData, spot.x)}\n${spot.y.toStringAsFixed(1)}',
                                  _style(text, size: 12),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                      lineBarsData: [
                        LineChartBarData(
                          spots: tempSpots,
                          isCurved: true,
                          color: _cTemp,
                          barWidth: 2,
                          isStrokeCapRound: true,
                          dotData: const FlDotData(show: false),
                        ),
                        LineChartBarData(
                          spots: humidSpots,
                          isCurved: true,
                          color: _cHumid,
                          barWidth: 2,
                          isStrokeCapRound: true,
                          dotData: const FlDotData(show: false),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
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
    FontWeight weight = FontWeight.normal,
    double? letterSpacing,
    String fontFamily = 'Quicksand',
  }) => TextStyle(
    color: color,
    fontSize: size,
    fontWeight: weight,
    fontFamily: fontFamily,
    letterSpacing: letterSpacing,
    decoration: TextDecoration.none,
  );

  BoxDecoration _cardDeco(Color comp, Color text) => BoxDecoration(
    color: comp,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: text.withValues(alpha: 0.07)),
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
          fontFamily: 'Quicksand',
          decoration: TextDecoration.none,
        ),
      ),
    ],
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// _SensorCard — radial gauge + sparkline
// ─────────────────────────────────────────────────────────────────────────────

class _SensorCard extends StatelessWidget {
  final bool isDark;
  final Color comp, text, muted, accentColor;
  final String label, value, unit;
  final PhosphorIconData icon;
  final List<_SparkPoint> sparkData;
  final double gaugeMax;

  const _SensorCard({
    required this.isDark,
    required this.comp,
    required this.text,
    required this.muted,
    required this.accentColor,
    required this.label,
    required this.value,
    required this.unit,
    required this.icon,
    required this.sparkData,
    required this.gaugeMax,
  });

  @override
  Widget build(BuildContext context) {
    final numValue = (double.tryParse(value) ?? 0.0)
        .clamp(0.0, gaugeMax)
        .toDouble();
    final progress = gaugeMax <= 0
        ? 0.0
        : (numValue / gaugeMax).clamp(0.0, 1.0);
    final trackColor = text.withValues(alpha: isDark ? 0.1 : 0.07);
    final sparkSpots = sparkData
        .map((point) => FlSpot(point.x.toDouble(), point.y))
        .toList();
    final sparkMax = sparkData.isEmpty
        ? 1.0
        : sparkData.map((e) => e.y).reduce((a, b) => a > b ? a : b);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      decoration: BoxDecoration(
        color: comp,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: text.withValues(alpha: 0.07)),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: accentColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: Colors.white, size: 20),
              ),
              const Spacer(),
              Text(
                label,
                style: TextStyle(
                  color: muted,
                  fontSize: 10,
                  letterSpacing: 0.6,
                  fontFamily: 'Quicksand',
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
          SizedBox(
            height: 130,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: progress),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutBack,
              builder: (context, animatedProgress, _) => Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 112,
                    height: 112,
                    child: CircularProgressIndicator(
                      value: 1,
                      strokeWidth: 12,
                      color: trackColor,
                    ),
                  ),
                  SizedBox(
                    width: 112,
                    height: 112,
                    child: CircularProgressIndicator(
                      value: animatedProgress,
                      strokeWidth: 12,
                      color: accentColor,
                      strokeCap: StrokeCap.round,
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        value,
                        style: TextStyle(
                          color: text,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Quicksand',
                          decoration: TextDecoration.none,
                        ),
                      ),
                      Text(
                        unit,
                        style: TextStyle(
                          color: muted,
                          fontSize: 12,
                          fontFamily: 'Quicksand',
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          SizedBox(
            height: 42,
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: 19,
                minY: 0,
                maxY: sparkMax <= 0 ? 1 : sparkMax * 1.1,
                clipData: const FlClipData.all(),
                borderData: FlBorderData(show: false),
                gridData: const FlGridData(show: false),
                titlesData: const FlTitlesData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: sparkSpots,
                    isCurved: true,
                    color: accentColor,
                    barWidth: 1.8,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: accentColor.withValues(alpha: 0.15),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
