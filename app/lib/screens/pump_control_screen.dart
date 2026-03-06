import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:convert';
import '../providers/app_state_provider.dart';
import 'package:provider/provider.dart';

class PumpControlScreen extends StatefulWidget {
  const PumpControlScreen({super.key});

  @override
  State<PumpControlScreen> createState() => _PumpControlScreenState();
}

class _PumpControlScreenState extends State<PumpControlScreen> {
  bool _isChanging = false;

  Future<void> _togglePump(String deviceId, String command) async {
    setState(() => _isChanging = true);

    try {
      final backendUrl = dotenv.env['PYTHON_BACKEND_URL'] ?? 'http://localhost:8000';
      final response = await http.post(
        Uri.parse('$backendUrl/api/pump/toggle'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({"device_id": deviceId, "command": command}),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Pump $command sent successfully.'),
            behavior: SnackBarBehavior.floating,
          )
        );
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send command. Server returned ${response.statusCode}'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error connecting to backend: $e'),
          behavior: SnackBarBehavior.floating, // Enables floating behavior
        )
      );
    } finally {
      if (mounted) setState(() => _isChanging = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final deviceId = context.watch<AppStateProvider>().deviceId;

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Manual Pump Control', style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontFamily: 'Bungee',
              fontSize: 24,
            )),
            const SizedBox(height: 32),
            if (deviceId == null)
              const Text('No device selected.')
            else ...[
              FilledButton.icon(
                onPressed: _isChanging ? null : () => _togglePump(deviceId, "pump_on"),
                icon: const Icon(Icons.water_drop),
                label: const Text("TURN PUMP ON"),
                style: FilledButton.styleFrom(padding: const EdgeInsets.all(24)),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _isChanging ? null : () => _togglePump(deviceId, "pump_off"),
                icon: const Icon(Icons.stop_circle),
                label: const Text("TURN PUMP OFF"),
                style: FilledButton.styleFrom(padding: const EdgeInsets.all(24)),
              ),
            ]
          ],
        )
      )
    );
  }
}

