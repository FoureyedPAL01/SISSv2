
// lib/screens/irrigation_screen.dart

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import '../providers/app_state_provider.dart';

class IrrigationScreen extends StatefulWidget {
  const IrrigationScreen({super.key});

  @override
  State<IrrigationScreen> createState() => _IrrigationScreenState();
}

class _IrrigationScreenState extends State<IrrigationScreen> {
  // Holds the chart points fetched from Supabase.
  // FlSpot(x, y) — x = day index (1–7), y = soil moisture %
  List<FlSpot> _moistureSpots = [];

  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchHistory();
  }

  void _fetchHistory() {
    final state = context.read<AppStateProvider>();
    final deviceId = state.deviceId;

    if (deviceId == null) {
      // No device linked — stop loading and show empty state
      setState(() { _isLoading = false; });
      return;
    }

    try {
      final now = DateTime.now();
      final spots = <FlSpot>[];

      for (final row in state.sensorHistory) {
        final String recordedAtStr = row['recorded_at'] ?? now.toIso8601String();
        final createdAt = DateTime.parse(recordedAtStr);
        final num moistureNum = row['soil_moisture'] ?? 0.0;
        final double moisture = moistureNum.toDouble();

        // How many days ago was this reading?
        // e.g. 6.5 days ago = x of 0.5, today = x of 7.0
        final daysAgo = now.difference(createdAt).inMinutes / (60 * 24);
        final x = (7.0 - daysAgo).clamp(0.0, 7.0);

        spots.add(FlSpot(x, moisture.clamp(0.0, 100.0)));
      }

      setState(() {
        _moistureSpots = spots;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to process history: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RefreshIndicator(
        // Pull-to-refresh re-runs the fetch
        onRefresh: () async {
          setState(() { _isLoading = true; _error = null; });
          await context.read<AppStateProvider>().refresh();
          if (mounted) _fetchHistory();
        },
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            Text("Irrigation History",
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontFamily: 'Poppins',
                  fontSize: 24,
                )),
            const SizedBox(height: 8),
            Text("Soil moisture timeline over the past week.", style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 24),
            _buildChartCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildChartCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(PhosphorIcons.drop(), color: Colors.green),
                SizedBox(width: 8),
                Text("Soil Moisture Trend (%)"),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 250,
              child: _buildChartBody(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChartBody() {
    // ── Loading state ──────────────────────────────────────────────────────
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // ── Error state ────────────────────────────────────────────────────────
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 40),
            const SizedBox(height: 8),
            Text(_error!, textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red)),
          ],
        ),
      );
    }

    // ── Empty state (no device or no readings yet) ─────────────────────────
    if (_moistureSpots.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(PhosphorIcons.chartBar(), size: 48, color: Colors.grey),
            SizedBox(height: 12),
            Text(
              "No data yet",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 4),
            Text(
              "Connect your ESP32 device to start\nseeing irrigation history here.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    // ── Chart (real data) ──────────────────────────────────────────────────
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
            color: Colors.grey.withValues(alpha: 0.2),
            strokeWidth: 1,
          ),
          getDrawingVerticalLine: (_) => FlLine(
            color: Colors.grey.withValues(alpha: 0.2),
            strokeWidth: 1,
            dashArray: [4, 4],
          ),
        ),
        titlesData: FlTitlesData(
          rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false)),
          // X axis: show day labels (Mon, Tue, etc.)
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 1,
              getTitlesWidget: (value, meta) {
                // Map 0–7 to actual day-of-week labels
                final day = DateTime.now()
                    .subtract(Duration(days: (7 - value).round()));
                const days = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
                return Text(
                  days[day.weekday - 1],
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                );
              },
            ),
          ),
          // Y axis: show % labels
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 20,
              getTitlesWidget: (value, meta) => Text(
                '${value.toInt()}%',
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: _moistureSpots,
            isCurved: true,
            color: Colors.green,
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                radius: 3,
                color: Colors.green,
                strokeWidth: 1,
                strokeColor: Colors.white,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              color: Colors.green.withValues(alpha: 0.15),
            ),
          ),
        ],
      ),
    );
  }
}


