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
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = Theme.of(context).scaffoldBackgroundColor;
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
        final d = state.latestSensorData;
        final moisture = (d['soil_moisture'] as num? ?? 20).toDouble();
        final tempC = (d['temperature_c'] as num? ?? 20).toDouble();
        final humidity = (d['humidity'] as num? ?? 20).toDouble();
        final flowLpm = (d['flow_litres'] as num? ?? 20).toDouble();

        final tempUnit = state.tempUnit;
        final tempDisplay = UnitConverter.formatTemp(tempC, tempUnit);

        final isRaining = d['rain_detected'] == true;

        // TODO: pull pumpRunning from state.pumpStatus when available
        const pumpRunning = false;

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
                      _buildHeader(text),
                      const SizedBox(height: 20),

                      // ── 1. Four Sensor Cards ─────────────────────────
                      _buildSensorCards(
                        isDark: isDark,
                        comp: comp,
                        text: text,
                        muted: muted,
                        isDesktop: isDesktop,
                        moisture: moisture,
                        tempC: tempC,
                        humidity: humidity,
                        flowRate: flowLpm,
                        tempDisplay: tempDisplay,
                      ),
                      const SizedBox(height: 16),

                      // ── 2. Pump + Rain + Profile ─────────────────────
                      isDesktop
                          ? _buildStatusRowDesktop(
                              isDark: isDark,
                              comp: comp,
                              text: text,
                              muted: muted,
                              btn: btn,
                              isRaining: isRaining,
                              pumpRunning: pumpRunning,
                              flowRate: flowLpm,
                              cropProfile: state.activeCropProfile,
                            )
                          : _buildStatusRowMobile(
                              isDark: isDark,
                              comp: comp,
                              text: text,
                              muted: muted,
                              btn: btn,
                              isRaining: isRaining,
                              pumpRunning: pumpRunning,
                              flowRate: flowLpm,
                              cropProfile: state.activeCropProfile,
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
  // Header — title only, no subtitle
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildHeader(Color text) => Text(
    'Dashboard',
    style: _style(
      text,
      size: 28,
      weight: FontWeight.bold,
      fontFamily: 'Poppins',
    ),
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
    required double tempC,
    required double humidity,
    required double flowRate,
    String? tempDisplay,
  }) {
    // Split "82.4°F" → value="82.4", unit="°F"
    // If no tempDisplay, fall back to raw °C
    final _tempValue = tempDisplay != null
        ? RegExp(r'^([\d.]+)(°[CF])$').firstMatch(tempDisplay!)?.group(1)
            ?? tempDisplay!
        : tempC.toStringAsFixed(1);

    final _tempUnit = tempDisplay != null
        ? RegExp(r'^([\d.]+)(°[CF])$').firstMatch(tempDisplay!)?.group(2)
            ?? ''
        : '°C';
    final cards = <_SensorCard>[
      _SensorCard(
        isDark: isDark,
        comp: comp,
        text: text,
        muted: muted,
        label: 'SOIL MOISTURE',
        numericValue: moisture,
        displayValue: moisture.toStringAsFixed(1),
        unit: '%',
        accentColor: _cMoisture,
        icon: PhosphorIcons.drop(),
        gaugeMax: 100,
      ),
      _SensorCard(
        isDark: isDark,
        comp: comp,
        text: text,
        muted: muted,
        label: 'TEMPERATURE',
        numericValue: tempC,
        displayValue: _tempValue,
        unit: _tempUnit,
        accentColor: _cTemp,
        icon: PhosphorIcons.thermometer(),
        gaugeMax: 50,
      ),
      _SensorCard(
        isDark: isDark,
        comp: comp,
        text: text,
        muted: muted,
        label: 'HUMIDITY',
        numericValue: humidity,
        displayValue: humidity.toStringAsFixed(1),
        unit: '%',
        accentColor: _cHumid,
        icon: PhosphorIcons.cloud(),
        gaugeMax: 100,
      ),
      _SensorCard(
        isDark: isDark,
        comp: comp,
        text: text,
        muted: muted,
        label: 'FLOW RATE',
        numericValue: flowRate,
        displayValue: flowRate.toStringAsFixed(1),
        unit: 'L/min',
        accentColor: _cFlow,
        icon: PhosphorIcons.waveform(),
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
  // Status Row — Desktop (pump | rain | profile side by side)
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildStatusRowDesktop({
    required bool isDark,
    required Color comp,
    required Color text,
    required Color muted,
    required Color btn,
    required bool isRaining,
    required bool pumpRunning,
    required double flowRate,
    Map<String, dynamic>? cropProfile,
  }) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _buildPumpCard(
            isDark: isDark,
            comp: comp,
            text: text,
            muted: muted,
            running: pumpRunning,
          ),
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
        const SizedBox(width: 12),
        Expanded(
          child: _buildProfileCard(
            isDark: isDark,
            comp: comp,
            text: text,
            muted: muted,
            cropProfile: cropProfile,
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
    required bool pumpRunning,
    required double flowRate,
    Map<String, dynamic>? cropProfile,
  }) => Column(
    children: [
      _buildPumpCard(
        isDark: isDark,
        comp: comp,
        text: text,
        muted: muted,
        running: pumpRunning,
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
      _buildProfileCard(isDark: isDark, comp: comp, text: text, muted: muted, cropProfile: cropProfile),
    ],
  );

  // ─────────────────────────────────────────────────────────────────────────────
  // Pump Status Card — with icon that changes color based on status
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildPumpCard({
    required bool isDark,
    required Color comp,
    required Color text,
    required Color muted,
    required bool running,
  }) {
    // Icon colors: green for running, grey for idle
    const runningIconColor = Color(0xFF4CAF50);
    const idleIconColor = Color(0xFF888888);
    final iconColor = running ? runningIconColor : idleIconColor;
    final iconBgColor = running
        ? runningIconColor.withValues(alpha: 0.15)
        : idleIconColor.withValues(alpha: 0.1);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
      decoration: BoxDecoration(
        color: comp,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: text.withValues(alpha: 0.1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'PUMP STATUS',
                style: _style(muted, size: 11, letterSpacing: 0.9),
              ),
              const SizedBox(height: 4),
              Text(
                running ? 'RUNNING' : 'IDLE',
                style: _style(text, size: 18, weight: FontWeight.bold),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconBgColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              running
                  ? PhosphorIcons.dropSimple()
                  : PhosphorIcons.dropSlash(),
              color: iconColor,
              size: 24,
            ),
          ),
        ],
      ),
    );
  }

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
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
      decoration: _cardDeco(comp, text),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'RAIN STATUS',
                style: _style(muted, size: 11, letterSpacing: 0.9),
              ),
              const SizedBox(height: 4),
              Text(
                isRaining ? 'RAINING' : 'NO RAIN',
                style: _style(text, size: 18, weight: FontWeight.bold),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconBgColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isRaining
                  ? PhosphorIcons.cloudRain(PhosphorIconsStyle.fill)
                  : PhosphorIcons.cloudSlash(),
              color: iconColor,
              size: 24,
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
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
      decoration: _cardDeco(comp, text),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'ACTIVE PROFILE',
                style: _style(muted, size: 11, letterSpacing: 0.9),
              ),
              const SizedBox(height: 4),
              Text(
                profileName,
                style: _style(text, size: 18, weight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              ),
            ],
          ),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _profileStatRow('Target', '$minMoisture% – $maxMoisture%', text, muted),
                  const SizedBox(height: 2),
                  _profileStatRow('Watering', '${cropProfile?['watering_minutes'] ?? 5} min', text, muted),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconBgColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              PhosphorIcons.plant(PhosphorIconsStyle.fill),
              color: profileIconColor,
              size: 24,
            ),
          ),
        ],
      ),
    );
  }

  Widget _profileStatRow(
    String label,
    String value,
    Color text,
    Color muted,
  ) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text('$label  ', style: _style(muted, size: 12)),
      Text(value, style: _style(text, size: 12, weight: FontWeight.bold)),
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
              Flexible(
                child: Text(
                  'Soil Moisture History',
                  style: _style(
                    text,
                    size: 16,
                    weight: FontWeight.bold,
                    fontFamily: 'Poppins',
                  ),
                ),
              ),
              const Spacer(),
              _legendItem(Colors.redAccent, 'Dry'),
              const SizedBox(width: 8),
              _legendItem(_cMoisture, 'Wet'),
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
                            cutOffY: 0,
                            applyCutOffY: true,
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
  // Temperature & Humidity — dual line chart, fixed 0–100 Y axis
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

    // Both series share the same timestamps — use temp as the time base
    final baseTime = tempData.isEmpty ? null : tempData.first.time;
    final tempSpots  = _timeSeriesToSpots(tempData,  minTime: baseTime);
    final humidSpots = _timeSeriesToSpots(humidData, minTime: baseTime);
    final maxX = tempSpots.isEmpty ? 1.0 : tempSpots.last.x;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
      decoration: _cardDeco(comp, text),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  'Temperature & Humidity',
                  style: _style(text, size: 16, weight: FontWeight.bold,
                      fontFamily: 'Poppins'),
                ),
              ),
              const Spacer(),
              _legendItem(_cTemp,  'Temp'),
              const SizedBox(width: 8),
              _legendItem(_cHumid, 'Humid'),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 210,
            child: tempSpots.isEmpty
                ? Center(child: Text('No data yet', style: _style(muted, size: 12)))
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
                            sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
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
                          getTooltipItems: (spots) => spots.map((spot) {
                            final isTemp = spot.barIndex == 0;
                            return LineTooltipItem(
                              '${_timeLabelFromMinutes(tempData, spot.x)}\n'
                              '${spot.y.toStringAsFixed(1)}'
                              '${isTemp ? '°C' : '%'}',
                              _style(isTemp ? _cTemp : _cHumid, size: 12),
                            );
                          }).toList(),
                        ),
                      ),
                      lineBarsData: [
                        // ── Temperature ──────────────────────────────────
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
        ],
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
          fontFamily: 'Poppins',
          decoration: TextDecoration.none,
        ),
      ),
    ],
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// _SensorCard — radial gauge only, no sparkline, circle centered
// ─────────────────────────────────────────────────────────────────────────────

