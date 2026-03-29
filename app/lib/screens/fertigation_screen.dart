import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/app_state_provider.dart';
import '../widgets/settings_section.dart';
import '../utils/date_helpers.dart';
import '../widgets/double_back_press_wrapper.dart';

class FertigationScreen extends StatefulWidget {
  const FertigationScreen({super.key});

  @override
  State<FertigationScreen> createState() => _FertigationScreenState();
}

class _FertigationScreenState extends State<FertigationScreen> {
  bool _loading = true;
  bool _fetching = false;
  bool _logging = false;
  String? _error;

  // Active profile data
  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _plantData;
  Map<String, dynamic>? _careData;

  // Fertigation log
  List<Map<String, dynamic>> _logs = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  // ── Load active profile + logs ────────────────────────────────────────────
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final provider = context.read<AppStateProvider>();
      final deviceId = provider.deviceId;

      if (deviceId == null) {
        setState(() {
          _loading = false;
        });
        return;
      }

      // Get active crop_profile_id from device
      final device = await Supabase.instance.client
          .from('devices')
          .select('crop_profile_id')
          .eq('id', deviceId)
          .maybeSingle();

      final profileId = device?['crop_profile_id'];

      if (profileId == null) {
        setState(() {
          _loading = false;
        });
        return;
      }

      // Fetch profile with Perenual data
      final profile = await Supabase.instance.client
          .from('crop_profiles')
          .select(
            'id, name, plant_name, min_moisture, '
            'perenual_data, perenual_care_data, perenual_cached_at',
          )
          .eq('id', profileId as int)
          .maybeSingle();

      // Fetch fertigation logs for this device
      final logs =
          await Supabase.instance.client
                  .from('fertigation_logs')
                  .select('id, fertilized_at, notes')
                  .eq('device_id', deviceId)
                  .order('fertilized_at', ascending: false)
                  .limit(20)
              as List<dynamic>;

