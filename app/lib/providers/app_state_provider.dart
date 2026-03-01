import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AppStateProvider extends ChangeNotifier {
  // State variables
  bool _isLoading = true;
  String? _deviceId;
  Map<String, dynamic> _latestSensorData = {};
  
  bool get isLoading => _isLoading;
  String? get deviceId => _deviceId;
  Map<String, dynamic> get latestSensorData => _latestSensorData;

  AppStateProvider() {
    _init();
  }

  Future<void> _init() async {
    // Check if user is logged in
    final session = Supabase.instance.client.auth.currentSession;
    if (session != null) {
      await _fetchUserDevices(session.user.id);
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> _fetchUserDevices(String userId) async {
    try {
      final response = await Supabase.instance.client
          .from('devices')
          .select()
          .eq('user_id', userId)
          .limit(1);
          
      if (response.isNotEmpty) {
        _deviceId = response[0]['id'];
        _subscribeToSensorData();
      }
    } catch (e) {
      debugPrint("Error fetching devices: \$e");
    }
  }

  void _subscribeToSensorData() {
    if (_deviceId == null) return;
    
    // Listen to realtime updates on sensor_readings table
    Supabase.instance.client
        .channel('public:sensor_readings')
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
              _latestSensorData = payload.newRecord;
              notifyListeners();
            })
        .subscribe();
  }
}
