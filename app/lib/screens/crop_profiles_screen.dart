// lib/screens/crop_profiles_screen.dart
//
// GlobalKey-free design:
//   • _ProfileSheet uses NO Form / GlobalKey.
//   • Validation is done inline in _save() by inspecting controller text.
//   • This prevents "multiple widgets used the same GlobalKey" crashes that
//     occur when the sheet is opened more than once per session.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart' show AppConfig;
import '../theme.dart';
import '../utils/date_helpers.dart';
import '../providers/app_state_provider.dart';
import '../widgets/double_back_press_wrapper.dart';

// ── Data model ────────────────────────────────────────────────────────────────
class _Profile {
  final int id;
  final String name;
  final String plantName;
  final double minMoisture;
  final int pwmDuty;
  final DateTime? perenualCachedAt;
  final Map<String, dynamic>? perenualData;

  const _Profile({
    required this.id,
    required this.name,
    required this.plantName,
    required this.minMoisture,
    this.pwmDuty = 200,
    this.perenualCachedAt,
    this.perenualData,
  });

  factory _Profile.fromMap(Map<String, dynamic> m) => _Profile(
    id: m['id'] as int,
    name: (m['name'] as String?) ?? 'Unnamed Profile',
    plantName: (m['plant_name'] as String?) ?? '',
    minMoisture: (m['min_moisture'] as num?)?.toDouble() ?? 30.0,
    pwmDuty: (m['pwm_duty'] as num?)?.toInt() ?? 200,
    perenualCachedAt: m['perenual_cached_at'] != null
        ? DateTime.parse(m['perenual_cached_at'] as String).toLocal()
        : null,
    perenualData: m['perenual_data'] as Map<String, dynamic>?,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────
class CropProfilesScreen extends StatefulWidget {
  const CropProfilesScreen({super.key});

  @override
  State<CropProfilesScreen> createState() => _CropProfilesScreenState();
}

class _CropProfilesScreenState extends State<CropProfilesScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  List<_Profile> _profiles = [];
  int? _activeId;
  bool _loading = true;
  final Set<int> _fetchingIds = {};

  // ── Load ──────────────────────────────────────────────────────────────────
  Future<void> _load() async {
    setState(() => _loading = true);
    final deviceId = context.read<AppStateProvider>().deviceId;
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      setState(() => _loading = false);
      return;
    }

    try {
      final rows =
          await Supabase.instance.client
                  .from('crop_profiles')
                  .select(
                    'id, name, plant_name, min_moisture, pwm_duty, perenual_cached_at, perenual_data',
                  )
                  .eq('user_id', userId)
                  .order('id', ascending: true)
              as List<dynamic>;

      int? activeId;
      if (deviceId != null) {
        final dev = await Supabase.instance.client
            .from('devices')
            .select('crop_profile_id')
            .eq('id', deviceId)
            .maybeSingle();
        activeId = dev?['crop_profile_id'] as int?;
      }

      if (mounted) {
        setState(() {
          _profiles = rows
              .map((r) => _Profile.fromMap(r as Map<String, dynamic>))
              .toList();
          _activeId = activeId;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Could not load profiles: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  // ── Set active ───────────────────────────────────────────────────────────
  Future<void> _setActive(int profileId) async {
    final deviceId = context.read<AppStateProvider>().deviceId;
    if (deviceId == null) return;
    await Supabase.instance.client
        .from('devices')
        .update({'crop_profile_id': profileId})
        .eq('id', deviceId);
    if (!mounted) return;
    setState(() => _activeId = profileId);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(_snackBar('Active profile updated.'));
  }

  // ── Delete ───────────────────────────────────────────────────────────────
  Future<void> _delete(_Profile profile) async {
    final provider = context.read<AppStateProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Profile'),
        content: Text('Delete "${profile.name}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'Delete',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await Supabase.instance.client
        .from('crop_profiles')
        .delete()
        .eq('id', profile.id);

    if (_activeId == profile.id) {
      final deviceId = provider.deviceId;
      if (deviceId != null) {
        await Supabase.instance.client
            .from('devices')
            .update({'crop_profile_id': null})
            .eq('id', deviceId);
      }
    }
    await _load();
  }

  // ── Open sheet (create or edit) ──────────────────────────────────────────
  // Each call pushes a fresh widget instance onto the sheet stack.
  // Because _ProfileSheet holds no GlobalKey, multiple opens are safe.
  void _openSheet({_Profile? profile}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      // useSafeArea keeps the sheet above the system navigation bar.
      useSafeArea: true,
      builder: (_) => _ProfileSheet(existing: profile, onSaved: _load),
    );
  }

  // ── Perenual fetch ───────────────────────────────────────────────────────
  Future<void> _fetchData(_Profile profile) async {
    if (_fetchingIds.contains(profile.id)) return;
    if (profile.plantName.isEmpty) return;
    setState(() => _fetchingIds.add(profile.id));

    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) throw Exception('User not logged in');

      // Use direct HTTP to bypass SDK token handling issues
      final accessToken = session.accessToken;

      debugPrint('=== HTTP Call Debug ===');
      debugPrint('URL: ${AppConfig.supabaseUrl}/functions/v1/perenual-lookup');
      debugPrint('Token: $accessToken');
      debugPrint('Token length: ${accessToken.length}');
      debugPrint('======================');

      final response = await http.post(
        Uri.parse('${AppConfig.supabaseUrl}/functions/v1/perenual-lookup'),
        headers: {
          'Content-Type': 'application/json',
          'apikey': accessToken, // Also pass as apikey
          'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode({
          'profile_id': profile.id,
          'plant_name': profile.plantName,
        }),
      );

      debugPrint('Response status: ${response.statusCode}');
      debugPrint('Response body: ${response.body}');

      if (response.statusCode != 200) {
        throw Exception(
          'Edge function error: ${response.statusCode} - ${response.body}',
        );
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (body['ok'] != true) {
        throw Exception(body['error'] ?? 'Unknown error from Perenual lookup');
      }

      await _load();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          _snackBar(
            body['source'] == 'cache'
                ? 'Plant data loaded from cache.'
                : 'Plant data fetched successfully.',
          ),
        );
      }
    } catch (e) {
      debugPrint('[Perenual] fetch error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to fetch plant data: $e'),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(20),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _fetchingIds.remove(profile.id));
    }
  }

