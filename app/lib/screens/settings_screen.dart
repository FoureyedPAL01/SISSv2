import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state_provider.dart';
import '../widgets/settings_section.dart';
import '../widgets/toggle_setting_tile.dart';
import '../widgets/enums.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppStateProvider>().checkDeviceStatus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppStateProvider>();
    final colors = Theme.of(context).colorScheme;
    final settingsColor =
        Theme.of(context).textTheme.headlineMedium?.color ?? colors.onSurface;

    return Scaffold(
      backgroundColor: colors.surfaceContainerHighest,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 36),
        children: [
          // ── Appearance ────────────────────────────────────────────────
          SettingsSection(
            title: 'Appearance',
            leadingIcon: Icon(
              Icons.palette_outlined,
              size: 20,
              color: settingsColor,
            ),
            children: [
              RadioGroup<ThemeMode>(
                groupValue: provider.themeMode,
                onChanged: (v) => provider.updateThemeMode(v!),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RadioListTile<ThemeMode>(
                      secondary: Icon(
                        Icons.light_mode_outlined,
                        color: settingsColor,
                        size: 20,
                      ),
                      title: Text(
                        'Light',
                        style: TextStyle(color: settingsColor),
                      ),
                      subtitle: Text(
                        'Always use light theme',
                        style: TextStyle(
                          color: settingsColor.withValues(alpha: 0.6),
                          fontSize: 12,
                        ),
                      ),
                      value: ThemeMode.light,
                    ),
                    RadioListTile<ThemeMode>(
                      secondary: Icon(
                        Icons.dark_mode_outlined,
                        color: settingsColor,
                        size: 20,
                      ),
                      title: Text(
                        'Dark',
                        style: TextStyle(color: settingsColor),
                      ),
                      subtitle: Text(
                        'Always use dark theme',
                        style: TextStyle(
                          color: settingsColor.withValues(alpha: 0.6),
                          fontSize: 12,
                        ),
                      ),
                      value: ThemeMode.dark,
                    ),
                    RadioListTile<ThemeMode>(
                      secondary: Icon(
                        Icons.phone_android_outlined,
                        color: settingsColor,
                        size: 20,
                      ),
                      title: Text(
                        'System Default',
                        style: TextStyle(color: settingsColor),
                      ),
                      subtitle: Text(
                        'Follow device theme setting',
                        style: TextStyle(
                          color: settingsColor.withValues(alpha: 0.6),
                          fontSize: 12,
                        ),
                      ),
                      value: ThemeMode.system,
                    ),
                  ],
                ),
              ),
            ],
          ),

          // ── Notifications ─────────────────────────────────────────────
          SettingsSection(
            title: 'Notifications',
            leadingIcon: Icon(
              Icons.notifications_outlined,
              size: 20,
              color: settingsColor,
            ),
            children: [
              ToggleSettingTile(
                title: 'Pump Alerts',
                subtitle: 'Notify on pump start/stop',
                icon: Icons.power_settings_new,
                value: provider.pumpAlerts,
                onChanged: (v) =>
                    provider.updateNotificationSetting('pump_alerts', v),
                saveStatus: provider.isSaving
                    ? SaveStatus.saving
                    : SaveStatus.idle,
              ),
              ToggleSettingTile(
                title: 'Soil Moisture Alerts',
                subtitle: 'Critical moisture level warnings',
                icon: Icons.eco,
                value: provider.soilMoistureAlerts,
                onChanged: (v) => provider.updateNotificationSetting(
                  'soil_moisture_alerts',
                  v,
                ),
                saveStatus: provider.isSaving
                    ? SaveStatus.saving
                    : SaveStatus.idle,
              ),
              ToggleSettingTile(
                title: 'Weather Alerts',
                subtitle: 'Rain detection & irrigation skips',
                icon: Icons.cloudy_snowing,
                value: provider.weatherAlerts,
                onChanged: (v) =>
                    provider.updateNotificationSetting('weather_alerts', v),
                saveStatus: provider.isSaving
                    ? SaveStatus.saving
                    : SaveStatus.idle,
              ),
              ToggleSettingTile(
                title: 'Fertigation Reminders',
                subtitle: 'Nutrient injection scheduling',
                icon: Icons.science,
                value: provider.fertigationReminders,
                onChanged: (v) => provider.updateNotificationSetting(
                  'fertigation_reminders',
                  v,
                ),
                saveStatus: provider.isSaving
                    ? SaveStatus.saving
                    : SaveStatus.idle,
              ),
              ToggleSettingTile(
                title: 'Device Offline Alerts',
                subtitle: 'Network connectivity warnings',
                icon: Icons.wifi_off,
                value: provider.deviceOfflineAlerts,
                onChanged: (v) => provider.updateNotificationSetting(
                  'device_offline_alerts',
                  v,
                ),
                saveStatus: provider.isSaving
                    ? SaveStatus.saving
                    : SaveStatus.idle,
              ),
              ToggleSettingTile(
                title: 'Weekly Summary Report',
                subtitle: 'Email digest of water usage',
                icon: Icons.bar_chart,
                value: provider.weeklySummary,
                onChanged: (v) =>
                    provider.updateNotificationSetting('weekly_summary', v),
                saveStatus: provider.isSaving
                    ? SaveStatus.saving
                    : SaveStatus.idle,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
