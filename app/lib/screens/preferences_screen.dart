import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state_provider.dart';
import '../widgets/settings_section.dart';

class PreferencesScreen extends StatefulWidget {
  const PreferencesScreen({super.key});

  @override
  State<PreferencesScreen> createState() => _PreferencesScreenState();
}

class _PreferencesScreenState extends State<PreferencesScreen> {
  late TextEditingController _latController;
  late TextEditingController _lonController;
  bool _editingLocation = false;
  String? _latError;
  String? _lonError;

  @override
  void initState() {
    super.initState();
    _latController = TextEditingController();
    _lonController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<AppStateProvider>();
      _latController.text = provider.locationLat;
      _lonController.text = provider.locationLon;
    });
  }

  @override
  void dispose() {
    _latController.dispose();
    _lonController.dispose();
    super.dispose();
  }

  String? _validateCoord(String value, {required bool isLat}) {
    final parsed = double.tryParse(value);
    if (parsed == null) return 'Enter a valid number';
    if (isLat && (parsed < -90 || parsed > 90)) {
      return 'Latitude must be –90 to 90';
    }
    if (!isLat && (parsed < -180 || parsed > 180)) {
      return 'Longitude must be –180 to 180';
    }
    return null;
  }

  Future<void> _saveLocation() async {
    final latErr = _validateCoord(_latController.text.trim(), isLat: true);
    final lonErr = _validateCoord(_lonController.text.trim(), isLat: false);
    setState(() {
      _latError = latErr;
      _lonError = lonErr;
    });
    if (latErr != null || lonErr != null) return;

    final provider = context.read<AppStateProvider>();
    await provider.updateLocationLat(_latController.text.trim());
    await provider.updateLocationLon(_lonController.text.trim());

    if (mounted) {
      setState(() => _editingLocation = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Location saved.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _cancelLocation(AppStateProvider provider) {
    setState(() {
      _latController.text = provider.locationLat;
      _lonController.text = provider.locationLon;
      _latError = null;
      _lonError = null;
      _editingLocation = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppStateProvider>();
    final colors = Theme.of(context).colorScheme;
    final labelColor =
        Theme.of(context).textTheme.headlineMedium?.color ?? colors.onSurface;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 36),
      children: [
        SettingsSection(
          title: 'Units',
          leadingIcon: Icon(Icons.straighten, size: 20, color: labelColor),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Icon(Icons.thermostat, color: labelColor, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Temperature',
                    style: TextStyle(
                      color: labelColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            RadioGroup<String>(
              groupValue: provider.tempUnit,
              onChanged: (v) {
                if (!provider.isSaving && v != null) {
                  provider.updateTempUnit(v);
                }
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioListTile<String>(
                    title: const Text('Celsius (°C)'),
                    value: 'celsius',
                  ),
                  RadioListTile<String>(
                    title: const Text('Fahrenheit (°F)'),
                    value: 'fahrenheit',
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Icon(Icons.water_drop, color: labelColor, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Volume',
                    style: TextStyle(
                      color: labelColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            RadioGroup<String>(
              groupValue: provider.volumeUnit,
              onChanged: (v) {
                if (!provider.isSaving && v != null) {
                  provider.updateVolumeUnit(v);
                }
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioListTile<String>(
                    title: const Text('Litres (L)'),
                    value: 'litres',
                  ),
                  RadioListTile<String>(
                    title: const Text('Gallons (gal)'),
                    value: 'gallons',
                  ),
                ],
              ),
            ),
          ],
        ),

        SettingsSection(
          title: 'Wind Speed',
          leadingIcon: Icon(Icons.air_rounded, size: 20, color: labelColor),
          children: [
            RadioGroup<String>(
              groupValue: provider.windUnit,
              onChanged: (v) {
                if (!provider.isSaving && v != null) {
                  provider.updateWindUnit(v);
                }
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final option in const [
                    ('Kilometres per hour', 'km/h'),
                    ('Metres per second', 'm/s'),
                    ('Miles per hour', 'mph'),
                    ('Knots', 'kn'),
                  ])
                    RadioListTile<String>(
                      title: Text(option.$1),
                      subtitle: Text(
                        option.$2,
                        style: TextStyle(
                          color: colors.onSurface.withValues(alpha: 0.5),
                          fontSize: 12,
                        ),
                      ),
                      value: option.$2,
                    ),
                ],
              ),
            ),
          ],
        ),

        SettingsSection(
          title: 'Precipitation',
          leadingIcon: Icon(
            Icons.umbrella_rounded,
            size: 20,
            color: labelColor,
          ),
          children: [
            RadioGroup<String>(
              groupValue: provider.precipitationUnit,
              onChanged: (v) {
                if (!provider.isSaving && v != null) {
                  provider.updatePrecipitationUnit(v);
                }
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final option in const [
                    ('Millimetres', 'mm'),
                    ('Inches', 'inch'),
                  ])
                    RadioListTile<String>(
                      title: Text(option.$1),
                      subtitle: Text(
                        option.$2,
                        style: TextStyle(
                          color: colors.onSurface.withValues(alpha: 0.5),
                          fontSize: 12,
                        ),
                      ),
                      value: option.$2,
                    ),
                ],
              ),
            ),
          ],
        ),

        SettingsSection(
          title: 'Air Quality Index',
          leadingIcon: Icon(Icons.air_rounded, size: 20, color: labelColor),
          children: [
            RadioGroup<String>(
              groupValue: provider.aqiType,
              onChanged: (v) {
                if (!provider.isSaving && v != null) {
                  provider.updateAqiType(v);
                }
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final option in const [
                    ('US AQI', 'us', 'EPA standard, 0–500 scale'),
                    ('European AQI', 'eu', 'EEA standard, 0–100 scale'),
                  ])
                    RadioListTile<String>(
                      title: Text(option.$1),
                      subtitle: Text(
                        option.$3,
                        style: TextStyle(
                          color: colors.onSurface.withValues(alpha: 0.5),
                          fontSize: 12,
                        ),
                      ),
                      value: option.$2,
                    ),
                ],
              ),
            ),
          ],
        ),

        SettingsSection(
          title: 'Time',
          leadingIcon: Icon(
            Icons.schedule_rounded,
            size: 20,
            color: labelColor,
          ),
          children: [
            ListTile(
              leading: Icon(
                Icons.schedule_rounded,
                color: labelColor,
                size: 20,
              ),
              title: Text('Timezone', style: TextStyle(color: labelColor)),
              subtitle: Text(
                provider.timezone,
                style: TextStyle(color: labelColor),
              ),
            ),
          ],
        ),

        SettingsSection(
          title: 'Location',
          leadingIcon: Icon(Icons.place_rounded, size: 20, color: labelColor),
          children: [
            if (!_editingLocation) ...[
              ListTile(
                leading: Icon(Icons.place_rounded, color: labelColor, size: 20),
                title: Text('Coordinates', style: TextStyle(color: labelColor)),
                subtitle: Text(
                  '${provider.locationLat}, ${provider.locationLon}',
                  style: TextStyle(color: labelColor),
                ),
                trailing: IconButton(
                  icon: Icon(Icons.edit_rounded, size: 20, color: labelColor),
                  onPressed: () => setState(() => _editingLocation = true),
                ),
              ),
            ] else ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Column(
                  children: [
                    TextField(
                      controller: _latController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Latitude',
                        hintText: 'e.g. 19.0760',
                        errorText: _latError,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _lonController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Longitude',
                        hintText: 'e.g. 72.8777',
                        errorText: _lonError,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: provider.isSaving
                              ? null
                              : () => _cancelLocation(provider),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: provider.isSaving ? null : _saveLocation,
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
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