      if (mounted) {
        setState(() {
          _profile = profile;
          _plantData = profile?['perenual_data'] != null
              ? Map<String, dynamic>.from(profile!['perenual_data'] as Map)
              : null;
          _careData = profile?['perenual_care_data'] != null
              ? Map<String, dynamic>.from(profile!['perenual_care_data'] as Map)
              : null;
          _logs = logs.map((r) => Map<String, dynamic>.from(r as Map)).toList();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  // ── Fetch Perenual data via Edge Function ─────────────────────────────────
  Future<void> _fetchPlantData() async {
    final profileId = _profile?['id'] as int?;
    final plantName = (_profile?['plant_name'] as String?) ?? '';

    if (profileId == null || plantName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Set a plant name in Crop Profiles first.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _fetching = true);

    try {
      final response = await Supabase.instance.client.functions.invoke(
        'perenual-lookup',
        body: {'profile_id': profileId, 'plant_name': plantName},
      );

      final data = response.data as Map<String, dynamic>?;
      if (data?['ok'] == true) {
        await _load();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Plant care data updated.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        throw Exception(data?['error'] ?? 'Unknown error');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to fetch: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
  }

  // ── Log fertilizer application ────────────────────────────────────────────
  Future<void> _logApplication() async {
    final provider = context.read<AppStateProvider>();
    final notesController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log Fertilizer Application'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Record a fertilizer application for today.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: notesController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                hintText: 'e.g. Used NPK 10-10-10',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Log'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    setState(() => _logging = true);

    try {
      final deviceId = provider.deviceId;
      final profileId = _profile?['id'] as int?;

      await Supabase.instance.client.from('fertigation_logs').insert({
        'device_id': deviceId,
        'crop_profile_id': profileId,
        'fertilized_at': DateTime.now().toIso8601String(),
        'notes': notesController.text.trim().isNotEmpty
            ? notesController.text.trim()
            : null,
      });

      await _load();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Fertilizer application logged.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to log: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _logging = false);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  // ── Time helper removed natively (using DateHelpers) ──────────────────────────

  int _daysSinceLast() {
    if (_logs.isEmpty) return -1;
    final last = DateTime.parse(
      _logs.first['fertilized_at'] as String,
    ).toLocal();
    return DateTime.now().difference(last).inDays;
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final labelColor =
        Theme.of(context).textTheme.headlineMedium?.color ?? colors.onSurface;

    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, color: colors.error, size: 40),
            const SizedBox(height: 8),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_profile == null) {
      return _NoProfileState(colors: colors);
    }

    final plantName = (_profile!['plant_name'] as String?) ?? '';
    final profileName = (_profile!['name'] as String?) ?? 'Unknown';
    final daysSince = _daysSinceLast();
    final fertDesc =
        (_careData?['fertilizer'] as Map<String, dynamic>?)?['description']
            as String?;
    final waterDesc =
        (_careData?['watering'] as Map<String, dynamic>?)?['description']
            as String?;
    final hasCareData = _careData != null && fertDesc != null;
    final imageUrl = _plantData?['image_url'] as String?;

    return DoubleBackPressWrapper(
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 36),
          children: [
            // ── Plant hero ──────────────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.08),
                border: Border(
                  bottom: BorderSide(
                    color: colors.outline.withValues(alpha: 0.2),
                  ),
                ),
              ),
              child: Row(
                children: [
                  // Plant image or placeholder
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: imageUrl != null
                        ? Image.network(
                            imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Icon(
                              Icons.local_florist_rounded,
                              size: 36,
                              color: colors.primary,
                            ),
                          )
                        : Icon(
                            Icons.local_florist_rounded,
                            size: 36,
                            color: colors.primary,
                          ),
                  ),
                  const SizedBox(width: 16),

                  // Profile info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          plantName.isNotEmpty ? plantName : profileName,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: colors.onSurface,
                          ),
                        ),
                        if (plantName.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            profileName,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12,
                              color: colors.onSurface.withValues(alpha: 0.5),
                            ),
                          ),
                        ],
                        if (_plantData?['scientific_name'] != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            _plantData!['scientific_name'] as String,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                              color: colors.onSurface.withValues(alpha: 0.5),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Refresh button
                  IconButton(
                    icon: _fetching
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colors.primary,
                            ),
                          )
                        : Icon(Icons.refresh_rounded, color: colors.primary),
                    tooltip: 'Refresh plant data',
                    onPressed: _fetching ? null : _fetchPlantData,
                  ),
                ],
              ),
            ),

            // ── Days since last application ─────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: _StatBox(
                      icon: Icons.event_rounded,
                      label: 'Last Applied',
                      value: daysSince < 0
                          ? 'Never'
                          : daysSince == 0
                          ? 'Today'
                          : '$daysSince days ago',
                      color: daysSince < 0
                          ? colors.error
                          : daysSince <= 7
                          ? const Color(0xFF2D9D5C)
                          : const Color(0xFFF59E0B),
                      colors: colors,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatBox(
                      icon: Icons.format_list_numbered_rounded,
                      label: 'Total Applications',
                      value: '${_logs.length}',
                      color: colors.primary,
                      colors: colors,
                    ),
                  ),
                ],
              ),
            ),

            // ── Log button ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: FilledButton.icon(
                onPressed: _logging ? null : _logApplication,
                icon: _logging
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(Icons.science_rounded),
                label: Text(
                  _logging ? 'Logging…' : 'Log Fertilizer Application',
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 48),
                ),
              ),
            ),

            // ── No care data prompt ─────────────────────────────────────────
            if (!hasCareData && plantName.isNotEmpty) ...[
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: colors.secondaryContainer,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: colors.onSecondaryContainer.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        color: colors.onSecondaryContainer,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Tap the refresh button above to fetch '
                          'fertilization recommendations for $plantName.',
                          style: TextStyle(
                            color: colors.onSecondaryContainer,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            // ── Fertilizer guide ────────────────────────────────────────────
            if (hasCareData) ...[
              const SizedBox(height: 8),
              SettingsSection(
                title: 'Fertilization Guide',
                leadingIcon: Icon(
                  Icons.science_rounded,
                  size: 20,
                  color: labelColor,
                ),
                children: [
                  _CareSection(
                    icon: Icons.science_rounded,
                    title: 'Fertilizer',
                    description: fertDesc,
                    color: const Color(0xFF7C3AED),
                    colors: colors,
                  ),
                  if (waterDesc != null) ...[
                    const Divider(height: 1),
                    _CareSection(
                      icon: Icons.water_drop_rounded,
                      title: 'Watering',
                      description: waterDesc,
                      color: const Color(0xFF2196F3),
                      colors: colors,
                    ),
                  ],
                ],
              ),
            ],

            // ── General plant info ──────────────────────────────────────────
            if (_plantData != null) ...[
              SettingsSection(
                title: 'Plant Info',
                leadingIcon: Icon(
                  Icons.local_florist_rounded,
                  size: 20,
                  color: labelColor,
                ),
                children: [
                  if (_plantData!['watering'] != null)
                    _InfoRow(
                      icon: Icons.water_drop_rounded,
                      label: 'Watering Needs',
                      value: _plantData!['watering'] as String,
                      colors: colors,
                    ),
                  if (_plantData!['cycle'] != null) ...[
                    const Divider(height: 1),
                    _InfoRow(
                      icon: Icons.autorenew_rounded,
                      label: 'Growth Cycle',
                      value: _plantData!['cycle'] as String,
                      colors: colors,
                    ),
                  ],
                  if (_plantData!['sunlight'] != null) ...[
                    const Divider(height: 1),
                    _InfoRow(
                      icon: Icons.wb_sunny_rounded,
                      label: 'Sunlight',
                      value: _plantData!['sunlight'] is List
                          ? (_plantData!['sunlight'] as List<dynamic>).join(
                              ', ',
                            )
                          : _plantData!['sunlight'] as String,
                      colors: colors,
                    ),
                  ],
                  if (_plantData!['description'] != null) ...[
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        _plantData!['description'] as String,
                        style: TextStyle(
                          fontSize: 13,
                          color: colors.onSurface.withValues(alpha: 0.7),
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],

            // ── Application history ─────────────────────────────────────────
            SettingsSection(
              title: 'Application History',
              leadingIcon: Icon(
                Icons.history_rounded,
                size: 20,
                color: labelColor,
              ),
              children: _logs.isEmpty
                  ? [
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Center(
                          child: Text(
                            'No applications logged yet.',
                            style: TextStyle(
                              color: colors.onSurface.withValues(alpha: 0.4),
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ]
                  : [
                      for (int i = 0; i < _logs.length; i++) ...[
                        _LogRow(
                          log: _logs[i],
                          timeAgo: DateHelpers.timeAgoLong(
                            DateTime.parse(
                              _logs[i]['fertilized_at'] as String,
                            ).toLocal(),
                          ),
                          colors: colors,
                        ),
                        if (i < _logs.length - 1)
                          const Divider(height: 1, indent: 56),
                      ],
                    ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// No profile state
// ─────────────────────────────────────────────────────────────────────────────
class _NoProfileState extends StatelessWidget {
  final ColorScheme colors;
  const _NoProfileState({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.local_florist_rounded,
              size: 64,
              color: colors.primary.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              'No Active Crop Profile',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: colors.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Go to Crop Profiles, create a profile with a '
              'plant name, and set it as Active.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: colors.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stat box
// ─────────────────────────────────────────────────────────────────────────────
class _StatBox extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final ColorScheme colors;

  const _StatBox({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: colors.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Care section tile
// ─────────────────────────────────────────────────────────────────────────────
class _CareSection extends StatefulWidget {
  final IconData icon;
  final String title;
  final String description;
  final Color color;
  final ColorScheme colors;

  const _CareSection({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
    required this.colors,
  });

  @override
  State<_CareSection> createState() => _CareSectionState();
}

class _CareSectionState extends State<_CareSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          leading: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: widget.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(widget.icon, color: widget.color, size: 18),
          ),
          title: Text(
            widget.title,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          trailing: Icon(
            _expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
            color: widget.colors.onSurface.withValues(alpha: 0.4),
          ),
          onTap: () => setState(() => _expanded = !_expanded),
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(68, 0, 16, 16),
            child: Text(
              widget.description,
              style: TextStyle(
                fontSize: 13,
                color: widget.colors.onSurface.withValues(alpha: 0.7),
                height: 1.6,
              ),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Info row
// ─────────────────────────────────────────────────────────────────────────────
class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final ColorScheme colors;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, size: 20, color: colors.primary),
      title: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          color: colors.onSurface.withValues(alpha: 0.55),
        ),
      ),
      trailing: SizedBox(
        width: 160,
        child: Text(
          value,
          textAlign: TextAlign.right,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: colors.onSurface,
          ),
          overflow: TextOverflow.ellipsis,
          maxLines: 2,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Log row
// ─────────────────────────────────────────────────────────────────────────────
class _LogRow extends StatelessWidget {
  final Map<String, dynamic> log;
  final String timeAgo;
  final ColorScheme colors;

  const _LogRow({
    required this.log,
    required this.timeAgo,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final notes = log['notes'] as String?;
    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: const Color(0xFF7C3AED).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(
          Icons.science_outlined,
          color: Color(0xFF7C3AED),
          size: 18,
        ),
      ),
      title: Text(
        timeAgo,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
      subtitle: notes != null && notes.isNotEmpty
          ? Text(
              notes,
              style: TextStyle(
                fontSize: 12,
                color: colors.onSurface.withValues(alpha: 0.55),
              ),
            )
          : null,
    );
  }
}
