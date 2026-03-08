import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import '../providers/app_state_provider.dart';
import '../utils/unit_converter.dart';
import '../theme.dart';

class WaterUsageScreen extends StatelessWidget {
  const WaterUsageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final appColors = Theme.of(context).extension<AppColors>()!;
    return Consumer<AppStateProvider>(
      builder: (context, appState, _) {
        final volumeUnit = appState.volumeUnit;

        // In a full implementation, these data points would be aggregated from Supabase pump_logs
        // Using sample data in litres
        final List<double> rawData = [12, 18, 15, 25, 14, 30, 22];

        // Convert to display units
        final List<FlSpot> spots = rawData
            .asMap()
            .entries
            .map(
              (e) => FlSpot(
                e.key.toDouble() + 1,
                volumeUnit == 'gallons' ? e.value * 0.264172 : e.value,
              ),
            )
            .toList();

        final totalLitres = rawData.reduce((a, b) => a + b);
        final totalDisplay = UnitConverter.formatVolume(
          totalLitres.toDouble(),
          volumeUnit,
        );

        return Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              Text(
                "Water Usage",
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontFamily: 'Bungee',
                  fontSize: 24,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Estimated $totalDisplay used over the last 7 days based on pump logs.",
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 24),

              Card(
                color: colors.surface,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                PhosphorIcons.chartBar(),
                                color: colors.primary,
                              ),
                              SizedBox(width: 8),
                              Text("Weekly Trend"),
                            ],
                          ),
                          Text(
                            "Total: $totalDisplay",
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(color: colors.primary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        height: 250,
                        child: LineChart(
                          LineChartData(
                            gridData: const FlGridData(show: false),
                            titlesData: const FlTitlesData(
                              rightTitles: AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              topTitles: AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                            ),
                            borderData: FlBorderData(show: false),
                            lineBarsData: [
                              LineChartBarData(
                                spots: spots,
                                isCurved: true,
                                color: appColors.infoBlue,
                                barWidth: 4,
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
              ),
            ],
          ),
        );
      },
    );
  }
}
