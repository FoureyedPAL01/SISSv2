// lib/services/mqtt_service.dart
// Connects to HiveMQ Cloud over TLS port 8883 (mobile/desktop only).
// MQTT is silently disabled on web — pump commands fall back to Supabase
// device_commands table which is always available.

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

class MqttService {
  MqttServerClient? _client;

  bool get isConnected =>
      !kIsWeb &&
      _client?.connectionStatus?.state == MqttConnectionState.connected;

  Future<void> connect() async {
    // MQTT over raw TLS (port 8883) does not work in browsers.
    // Pump control falls back to the Supabase device_commands table.
    if (kIsWeb) return;

    final host     = dotenv.env['HIVEMQ_HOST']!;
    final port     = int.parse(dotenv.env['HIVEMQ_PORT'] ?? '8883');
    final user     = dotenv.env['HIVEMQ_USER']!;
    final password = dotenv.env['HIVEMQ_PASSWORD']!;

    final clientId = 'siss-flutter-${DateTime.now().millisecondsSinceEpoch}';

    _client = MqttServerClient(host, clientId)
      ..port            = port
      ..secure          = true
      ..keepAlivePeriod = 30
      ..logging(on: false)
      ..setProtocolV311()
      ..onDisconnected = _onDisconnected;

    final connMsg = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .authenticateAs(user, password)
        .startClean()
        .withWillQos(MqttQos.atLeastOnce);
    _client!.connectionMessage = connMsg;

    try {
      await _client!.connect();
    } catch (e) {
      _client?.disconnect();
      // Log but don't rethrow — dashboard pump widget falls back to
      // Supabase device_commands when MQTT is unavailable.
    }
  }

  void sendPumpCommand(String deviceId, String command) {
    if (!isConnected) return; // silently skip; caller uses Supabase fallback

    final topic   = 'devices/$deviceId/control';
    final payload = '{"command":"$command"}';
    final builder = MqttClientPayloadBuilder()..addString(payload);
    _client!.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
  }

  void _onDisconnected() {
    if (kIsWeb) return;
    Future.delayed(const Duration(seconds: 3), connect);
  }

  void disconnect() => _client?.disconnect();
}
