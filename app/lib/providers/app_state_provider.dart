import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';

class AppStateProvider extends ChangeNotifier {
  // State variables
  bool _isLoading = true;
  String? _deviceId;
  Map<String, dynamic> _latestSensorData = {};
  List<Map<String, dynamic>> _sensorHistory = [];
  
  bool get isLoading => _isLoading;
  String? get deviceId => _deviceId;
  Map<String, dynamic> get latestSensorData => _latestSensorData;
  List<Map<String, dynamic>> get sensorHistory => _sensorHistory;

  // ── Subscription references (to prevent memory leaks) ─────────────────────
  late final StreamSubscription<AuthState> _authSub;
  RealtimeChannel? _realtimeChannel;

  AppStateProvider() {
    _init();
    // ── Listen to auth state changes ──────────────────────────────────────
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final event = data.event;
      if (event == AuthChangeEvent.signedIn) {
        _init();
      } else if (event == AuthChangeEvent.signedOut) {
        _clearRealtimeChannel();
        _deviceId = null;
        _latestSensorData = {};
        _sensorHistory = [];
        _isLoading = false;
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    _authSub.cancel();
    _clearRealtimeChannel();
    super.dispose();
  }

  void _clearRealtimeChannel() {
    if (_realtimeChannel != null) {
      Supabase.instance.client.removeChannel(_realtimeChannel!);
      _realtimeChannel = null;
    }
  }

  /// Public method for pull-to-refresh on the dashboard.
  Future<void> refresh() async {
    await _init();
  }

  Future<void> _init() async {
    _isLoading = true;
    notifyListeners();

    final session = Supabase.instance.client.auth.currentSession;
    if (session != null) {
      await _fetchUserDevices(session.user.id);
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> _fetchUserDevices(String userId) async {
    debugPrint('[DEBUG] Fetching devices for user: $userId');
    try {
      final response = await Supabase.instance.client
          .from('devices')
          .select()
          .eq('user_id', userId)
          .limit(1);

      debugPrint('[DEBUG] Devices response: $response');
      
      if (response.isNotEmpty) {
        _deviceId = response[0]['id'];
        debugPrint('[DEBUG] Device found: $_deviceId');
        await _subscribeToSensorData();
      } else {
        debugPrint('[DEBUG] No device linked to this user');
      }
    } catch (e) {
      debugPrint("[DEBUG] Error fetching devices: $e");
    }
  }

  Future<void> _subscribeToSensorData() async {
    if (_deviceId == null) return;

    debugPrint('[DEBUG] Subscribing to sensor data for device: $_deviceId');

    // Clean up any previous channel before creating a new one
    _clearRealtimeChannel();

    // Fetch the latest existing row so the dashboard isn't blank on first load
    final initial = await Supabase.instance.client
        .from('sensor_readings')
        .select()
        .eq('device_id', _deviceId!)
        .order('recorded_at', ascending: false)
        .limit(1)
        .maybeSingle();

    debugPrint('[DEBUG] Initial sensor data: $initial');

    if (initial != null) {
      _latestSensorData = initial;
      notifyListeners();
    }

    // Fetch historical data for charts (last 60 readings)
    final historyResponse = await Supabase.instance.client
        .from('sensor_readings')
        .select('soil_moisture, temperature_c, humidity, flow_litres, recorded_at')
        .eq('device_id', _deviceId!)
        .order('recorded_at', ascending: false)
        .limit(60);

    debugPrint('[DEBUG] History response count: ${historyResponse.length}');

    if (historyResponse.isNotEmpty) {
      _sensorHistory = historyResponse.reversed.toList();
      debugPrint('[DEBUG] Sensor history loaded: ${_sensorHistory.length} records');
      notifyListeners();
    } else {
      debugPrint('[DEBUG] No historical data found for this device');
    }

    // Then listen for new inserts in real-time
    _realtimeChannel = Supabase.instance.client
        .channel('public:sensor_readings:$_deviceId')   // unique channel per device
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'sensor_readings',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'device_id',
            value: _deviceId!,
          ),
          callback: (payload) {
            debugPrint('[DEBUG] Realtime update received: ${payload.newRecord}');
            _latestSensorData = payload.newRecord;
            _sensorHistory.add(payload.newRecord);
            if (_sensorHistory.length > 60) {
              _sensorHistory.removeAt(0);
            }
            notifyListeners();
          },
        )
        .subscribe();
    debugPrint('[DEBUG] Subscribed to realtime channel');
  }

  // ── Sign Out ──────────────────────────────────────────────────────────────
  // Call this from SettingsScreen. The auth listener above handles state clear.
  // The GoRouterRefreshStream in router.dart handles the redirect to /login.
  Future<void> signOut() async {
    await Supabase.instance.client.auth.signOut();
  }
}