class _SensorCard extends StatelessWidget {
  final bool isDark;
  final Color comp, text, muted, accentColor;
  final String label, displayValue, unit;
  final double numericValue; // always the raw numeric for gauge calculation
  final PhosphorIconData icon;
  final double gaugeMax;

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
  });

  @override
  Widget build(BuildContext context) {
    // Use numericValue (always a raw double) for gauge — avoids parsing failures
    final clamped = numericValue.clamp(0.0, gaugeMax).toDouble();
    final progress = gaugeMax <= 0 ? 0.0 : (clamped / gaugeMax).clamp(0.0, 1.0);
    final trackColor = text.withValues(alpha: isDark ? 0.12 : 0.09);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Top row: icon left, label right ──────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: accentColor,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, color: Colors.white, size: 16),
              ),
              const Spacer(),
              Text(
                label,
                style: TextStyle(
                  color: muted,
                  fontSize: 10,
                  letterSpacing: 0.6,
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.bold,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Gauge — centered ──────────────────────────────────────────
          Center(
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: progress),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutBack,
              builder: (context, animatedProgress, _) => SizedBox(
                width: 90,
                height: 90,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Track (full circle, background color)
                    SizedBox.expand(
                      child: CircularProgressIndicator(
                        value: 1.0,
                        strokeWidth: 9,
                        color: trackColor,
                        strokeCap: StrokeCap.round,
                      ),
                    ),
                    // Progress arc (accent color)
                    SizedBox.expand(
                      child: CircularProgressIndicator(
                        value: animatedProgress,
                        strokeWidth: 9,
                        color: accentColor,
                        backgroundColor: Colors.transparent,
                        strokeCap: StrokeCap.round,
                      ),
                    ),
                    // Value text in center
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          displayValue,
                          style: TextStyle(
                            color: text,
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Poppins',
                            decoration: TextDecoration.none,
                          ),
                        ),
                        if (unit.isNotEmpty)
                          Text(
                            unit,
                            style: TextStyle(
                              color: muted,
                              fontSize: 11,
                              fontFamily: 'Poppins',
                              decoration: TextDecoration.none,
                            ),
                          ),
                      ],
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
