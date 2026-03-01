import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:lucide_icons/lucide_icons.dart';

class AlertsScreen extends StatelessWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final stream = Supabase.instance.client
        .from('system_alerts')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .limit(20);

    return Scaffold(
      appBar: AppBar(title: const Text('System Alerts')),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text("Error: \${snapshot.error}"));
          }
          
          final alerts = snapshot.data ?? [];
          
          if (alerts.isEmpty) {
             return const Center(
               child: Column(
                 mainAxisAlignment: MainAxisAlignment.center,
                 children: [
                   Icon(LucideIcons.checkCircle, size: 64, color: Colors.green),
                   SizedBox(height: 16),
                   Text("No active alerts! System is running smoothly.")
                 ]
               )
             );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16.0),
            itemCount: alerts.length,
            itemBuilder: (context, index) {
              final alert = alerts[index];
              return Card(
                child: ListTile(
                  leading: const Icon(LucideIcons.alertTriangle, color: Colors.red),
                  title: Text(alert['alert_type'] ?? 'Unknown Alert'),
                  subtitle: Text(alert['message'] ?? 'No details.'),
                  trailing: alert['status'] == 'active' 
                    ? const Chip(label: Text('Active'), backgroundColor: Colors.red, labelStyle: TextStyle(color: Colors.white))
                    : const Chip(label: Text('Resolved')),
                ),
              );
            },
          );
        }
      )
    );
  }
}
