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

  // Active crop profile
  Map<String, dynamic>? _activeCropProfile;

  // Water usage data
  List<Map<String, dynamic>> _weeklyWaterUsage = [];

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

  // Getter for active crop profile
  Map<String, dynamic>? get activeCropProfile => _activeCropProfile;

  // Getter for weekly water usage
  List<Map<String, dynamic>> get weeklyWaterUsage => _weeklyWaterUsage;

  // Getters for connectivity
  bool get isDeviceOnline => _isDeviceOnline;
  bool get isApiConnected => _isApiConnected;
  DateTime? get deviceLastSeen => _deviceLastSeen;
  String? get deviceName => _deviceName;

  // True once a device row has been found for the logged-in user.
  // GoRouter reads this to decide whether to redirect to /link-device.
  bool get hasDevice => _deviceId != null;

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
    Future.microtask(_init);
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final event = data.event;
      if (event == AuthChangeEvent.signedIn) {
        Future.microtask(_init);
      } else if (event == AuthChangeEvent.signedOut) {
        _clearRealtimeChannel();
        _deviceId = null;
        _latestSensorData = {};
        _sensorHistory = [];
        _userProfile = null;
        _activeCropProfile = null;
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
      await _fetchActiveCropProfile();
      await fetchWeeklyWaterUsage();
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
      debugPrint('[DEBUG] Error fetching devices: $e');
    }
  }

  Future<void> _subscribeToSensorData() async {
    if (_deviceId == null) return;

    debugPrint('[DEBUG] Subscribing to sensor data for device: $_deviceId');

    _clearRealtimeChannel();

    final initial = await Supabase.instance.client
        .from('sensor_readings')
        .select()
        .eq('device_id', _deviceId!)
        .order('recorded_at', ascending: false)
        .limit(1)
        .maybeSingle();

    if (initial != null) {
      _latestSensorData = initial;
      notifyListeners();
    }

    final historyResponse = await Supabase.instance.client
        .from('sensor_readings')
        .select('soil_moisture, temperature_c, humidity, flow_litres, recorded_at')
        .eq('device_id', _deviceId!)
        .order('recorded_at', ascending: false)
        .limit(60);

    if (historyResponse.isNotEmpty) {
      _sensorHistory = historyResponse.reversed.toList();
      notifyListeners();
    }

    _realtimeChannel = Supabase.instance.client
        .channel('public:sensor_readings:$_deviceId')
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
            _sensorHistory.add(payload.newRecord);
            if (_sensorHistory.length > 60) _sensorHistory.removeAt(0);
            notifyListeners();
          },
        )
        .subscribe();
  }

  Future<void> _fetchActiveCropProfile() async {
    if (_deviceId == null) return;

    try {
      final device = await Supabase.instance.client
          .from('devices')
          .select('crop_profile_id')
          .eq('id', _deviceId!)
          .maybeSingle();

      final profileId = device?['crop_profile_id'];
      if (profileId == null) {
        _activeCropProfile = null;
        notifyListeners();
        return;
      }

      final profile = await Supabase.instance.client
          .from('crop_profiles')
          .select()
          .eq('id', profileId as int)
          .maybeSingle();

      _activeCropProfile = profile;
      notifyListeners();
    } catch (e) {
      debugPrint('[DEBUG] Error fetching active crop profile: $e');
    }
  }

  Future<void> signOut() async {
    await Supabase.instance.client.auth.signOut();
  }

  Future<void> refreshCropProfile() async {
    await _fetchActiveCropProfile();
  }

  // ── Water Usage ──────────────────────────────────────────────────────────
  // Reads from pump_logs (which exists in your schema) instead of
  // water_usage (which does not exist).
  Future<void> fetchWeeklyWaterUsage() async {
    if (_deviceId == null) return;

    try {
      final weekAgo = DateTime.now().subtract(const Duration(days: 7));

      final response = await Supabase.instance.client
          .from('pump_logs')
          .select('pump_on_at, water_used_litres')
          .eq('device_id', _deviceId!)
          .gte('pump_on_at', weekAgo.toIso8601String())
          .order('pump_on_at', ascending: true);

      // Group by date and sum water used per day
      final Map<String, double> dailyTotals = {};
      for (final row in response) {
        final date = (row['pump_on_at'] as String).split('T')[0];
        final litres = (row['water_used_litres'] as num?)?.toDouble() ?? 0.0;
        dailyTotals[date] = (dailyTotals[date] ?? 0.0) + litres;
      }

      // Fill in missing days with 0
      _weeklyWaterUsage = List.generate(7, (i) {
        final day = weekAgo.add(Duration(days: i));
        final date = day.toIso8601String().split('T')[0];
        return {
          'date': date,
          'total_liters': dailyTotals[date] ?? 0.0,
        };
      });

      notifyListeners();
    } catch (e) {
      debugPrint('[DEBUG] Error fetching water usage: $e');
      _weeklyWaterUsage = [];
    }
  }

  // ── User Profile ─────────────────────────────────────────────────────────
  // FIX: users table primary key is 'id', not 'user_id'
  Future<void> fetchUserProfile() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final response = await Supabase.instance.client
          .from('users')
          .select()
          .eq('id', userId)           // ← FIXED: was 'user_id'
          .maybeSingle();

      _userProfile = response;

      if (_userProfile == null) {
        // Row missing — insert it (the trigger should have done this on signup,
        // but insert manually as a fallback)
        await Supabase.instance.client.from('users').insert({
          'id': userId,               // ← FIXED: was 'user_id'
        });
        _userProfile = await Supabase.instance.client
            .from('users')
            .select()
            .eq('id', userId)         // ← FIXED: was 'user_id'
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
          .from('users')
          .update({field: value})
          .eq('id', Supabase.instance.client.auth.currentUser!.id); // ← FIXED: was 'user_id'

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

  // ── Device Status ────────────────────────────────────────────────────────
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
