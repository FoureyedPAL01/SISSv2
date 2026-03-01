import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:lucide_icons/lucide_icons.dart';

class IrrigationScreen extends StatelessWidget {
  const IrrigationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Mock past week soil moisture trend
    final List<FlSpot> moistureSpots = [
      const FlSpot(1, 40),
      const FlSpot(2, 35),
      const FlSpot(3, 28), // Dipped below thresh
      const FlSpot(4, 85), // Pump turned on
      const FlSpot(5, 70),
      const FlSpot(6, 60),
      const FlSpot(7, 52),
    ];

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          Text("Irrigation History", style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          const Text("Soil moisture timeline over the past week."),
          const SizedBox(height: 24),
          
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  const Row(
                    children: [
                      Icon(LucideIcons.droplets, color: Colors.green),
                      SizedBox(width: 8),
                      Text("Soil Moisture Trend (%)"),
                    ],
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 250,
                    child: LineChart(
                      LineChartData(
                        minY: 0,
                        maxY: 100,
                        titlesData: const FlTitlesData(
                          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        ),
                        borderData: FlBorderData(show: false),
                        lineBarsData: [
                          LineChartBarData(
                            spots: moistureSpots,
                            isCurved: true,
                            color: Colors.green,
                            barWidth: 4,
                            isStrokeCapRound: true,
                            dotData: const FlDotData(show: false),
                            belowBarData: BarAreaData(
                              show: true,
                              color: Colors.green.withValues(alpha: 0.2),
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