  SnackBar _snackBar(String message) => SnackBar(
    content: Text(message),
    behavior: SnackBarBehavior.floating,
    margin: const EdgeInsets.all(20),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
  );

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colors = Theme.of(context).colorScheme;
    final appColors = Theme.of(context).extension<AppColors>()!;

    return DoubleBackPressWrapper(
      child: Scaffold(
        backgroundColor: colors.surfaceContainerHighest,
        floatingActionButton: FloatingActionButton(
          onPressed: () => _openSheet(),
          tooltip: 'Add Profile',
          child: Icon(Icons.add),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  children: [
                    if (_profiles.isEmpty)
                      _EmptyState(onAdd: () => _openSheet())
                    else
                      ...List.generate(_profiles.length, (i) {
                        final p = _profiles[i];
                        final isActive = p.id == _activeId;
                        return _ProfileCard(
                          profile: p,
                          isActive: isActive,
                          colors: colors,
                          appColors: appColors,
                          onSetActive: isActive ? null : () => _setActive(p.id),
                          onEdit: () => _openSheet(profile: p),
                          onDelete: () => _delete(p),
                          onFetchData: p.plantName.isNotEmpty
                              ? () => _fetchData(p)
                              : null,
                          isFetching: _fetchingIds.contains(p.id),
                        );
                      }),
                  ],
                ),
              ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Profile card
// ─────────────────────────────────────────────────────────────────────────────
class _ProfileCard extends StatelessWidget {
  final _Profile profile;
  final bool isActive;
  final ColorScheme colors;
  final AppColors appColors;
  final VoidCallback? onSetActive;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onFetchData;
  final bool isFetching;

  const _ProfileCard({
    required this.profile,
    required this.isActive,
    required this.colors,
    required this.appColors,
    required this.onSetActive,
    required this.onEdit,
    required this.onDelete,
    this.onFetchData,
    this.isFetching = false,
  });

  @override
  Widget build(BuildContext context) {
    final cached = profile.perenualCachedAt;
    final plantData = profile.perenualData;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isActive ? AppTheme.teal : AppTheme.softMint,
          width: isActive ? 2 : 0.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(Icons.eco, color: appColors.successGreen, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    profile.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (isActive)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.teal,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'ACTIVE',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                const SizedBox(width: 4),
                IconButton(
                  onPressed: onEdit,
                  icon: Icon(Icons.edit, size: 18),
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Edit',
                ),
                IconButton(
                  onPressed: onDelete,
                  icon: Icon(Icons.delete, size: 18, color: colors.error),
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Delete',
                ),
              ],
            ),

            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 10),

            // Plant name + threshold
            Row(
              children: [
                Expanded(
                  child: _DetailChip(
                    icon: Icons.grass,
                    label: profile.plantName.isNotEmpty
                        ? profile.plantName
                        : 'No plant set',
                    faded: profile.plantName.isEmpty,
                  ),
                ),
                const SizedBox(width: 8),
                _DetailChip(
                  icon: Icons.water_drop,
                  label: '${profile.minMoisture.round()}% threshold',
                ),
              ],
            ),

            // Perenual section
            if (profile.plantName.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: cached != null
                        ? _DetailChip(
                            icon: Icons.check_circle,
                            label:
                                'Cached · ${DateHelpers.timeAgoLong(cached).toLowerCase()}',
                            color: AppTheme.teal,
                          )
                        : _DetailChip(
                            icon: Icons.warning,
                            label: 'No plant data yet',
                            color: const Color(0xFFB45309),
                          ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 32,
                    child: isFetching
                        ? const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : OutlinedButton.icon(
                            onPressed: onFetchData,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.teal,
                              side: const BorderSide(color: AppTheme.teal),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              textStyle: const TextStyle(fontSize: 12),
                            ),
                            icon: Icon(
                              cached != null
                                  ? Icons.refresh
                                  : Icons.open_in_new,
                              size: 14,
                            ),
                            label: Text(
                              cached != null ? 'Refresh' : 'Fetch Data',
                            ),
                          ),
                  ),
                ],
              ),
              if (plantData != null) ...[
                const SizedBox(height: 10),
                _PlantDataPanel(data: plantData, colors: colors),
              ],
            ],

            // Set active button
            if (onSetActive != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onSetActive,
                  icon: Icon(Icons.check, size: 16),
                  label: const Text('Set as Active'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.teal,
                    side: const BorderSide(color: AppTheme.teal),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Plant data panel
// ─────────────────────────────────────────────────────────────────────────────
class _PlantDataPanel extends StatelessWidget {
  final Map<String, dynamic> data;
  final ColorScheme colors;

  const _PlantDataPanel({required this.data, required this.colors});

  @override
  Widget build(BuildContext context) {
    final scientificName = data['scientific_name'] as String?;
    final watering = data['watering'] as String?;
    final sunlightRaw = data['sunlight'];
    final cycle = data['cycle'] as String?;
    final description = data['description'] as String?;

    String? sunlight;
    if (sunlightRaw is List && sunlightRaw.isNotEmpty) {
      sunlight = sunlightRaw.map((e) => e.toString()).join(', ');
    } else if (sunlightRaw is String) {
      sunlight = sunlightRaw;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.teal.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.teal.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.eco, size: 14, color: AppTheme.teal),
              const SizedBox(width: 6),
              const Text(
                'Plant Info',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.teal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (scientificName != null && scientificName.isNotEmpty)
            _InfoRow(
              icon: Icons.menu_book,
              label: 'Scientific name',
              value: scientificName,
            ),
          if (watering != null && watering.isNotEmpty)
            _InfoRow(
              icon: Icons.water_drop,
              label: 'Watering',
              value: watering,
            ),
          if (sunlight != null && sunlight.isNotEmpty)
            _InfoRow(icon: Icons.wb_sunny, label: 'Sunlight', value: sunlight),
          if (cycle != null && cycle.isNotEmpty)
            _InfoRow(icon: Icons.refresh, label: 'Cycle', value: cycle),
          if (description != null && description.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: colors.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 13, color: AppTheme.teal),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: AppTheme.pine,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.75),
            ),
          ),
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Detail chip
// ─────────────────────────────────────────────────────────────────────────────
class _DetailChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool faded;
  final Color? color;
  const _DetailChip({
    required this.icon,
    required this.label,
    this.faded = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final resolved =
        color ??
        (faded ? AppTheme.pine.withValues(alpha: 0.35) : AppTheme.pine);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: resolved),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: resolved),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty state
// ─────────────────────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Column(
          children: [
            Icon(
              Icons.eco,
              size: 56,
              color: AppTheme.teal.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'No profiles yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'Tap the + button to create your first crop profile.',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onAdd,
              icon: Icon(Icons.add),
              label: const Text('Add Profile'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bottom sheet — GlobalKey-free
//
// Why no GlobalKey here:
//   Form + GlobalKey<FormState> causes "multiple widgets used the same
//   GlobalKey" errors when the sheet is opened, dismissed, and reopened
//   because Flutter can reuse the old State before GC collects it.
//
//   Fix: validate directly against TextEditingController.text in _save().
//   An error string (_nameError) drives the inline error display, replacing
//   the Form validator entirely.
// ─────────────────────────────────────────────────────────────────────────────
class _ProfileSheet extends StatefulWidget {
  final _Profile? existing;
  final VoidCallback onSaved;

  const _ProfileSheet({this.existing, required this.onSaved});

  @override
  State<_ProfileSheet> createState() => _ProfileSheetState();
}

class _ProfileSheetState extends State<_ProfileSheet> {
  // No GlobalKey — controllers are enough.
  final _nameController = TextEditingController();
  final _plantController = TextEditingController();

  double _threshold = 30.0;
  bool _saving = false;

  // Inline validation state — replaces Form validator.
  String? _nameError;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit && widget.existing != null) {
      _nameController.text = widget.existing!.name;
      _plantController.text = widget.existing!.plantName;
      _threshold = widget.existing!.minMoisture;
    }
    // Clear the name error as soon as the user types.
    _nameController.addListener(() {
      if (_nameError != null && _nameController.text.trim().isNotEmpty) {
        setState(() => _nameError = null);
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _plantController.dispose();
    super.dispose();
  }

  // ── Inline validation — no GlobalKey needed ───────────────────────────────
  bool _validate() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'Please enter a profile name');
      return false;
    }
    setState(() => _nameError = null);
    return true;
  }

  Future<void> _save() async {
    if (!_validate()) return;
    setState(() => _saving = true);

    final userId = Supabase.instance.client.auth.currentUser?.id;
    final name = _nameController.text.trim();
    final plantName = _plantController.text.trim();

    try {
      if (_isEdit) {
        final plantChanged = plantName != widget.existing!.plantName;
        await Supabase.instance.client
            .from('crop_profiles')
            .update({
              'name': name,
              'plant_name': plantName.isNotEmpty ? plantName : null,
              'min_moisture': _threshold,
              if (plantChanged) 'perenual_data': null,
              if (plantChanged) 'perenual_species_id': null,
              if (plantChanged) 'perenual_cached_at': null,
            })
            .eq('id', widget.existing!.id);
      } else {
        await Supabase.instance.client.from('crop_profiles').insert({
          'user_id': userId,
          'name': name,
          'plant_name': plantName.isNotEmpty ? plantName : null,
          'min_moisture': _threshold,
        });
      }

      if (mounted) {
        Navigator.of(context).pop();
        widget.onSaved();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEdit ? 'Profile updated.' : 'Profile created.'),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(20),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(20),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final appColors = Theme.of(context).extension<AppColors>()!;
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 24, 16, 24 + bottomPad),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title
            Row(
              children: [
                Icon(Icons.eco, color: appColors.successGreen),
                const SizedBox(width: 8),
                Text(
                  _isEdit ? 'Edit Profile' : 'New Profile',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Profile name — error driven by _nameError, not Form validator
            TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'Profile Name',
                hintText: 'e.g. Summer Tomato',
                errorText: _nameError,
              ),
            ),
            const SizedBox(height: 16),

            // Plant name
            TextField(
              controller: _plantController,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'Plant Name',
                hintText: 'e.g. Tomato, Wheat, Basil',
                helperText: 'Used to fetch nutrient & care data from Perenual.',
                prefixIcon: Icon(Icons.grass, color: colors.primary),
              ),
            ),
            const SizedBox(height: 24),

            // Threshold slider
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.water_drop, color: colors.primary),
                        const SizedBox(width: 8),
                        Text(
                          'Dry Threshold (%)',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Pump turns on when moisture drops below this.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                    Slider(
                      value: _threshold,
                      min: 0,
                      max: 100,
                      divisions: 20,
                      label: '${_threshold.round()}%',
                      onChanged: (v) => setState(() => _threshold = v),
                    ),
                    Center(
                      child: Text(
                        '${_threshold.round()}%',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Save
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Icon(Icons.save),
                label: Text(
                  _saving
                      ? 'Saving…'
                      : (_isEdit ? 'Save Changes' : 'Create Profile'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
