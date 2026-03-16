// lib/services/mqtt_service.dart
// SISS v2 -- Connects to HiveMQ Cloud over TLS port 8883.
// Flutter only PUBLISHES pump commands; it does not subscribe to topics.
// All live sensor data arrives via Supabase Realtime, not MQTT.

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

class MqttService {
  MqttServerClient? _client;

  bool get isConnected =>
      _client?.connectionStatus?.state == MqttConnectionState.connected;

  Future<void> connect() async {
    final host     = dotenv.env['HIVEMQ_HOST']!;
    final port     = int.parse(dotenv.env['HIVEMQ_PORT'] ?? '8883');
    final user     = dotenv.env['HIVEMQ_USER']!;
    final password = dotenv.env['HIVEMQ_PASSWORD']!;

    // Append timestamp to ensure each app instance gets a unique client ID.
    // HiveMQ disconnects the older connection if two clients share the same ID.
    final clientId = 'siss-flutter-${DateTime.now().millisecondsSinceEpoch}';

    _client = MqttServerClient(host, clientId)
      ..port            = port
      ..secure          = true       // enables TLS -- required for port 8883
      ..keepAlivePeriod = 30
      ..logging(on: false)
      ..setProtocolV311()            // MQTT protocol version 3.1.1
      ..onDisconnected = _onDisconnected;

    // startClean() means no persistent session.
    // Fine here since Flutter only publishes and does not need queued messages.
    final connMsg = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .authenticateAs(user, password)
        .startClean()
        .withWillQos(MqttQos.atLeastOnce);
    _client!.connectionMessage = connMsg;

    try {
      await _client!.connect();
    } catch (e) {
      _client!.disconnect();
      rethrow;
    }
  }

  // Publish a pump command.
  // deviceId: the UUID from AppStateProvider.deviceId
  // command: 'pump_on' or 'pump_off'
  void sendPumpCommand(String deviceId, String command) {
    if (!isConnected) return;

    final topic   = 'devices/$deviceId/control';
    final payload = '{"command":"$command"}';
    final builder = MqttClientPayloadBuilder()..addString(payload);

    // QoS 1 = at least once. HiveMQ retries if ESP32 is briefly disconnected.
    // The consumed flag in device_commands prevents duplicate execution.
    _client!.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
  }

  void _onDisconnected() {
    Future.delayed(const Duration(seconds: 3), connect);
  }

  void disconnect() => _client?.disconnect();
}
