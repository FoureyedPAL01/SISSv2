import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';

class AppStateProvider extends ChangeNotifier {
  // State variables
  bool _isLoading = true;
  String? _deviceId;
  Map<String, dynamic> _latestSensorData = {};
  List<Map<String, dynamic>> _sensorHistory = [];
  
  // User profile and settings
  Map<String, dynamic>? _userProfile;
  bool _isSaving = false;
  String? _saveError;
  
  // Device and connectivity status
  bool _isDeviceOnline = false;
  bool _isApiConnected = false;
  DateTime? _deviceLastSeen;
  String? _deviceName;
  
  bool get isLoading => _isLoading;
  String? get deviceId => _deviceId;
  Map<String, dynamic> get latestSensorData => _latestSensorData;
  List<Map<String, dynamic>> get sensorHistory => _sensorHistory;
  
  // Getters for user profile
  Map<String, dynamic>? get userProfile => _userProfile;
  bool get isSaving => _isSaving;
  String? get saveError => _saveError;
  
  // Getters for connectivity
  bool get isDeviceOnline => _isDeviceOnline;
  bool get isApiConnected => _isApiConnected;
  DateTime? get deviceLastSeen => _deviceLastSeen;
  String? get deviceName => _deviceName;
  
  // Convenience getters for profile fields
  String get username => _userProfile?['username'] ?? '';
  String get tempUnit => _userProfile?['temp_unit'] ?? 'celsius';
  String get volumeUnit => _userProfile?['volume_unit'] ?? 'litres';
  String get timezone => _userProfile?['timezone'] ?? 'UTC';
  bool get pumpAlerts => _userProfile?['pump_alerts'] ?? true;
  bool get soilMoistureAlerts => _userProfile?['soil_moisture_alerts'] ?? true;
  bool get weatherAlerts => _userProfile?['weather_alerts'] ?? true;
  bool get fertigationReminders => _userProfile?['fertigation_reminders'] ?? true;
  bool get deviceOfflineAlerts => _userProfile?['device_offline_alerts'] ?? true;
  bool get weeklySummary => _userProfile?['weekly_summary'] ?? false;

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
        _userProfile = null;
        _isDeviceOnline = false;
        _isApiConnected = false;
        _deviceLastSeen = null;
        _deviceName = null;
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
      await fetchUserProfile();
      await _fetchUserDevices(session.user.id);
      await checkDeviceStatus();
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
  
  // ── User Profile Methods ──────────────────────────────────────────────────
  Future<void> fetchUserProfile() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    
    try {
      final response = await Supabase.instance.client
          .from('user_profiles')
          .select()
          .eq('user_id', userId)
          .maybeSingle();
      
      _userProfile = response;
      
      if (_userProfile == null) {
        await Supabase.instance.client.from('user_profiles').insert({
          'user_id': userId,
        });
        _userProfile = await Supabase.instance.client
            .from('user_profiles')
            .select()
            .eq('user_id', userId)
            .single();
      }
      
      notifyListeners();
    } catch (e) {
      debugPrint('[DEBUG] Error fetching user profile: $e');
    }
  }
  
  Future<void> updateUsername(String username) async {
    await _updateProfileField('username', username);
  }
  
  Future<void> updateTempUnit(String unit) async {
    await _updateProfileField('temp_unit', unit);
  }
  
  Future<void> updateVolumeUnit(String unit) async {
    await _updateProfileField('volume_unit', unit);
  }
  
  Future<void> updateTimezone(String tz) async {
    await _updateProfileField('timezone', tz);
  }
  
  Future<void> updateNotificationSetting(String field, bool value) async {
    await _updateProfileField(field, value);
  }
  
  Future<void> _updateProfileField(String field, dynamic value) async {
    if (_userProfile == null) return;
    
    _isSaving = true;
    _saveError = null;
    notifyListeners();
    
    try {
      await Supabase.instance.client
          .from('user_profiles')
          .update({field: value, 'updated_at': DateTime.now().toIso8601String()})
          .eq('user_id', Supabase.instance.client.auth.currentUser!.id);
      
      _userProfile![field] = value;
      _isSaving = false;
      notifyListeners();
    } catch (e) {
      _isSaving = false;
      _saveError = e.toString();
      notifyListeners();
      debugPrint('[DEBUG] Error updating profile field $field: $e');
    }
  }
  
  Future<void> updatePassword(String currentPassword, String newPassword) async {
    _isSaving = true;
    _saveError = null;
    notifyListeners();
    
    try {
      final currentUser = Supabase.instance.client.auth.currentUser;
      if (currentUser == null || currentUser.email == null) {
        throw Exception('No user logged in');
      }
      
      await Supabase.instance.client.auth.signInWithPassword(
        email: currentUser.email!,
        password: currentPassword,
      );
      
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: newPassword),
      );
      
      _isSaving = false;
      notifyListeners();
    } on AuthException catch (e) {
      _isSaving = false;
      _saveError = e.message;
      notifyListeners();
      rethrow;
    } catch (e) {
      _isSaving = false;
      _saveError = e.toString();
      notifyListeners();
      rethrow;
    }
  }
  
  Future<void> deleteAccount() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    
    _isSaving = true;
    notifyListeners();
    
    try {
      await Supabase.instance.client.rpc('delete_account_cascade', params: {
        'uid': userId,
      });
      
      await signOut();
    } catch (e) {
      _isSaving = false;
      _saveError = e.toString();
      notifyListeners();
      debugPrint('[DEBUG] Error deleting account: $e');
      rethrow;
    }
  }
  
  // ── Device Status Methods ────────────────────────────────────────────────
  Future<void> checkDeviceStatus() async {
    try {
      await Supabase.instance.client.from('devices').select('id').limit(1);
      _isApiConnected = true;
    } catch (e) {
      _isApiConnected = false;
    }
    
    final deviceId = _deviceId;
    if (deviceId != null) {
      try {
        final deviceInfo = await Supabase.instance.client
            .from('devices')
            .select('name, status')
            .eq('id', deviceId)
            .single();
        
        _deviceName = deviceInfo['name'] ?? 'Unknown Device';
        
        final latest = await Supabase.instance.client
            .from('sensor_readings')
            .select('recorded_at')
            .eq('device_id', deviceId)
            .order('recorded_at', ascending: false)
            .limit(1)
            .maybeSingle();
        
        if (latest != null) {
          _deviceLastSeen = DateTime.parse(latest['recorded_at']);
          _isDeviceOnline = DateTime.now().difference(_deviceLastSeen!).inMinutes < 5;
        } else {
          _isDeviceOnline = false;
          _deviceLastSeen = null;
        }
      } catch (e) {
        _isDeviceOnline = false;
        _deviceName = null;
      }
    }
    
    notifyListeners();
  }
  
  Future<void> refreshDeviceStatus() async {
    await checkDeviceStatus();
  }
}

