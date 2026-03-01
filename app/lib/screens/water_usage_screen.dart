import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:lucide_icons/lucide_icons.dart';

class WaterUsageScreen extends StatelessWidget {
  const WaterUsageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // In a full implementation, these data points would be aggregated from Supabase pump_logs
    final List<FlSpot> spots = [
      const FlSpot(1, 12),
      const FlSpot(2, 18),
      const FlSpot(3, 15),
      const FlSpot(4, 25),
      const FlSpot(5, 14),
      const FlSpot(6, 30),
      const FlSpot(7, 22),
    ];

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          Text("Water Usage", style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          const Text("Estimated Litres used over the last 7 days based on pump logs."),
          const SizedBox(height: 24),
          
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(LucideIcons.barChart2, color: Colors.blue),
                          SizedBox(width: 8),
                          Text("Weekly Trend"),
                        ],
                      ),
                      Text("Total: 136L", style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.blue)),
                    ],
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 250,
                    child: LineChart(
                      LineChartData(
                        gridData: const FlGridData(show: false),
                        titlesData: const FlTitlesData(
                          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        ),
                        borderData: FlBorderData(show: false),
                        lineBarsData: [
                          LineChartBarData(
                            spots: spots,
                            isCurved: true,
                            color: Colors.blue,
                            barWidth: 4,
                            isStrokeCapRound: true,
                            dotData: const FlDotData(show: false),
                            belowBarData: BarAreaData(
                              show: true,
                              color: Colors.blue.withValues(alpha: 0.2),
                            ),
                          ),
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
    );
  }
}
