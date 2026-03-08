import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import '../providers/app_state_provider.dart';
import '../widgets/settings_section.dart';
import '../widgets/dropdown_setting_tile.dart';
import '../widgets/toggle_setting_tile.dart';
import '../widgets/read_only_tile.dart';
import '../widgets/inline_password_tile.dart';
import '../widgets/device_health_tile.dart';
import '../widgets/delete_account_button.dart';
import '../widgets/enums.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _deviceTimezone = 'UTC';

  // --- Username edit state ---
  bool _isEditingUsername = false;
  late TextEditingController _usernameController;
  final FocusNode _usernameFocusNode = FocusNode();
  String? _usernameError;

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController();
    _initTimezone();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<AppStateProvider>();
      provider.checkDeviceStatus();
      _usernameController.text = provider.username;
    });
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _usernameFocusNode.dispose();
    super.dispose();
  }

  void _initTimezone() {
    // Use Dart's built-in — no plugin required
    final tzName = DateTime.now().timeZoneName;
    setState(() => _deviceTimezone = tzName);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AppStateProvider>().updateTimezone(tzName);
    });
  }

  void _startEditingUsername(String currentValue) {
    setState(() {
      _usernameController.text = currentValue;
      _usernameError = null;
      _isEditingUsername = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _usernameFocusNode.requestFocus();
    });
  }

  Future<void> _saveUsername() async {
    final value = _usernameController.text.trim();
    final error = _validateUsername(value);
    if (error != null) {
      setState(() => _usernameError = error);
      return;
    }
    setState(() => _usernameError = null);
    await context.read<AppStateProvider>().updateUsername(value);
    if (mounted) {
      setState(() => _isEditingUsername = false);
      _usernameFocusNode.unfocus();
    }
  }

  void _cancelEditUsername() {
    final provider = context.read<AppStateProvider>();
    setState(() {
      _usernameController.text = provider.username;
      _usernameError = null;
      _isEditingUsername = false;
    });
    _usernameFocusNode.unfocus();
  }

  Future<void> _signOut(BuildContext context) async {
    await context.read<AppStateProvider>().signOut();
  }

  Future<void> _deleteAccount(BuildContext context) async {
    await context.read<AppStateProvider>().deleteAccount();
  }

  String? _validateUsername(String? value) {
    if (value == null || value.isEmpty) return 'Username is required';
    if (value.length < 3) return 'Username must be at least 3 characters';
    if (value.length > 30) return 'Username must be at most 30 characters';
    final usernameRegex = RegExp(r'^[a-zA-Z0-9_]+$');
    if (!usernameRegex.hasMatch(value)) {
      return 'Username can only contain letters, numbers, and underscores';
    }
    return null;
  }

  Widget _buildUsernameRow(BuildContext context, AppStateProvider provider) {
    final colors = Theme.of(context).colorScheme;
    final settingsColor =
        Theme.of(context).textTheme.headlineMedium?.color ?? colors.onSurface;
    if (!_isEditingUsername) {
      return ListTile(
        leading: Icon(PhosphorIcons.user(), size: 20, color: settingsColor),
        title: Text(
          'Username',
          style: TextStyle(fontSize: 12, color: settingsColor),
        ),
        subtitle: Text(
          provider.username,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.normal,
            color: settingsColor,
          ),
        ),
        trailing: IconButton(
          icon: Icon(
            PhosphorIcons.pencilSimple(),
            size: 20,
            color: settingsColor,
          ),
          tooltip: 'Edit username',
          onPressed: () => _startEditingUsername(provider.username),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _usernameController,
            focusNode: _usernameFocusNode,
            decoration: InputDecoration(
              labelText: 'Username',
              hintText: 'Enter your username',
              errorText: _usernameError,
              prefixIcon: Icon(PhosphorIcons.user(), size: 20),
              border: const OutlineInputBorder(),
              suffixIcon: _usernameController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _usernameController.clear();
                        setState(() => _usernameError = null);
                      },
                    )
                  : null,
            ),
            onChanged: (_) {
              if (_usernameError != null) {
                setState(() => _usernameError = null);
              }
            },
            onSubmitted: (_) => _saveUsername(),
            textInputAction: TextInputAction.done,
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: provider.isSaving ? null : _cancelEditUsername,
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: provider.isSaving ? null : _saveUsername,
                icon: provider.isSaving
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colors.onPrimary,
                        ),
                      )
                    : const Icon(Icons.check, size: 18),
                label: Text(provider.isSaving ? 'Saving…' : 'Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final provider = context.watch<AppStateProvider>();
    final colors = Theme.of(context).colorScheme;
    final settingsColor =
        Theme.of(context).textTheme.headlineMedium?.color ?? colors.onSurface;

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              "Settings",
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontFamily: 'Bungee',
                fontSize: 24,
                color: settingsColor,
              ),
            ),
          ),

          SettingsSection(
            title: "Profile",
            leadingIcon: Icon(
              PhosphorIcons.user(),
              size: 20,
              color: settingsColor,
            ),
            children: [
              _buildUsernameRow(context, provider),
              ReadOnlyTile(
                title: "Email",
                value: user?.email ?? "Not logged in",
                icon: PhosphorIcons.envelope(),
              ),
            ],
          ),

          SettingsSection(
            title: "Localization",
            leadingIcon: Icon(
              PhosphorIcons.globe(),
              size: 20,
              color: settingsColor,
            ),
            children: [
              DropdownSettingTile<String>(
                title: "Temperature Unit",
                subtitle: "Display temperature in",
                icon: PhosphorIcons.thermometer(),
                value: provider.tempUnit,
                options: const {'celsius': '°C', 'fahrenheit': '°F'},
                onChanged: (value) => provider.updateTempUnit(value),
                saveStatus: provider.isSaving
                    ? SaveStatus.saving
                    : SaveStatus.idle,
              ),
              DropdownSettingTile<String>(
                title: "Volume Unit",
                subtitle: "Display water volume in",
                icon: PhosphorIcons.drop(),
                value: provider.volumeUnit,
                options: const {'litres': 'L', 'gallons': 'gal'},
                onChanged: (value) => provider.updateVolumeUnit(value),
                saveStatus: provider.isSaving
                    ? SaveStatus.saving
                    : SaveStatus.idle,
              ),
              ReadOnlyTile(
                title: "Timezone",
                value: _deviceTimezone,
                icon: PhosphorIcons.clock(),
              ),
            ],
          ),

          SettingsSection(
            title: "Notifications",
            leadingIcon: Icon(
              PhosphorIcons.bell(),
              size: 20,
              color: settingsColor,
            ),
            children: [
              ToggleSettingTile(
                title: "Pump Alerts",
                subtitle: "Notify on pump start/stop",
                icon: PhosphorIcons.power(),
                value: provider.pumpAlerts,
                onChanged: (value) =>
                    provider.updateNotificationSetting('pump_alerts', value),
                saveStatus: provider.isSaving
                    ? SaveStatus.saving
                    : SaveStatus.idle,
              ),
              ToggleSettingTile(
                title: "Soil Moisture Alerts",
                subtitle: "Critical moisture level warnings",
                icon: PhosphorIcons.plant(),
                value: provider.soilMoistureAlerts,
                onChanged: (value) => provider.updateNotificationSetting(
                  'soil_moisture_alerts',
                  value,
                ),
                saveStatus: provider.isSaving
                    ? SaveStatus.saving
                    : SaveStatus.idle,
              ),
              ToggleSettingTile(
                title: "Weather Alerts",
                subtitle: "Rain detection & irrigation skips",
                icon: PhosphorIcons.cloudRain(),
                value: provider.weatherAlerts,
                onChanged: (value) =>
                    provider.updateNotificationSetting('weather_alerts', value),
                saveStatus: provider.isSaving
                    ? SaveStatus.saving
                    : SaveStatus.idle,
              ),
              ToggleSettingTile(
                title: "Fertigation Reminders",
                subtitle: "Nutrient injection scheduling",
                icon: PhosphorIcons.flask(),
                value: provider.fertigationReminders,
                onChanged: (value) => provider.updateNotificationSetting(
                  'fertigation_reminders',
                  value,
                ),
                saveStatus: provider.isSaving
                    ? SaveStatus.saving
                    : SaveStatus.idle,
              ),
              ToggleSettingTile(
                title: "Device Offline Alerts",
                subtitle: "Network connectivity warnings",
                icon: PhosphorIcons.wifiSlash(),
                value: provider.deviceOfflineAlerts,
                onChanged: (value) => provider.updateNotificationSetting(
                  'device_offline_alerts',
                  value,
                ),
                saveStatus: provider.isSaving
                    ? SaveStatus.saving
                    : SaveStatus.idle,
              ),
              ToggleSettingTile(
                title: "Weekly Summary Report",
                subtitle: "Email digest of water usage",
                icon: PhosphorIcons.chartBar(),
                value: provider.weeklySummary,
                onChanged: (value) =>
                    provider.updateNotificationSetting('weekly_summary', value),
                saveStatus: provider.isSaving
                    ? SaveStatus.saving
                    : SaveStatus.idle,
              ),
            ],
          ),

          SettingsSection(
            title: "Security",
            leadingIcon: Icon(
              PhosphorIcons.lock(),
              size: 20,
              color: settingsColor,
            ),
            children: [
              InlinePasswordTile(
                title: "Change Password",
                icon: PhosphorIcons.lock(),
                onUpdate: (current, newPassword) =>
                    provider.updatePassword(current, newPassword),
                isLoading: provider.isSaving,
                errorMessage: provider.saveError,
              ),
            ],
          ),

          SettingsSection(
            title: "Device & System Health",
            leadingIcon: Icon(
              PhosphorIcons.hardDrives(),
              size: 20,
              color: settingsColor,
            ),
            children: [
              DeviceHealthTile(
                deviceName: provider.deviceName ?? 'No Device',
                isOnline: provider.isDeviceOnline,
                lastSeen: provider.deviceLastSeen,
                onRefresh: () => provider.refreshDeviceStatus(),
              ),
              ApiConnectivityTile(
                serviceName: "Supabase",
                isConnected: provider.isApiConnected,
              ),
              const ApiConnectivityTile(
                serviceName: "Open-Meteo",
                isConnected: true,
              ),
            ],
          ),

          const SizedBox(height: 24),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              "Account",
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: settingsColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 8),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: FilledButton.icon(
              onPressed: () => _signOut(context),
              style: FilledButton.styleFrom(
                backgroundColor: colors.error.withValues(alpha: 0.85),
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.logout),
              label: const Text("Sign Out"),
            ),
          ),

          DeleteAccountButton(
            onDelete: () => _deleteAccount(context),
            isLoading: provider.isSaving,
          ),
        ],
      ),
    );
  }
}
