import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  // Create the stream once, not on every build()
  late final Stream<List<Map<String, dynamic>>> _alertsStream;

  @override
  void initState() {
    super.initState();
    _alertsStream = Supabase.instance.client
        .from('system_alerts')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .limit(20);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _alertsStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text("Error: ${snapshot.error}"));
          }

          final alerts = snapshot.data ?? [];

          if (alerts.isEmpty) {
             return Center(
               child: Column(
                 mainAxisAlignment: MainAxisAlignment.center,
                 children: [
                   Icon(PhosphorIcons.checkCircle(), size: 64, color: Colors.green),
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
                  leading: Icon(PhosphorIcons.warning(PhosphorIconsStyle.fill), color: Colors.red),
                  title: Text(alert['alert_type'] ?? 'Unknown Alert'),
                  subtitle: Text(alert['message'] ?? 'No details.'),
                  trailing: alert['status'] == 'active'
                    ? const ActionChip(label: Text('Active'), backgroundColor: Colors.red, labelStyle: TextStyle(color: Colors.white))
                    : const ActionChip(label: Text('Resolved')),
                ),
              );
            },
          );
        }
      )
    );
  }
}


