import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/app_state_provider.dart';
import '../widgets/settings_section.dart';
import '../utils/date_helpers.dart';
import '../widgets/device_health_tile.dart';

class DeviceManagementScreen extends StatefulWidget {
  const DeviceManagementScreen({super.key});

  @override
  State<DeviceManagementScreen> createState() => _DeviceManagementScreenState();
}

class _DeviceManagementScreenState extends State<DeviceManagementScreen> {
  bool _editingName    = false;
  bool _savingName     = false;
  bool _unlinking      = false;
  String? _nameError;
  late TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _nameController.text = context.read<AppStateProvider>().deviceName ?? '';
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _saveName() async {
    final value = _nameController.text.trim();
    if (value.isEmpty) {
      setState(() => _nameError = 'Device name cannot be empty');
      return;
    }
    setState(() { _savingName = true; _nameError = null; });

    final provider = context.read<AppStateProvider>();
    try {
      final deviceId = provider.deviceId;
      if (deviceId == null) return;
      await Supabase.instance.client
          .from('devices')
          .update({'name': value})
          .eq('id', deviceId);

      await provider.checkDeviceStatus();

      if (mounted) {
        setState(() { _editingName = false; _savingName = false; });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:  Text('Device name updated.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _savingName = false;
          _nameError  = 'Failed to update name.';
        });
      }
    }
  }

  void _cancelName(String original) {
    setState(() {
      _nameController.text = original;
      _nameError           = null;
      _editingName         = false;
    });
  }

  Future<void> _unlinkDevice() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title:   const Text('Unlink Device'),
        content: const Text(
          'This removes your account from this device.\n'
          'You will need to re-enter the UUID to reclaim it.\n\n'
          'All historical data is preserved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Unlink'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    setState(() => _unlinking = true);

    if (!mounted) return;
    final provider = context.read<AppStateProvider>();

    try {
      final deviceId = provider.deviceId;
      if (deviceId == null) return;
      await Supabase.instance.client
          .from('devices')
          .update({'user_id': null, 'claimed_at': null})
          .eq('id', deviceId);

      await provider.refresh();
    } catch (e) {
      if (mounted) {
        setState(() => _unlinking = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:  Text('Failed to unlink: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider   = context.watch<AppStateProvider>();
    final colors     = Theme.of(context).colorScheme;
    final labelColor =
        Theme.of(context).textTheme.headlineMedium?.color ?? colors.onSurface;
    final deviceName = provider.deviceName ?? 'Unknown Device';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 36),
      children: [

        Container(
          width:   double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 36),
          decoration: BoxDecoration(
            color: colors.primary.withValues(alpha: 0.08),
            border: Border(
              bottom: BorderSide(
                color: colors.outline.withValues(alpha: 0.2),
              ),
            ),
          ),
          child: Column(
            children: [
              Container(
                width:  72,
                height: 72,
                decoration: BoxDecoration(
                  color:        provider.isDeviceOnline
                      ? colors.primary
                      : colors.onSurface.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color:        (provider.isDeviceOnline
                              ? colors.primary
                              : colors.onSurface)
                          .withValues(alpha: 0.25),
                      blurRadius:   16,
                      spreadRadius: 1,
                      offset:       const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.memory_rounded,
                  size:  36,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                deviceName,
                style: TextStyle(
                  fontFamily:  'Poppins',
                  fontSize:    20,
                  fontWeight:  FontWeight.bold,
                  color:       colors.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 4),
                decoration: BoxDecoration(
                  color:        (provider.isDeviceOnline
                          ? colors.primary
                          : colors.error)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width:  8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: provider.isDeviceOnline
                            ? colors.primary
                            : colors.error,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      provider.isDeviceOnline ? 'Online' : 'Offline',
                      style: TextStyle(
                        fontFamily:  'Poppins',
                        fontSize:    12,
                        fontWeight:  FontWeight.w600,
                        color:       provider.isDeviceOnline
                            ? colors.primary
                            : colors.error,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        SettingsSection(
          title:       'Device Info',
          leadingIcon: Icon(Icons.storage_rounded,
              size: 20, color: labelColor),
          children: [
            if (!_editingName)
              ListTile(
                leading: Icon(Icons.sell_rounded,
                    color: labelColor, size: 20),
                title: Text('Name',
                    style: TextStyle(color: labelColor)),
                subtitle: Text(deviceName,
                    style: TextStyle(color: labelColor)),
                trailing: IconButton(
                  icon: Icon(Icons.edit_rounded,
                      size: 20, color: labelColor),
                  onPressed: () => setState(() => _editingName = true),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Column(
                  children: [
                    TextField(
                      controller:  _nameController,
                      autofocus:   true,
                      decoration: InputDecoration(
                        labelText: 'Device Name',
                        errorText: _nameError,
                        border:    const OutlineInputBorder(),
                        isDense:   true,
                      ),
                      onSubmitted: (_) => _saveName(),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: _savingName
                              ? null
                              : () => _cancelName(deviceName),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: _savingName ? null : _saveName,
                          icon: _savingName
                              ? SizedBox(
                                  width: 16, height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color:       colors.onPrimary,
                                  ),
                                )
                              : const Icon(Icons.check, size: 18),
                          label: Text(
                              _savingName ? 'Saving…' : 'Save'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                  ],
                ),
              ),

            const Divider(height: 1),

            ListTile(
              leading: Icon(Icons.schedule_rounded,
                  color: labelColor, size: 20),
              title: Text('Last Seen',
                  style: TextStyle(color: labelColor)),
              subtitle: Text(
                provider.deviceLastSeen != null
                    ? DateHelpers.timeAgoShort(provider.deviceLastSeen!)
                    : 'Unknown',
                style: TextStyle(color: labelColor),
              ),
              trailing: IconButton(
                icon: Icon(Icons.refresh_rounded,
                    size: 20, color: labelColor),
                tooltip:  'Refresh',
                onPressed: () => provider.refreshDeviceStatus(),
              ),
            ),

            const Divider(height: 1),

            ListTile(
              leading: Icon(Icons.fingerprint_rounded,
                  color: labelColor, size: 20),
              title: Text('Device ID',
                  style: TextStyle(color: labelColor)),
              subtitle: Text(
                provider.deviceId ?? 'Not linked',
                style: TextStyle(
                  color:    labelColor,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        ),

        SettingsSection(
          title:       'Connectivity',
          leadingIcon: Icon(Icons.wifi_rounded,
              size: 20, color: labelColor),
          children: [
            ApiConnectivityTile(
              serviceName: 'Supabase',
              isConnected: provider.isApiConnected,
            ),
            const Divider(height: 1),
            const ApiConnectivityTile(
              serviceName: 'Open-Meteo',
              isConnected: true,
            ),
          ],
        ),

        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Danger Zone',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color:      colors.error,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _unlinking ? null : _unlinkDevice,
              style: OutlinedButton.styleFrom(
                foregroundColor: colors.error,
                side:            BorderSide(color: colors.error),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              icon: _unlinking
                  ? SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color:       colors.error,
                      ),
                    )
                  : Icon(Icons.link_off_rounded),
              label: const Text('Unlink Device'),
            ),
          ),
        ),
      ],
    );
  }

// ── Time helper removed natively (using DateHelpers) ──────────────────────────
}
