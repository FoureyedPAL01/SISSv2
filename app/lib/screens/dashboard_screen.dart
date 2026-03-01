import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../providers/app_state_provider.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppStateProvider>(
      builder: (context, state, child) {
        if (state.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (state.deviceId == null) {
          return const Center(child: Text("No device linked to this account."));
        }

        final data = state.latestSensorData;
        final moisture = data['soil_moisture']?.toStringAsFixed(1) ?? '--';
        final temp = data['temperature_c']?.toStringAsFixed(1) ?? '--';
        final humidity = data['humidity']?.toStringAsFixed(1) ?? '--';
        final isRaining = data['rain_detected'] == true;

        return RefreshIndicator(
          onRefresh: () async {
            // Realtime updates handle this, but for UX we can let them pull to refresh.
          },
          child: ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              Text("Device Status: Online", style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              
              GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _StatCard(title: "Soil Moisture", value: moisture, unit: "%", icon: LucideIcons.droplets, color: Colors.blue),
                  _StatCard(title: "Temperature", value: temp, unit: "°C", icon: LucideIcons.thermometer, color: Colors.orange),
                  _StatCard(title: "Humidity", value: humidity, unit: "%", icon: LucideIcons.cloud, color: Colors.lightBlue),
                  _StatCard(title: "Rain Sensor", value: isRaining ? "Raining" : "Dry", unit: "", icon: isRaining ? LucideIcons.cloudRain : LucideIcons.sun, color: isRaining ? Colors.indigo : Colors.amber),
                ],
              ),
              
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Recent Pump Activity", style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 16),
                      const ListTile(
                        leading: Icon(LucideIcons.power, color: Colors.green),
                        title: Text("Pump turned ON (Automated)"),
                        subtitle: Text("2 hours ago"),
                      ),
                      const ListTile(
                        leading: Icon(LucideIcons.powerOff, color: Colors.red),
                        title: Text("Pump turned OFF (Timeout)"),
                        subtitle: Text("1.5 hours ago"),
                      ),
                    ],
                  ),
                ),
              )
            ],
          ),
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final String unit;
  final IconData icon;
  final Color color;

  const _StatCard({required this.title, required this.value, required this.unit, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(height: 8),
            Text(title, style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(value, style: Theme.of(context).textTheme.headlineMedium),
                if (unit.isNotEmpty) Text(" $unit", style: Theme.of(context).textTheme.bodyMedium),
              ],
            )
          ],
        ),
      ),
    );
  }
}
