// lib/screens/crop_profiles_screen.dart
//
// Changes from previous version:
//  1. Supports multiple profiles — each user can create, edit, delete profiles.
//  2. The "active" profile is whichever one devices.crop_profile_id points to.
//     Tapping "Set Active" on any card updates that FK.
//  3. Editing/creating uses a bottom sheet that contains the same
//     slider + fields from the original screen — look and feel unchanged.
//  4. plant_name field added (needed by Stage 2 Perenual lookup).
//  5. The FAB at bottom-right opens the sheet for a new profile.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme.dart';
import '../providers/app_state_provider.dart';

// ── Simple data model for one row from crop_profiles ─────────────────────────
class _Profile {
  final int       id;
  String          name;
  String          plantName;        // stored in plant_name column; used by Perenual
  double          minMoisture;
  DateTime?       perenualCachedAt; // null = no Perenual data fetched yet

  _Profile({
    required this.id,
    required this.name,
    required this.plantName,
    required this.minMoisture,
    this.perenualCachedAt,
  });

  factory _Profile.fromMap(Map<String, dynamic> m) => _Profile(
    id:               m['id'] as int,
    name:             (m['name'] as String?) ?? 'Unnamed Profile',
    plantName:        (m['plant_name'] as String?) ?? '',
    minMoisture:      (m['min_moisture'] as num).toDouble(),
    // Supabase returns timestamps as ISO-8601 strings; parse to DateTime.
    perenualCachedAt: m['perenual_cached_at'] != null
        ? DateTime.parse(m['perenual_cached_at'] as String).toLocal()
        : null,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
class CropProfilesScreen extends StatefulWidget {
  const CropProfilesScreen({super.key});

  @override
  State<CropProfilesScreen> createState() => _CropProfilesScreenState();
}

class _CropProfilesScreenState extends State<CropProfilesScreen> {
  List<_Profile> _profiles    = [];
  int?           _activeId;              // crop_profile_id on the device row
  bool           _loading     = true;
  final Set<int> _fetchingIds = {};      // profiles currently being fetched

  // ── Load all profiles + which one is active ───────────────────────────────
  Future<void> _load() async {
    setState(() => _loading = true);
    final deviceId = context.read<AppStateProvider>().deviceId;
    final userId   = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) { setState(() => _loading = false); return; }

    try {
      // All profiles belonging to this user
      final rows = await Supabase.instance.client
          .from('crop_profiles')
          .select('id, name, plant_name, min_moisture, perenual_cached_at')
          .eq('user_id', userId)
          .order('id', ascending: true) as List<dynamic>;

      // Active profile id from the device row
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
          _loading  = false;
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

  // ── Set a profile as active on the device ────────────────────────────────
  Future<void> _setActive(int profileId) async {
    final deviceId = context.read<AppStateProvider>().deviceId;
    if (deviceId == null) return;
    await Supabase.instance.client
        .from('devices')
        .update({'crop_profile_id': profileId})
        .eq('id', deviceId);
    setState(() => _activeId = profileId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:  const Text('Active profile updated.'),
          behavior: SnackBarBehavior.floating,
          margin:   const EdgeInsets.all(20),
          shape:    RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  // ── Delete a profile (with confirm dialog) ────────────────────────────────
  Future<void> _delete(_Profile profile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title:   const Text('Delete Profile'),
        content: Text('Delete "${profile.name}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(context, rootNavigator: true).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(context, rootNavigator: true).pop(true),
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

    // If the deleted profile was active, clear the device FK
    if (_activeId == profile.id) {
      final deviceId = context.read<AppStateProvider>().deviceId;
      if (deviceId != null) {
        await Supabase.instance.client
            .from('devices')
            .update({'crop_profile_id': null})
            .eq('id', deviceId);
      }
    }

    await _load();
  }

  // ── Open bottom sheet for create or edit ─────────────────────────────────
  // Passing null for [profile] means "create new".
  void _openSheet({_Profile? profile}) {
    showModalBottomSheet(
      context:            context,
      isScrollControlled: true, // lets sheet resize when keyboard appears
      builder: (_) => _ProfileSheet(
        existing: profile,
        onSaved:  _load,
      ),
    );
  }

  // ── Fetch Perenual plant data for one profile ─────────────────────────────
  // The button on the card calls this. Shows a per-card loading indicator
  // while the request is in flight.
  //
  // STAGE 2 — swap the Future.delayed below with the real service call:
  //   import '../services/perenual_service.dart';
  //   await PerenualService.fetchPlantData(profile.id);
  // The rest of the method (setState, _load, error handling) stays exactly
  // as-is — no other changes to this screen are needed for Stage 2.
  Future<void> _fetchData(_Profile profile) async {
    if (_fetchingIds.contains(profile.id)) return; // already in flight
    setState(() => _fetchingIds.add(profile.id));
    try {
      // ── STAGE 2: replace the line below ──────────────────────────────────
      await Future.delayed(const Duration(milliseconds: 300)); // placeholder
      // ─────────────────────────────────────────────────────────────────────
      await _load(); // reload list to pick up updated perenual_cached_at
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:  Text('Failed to fetch plant data: $e'),
            behavior: SnackBarBehavior.floating,
            margin:   const EdgeInsets.all(20),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _fetchingIds.remove(profile.id));
    }
  }


  @override
  Widget build(BuildContext context) {
    final colors    = Theme.of(context).colorScheme;
    final appColors = Theme.of(context).extension<AppColors>()!;

    return Scaffold(
      // FAB opens the sheet for a new profile
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openSheet(),
        tooltip:   'Add Profile',
        child:     Icon(PhosphorIcons.plus()),
      ),

      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                children: [
                  // ── Page title ──────────────────────────────────────────
                  Text(
                    'Crop Profiles',
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(fontFamily: 'GermaniaOne', fontSize: 24),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Create profiles for each plant. '
                    'Set one as Active to use it for irrigation & fertigation.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 24),

                  // ── Empty state ─────────────────────────────────────────
                  if (_profiles.isEmpty)
                    _EmptyState(onAdd: () => _openSheet())
                  else
                    ...List.generate(_profiles.length, (i) {
                      final p        = _profiles[i];
                      final isActive = p.id == _activeId;
                      return _ProfileCard(
                        profile:     p,
                        isActive:    isActive,
                        colors:      colors,
                        appColors:   appColors,
                        onSetActive: isActive ? null : () => _setActive(p.id),
                        onEdit:      () => _openSheet(profile: p),
                        onDelete:    () => _delete(p),
                        onFetchData: p.plantName.isNotEmpty
                            ? () => _fetchData(p)
                            : null,
                        isFetching:  _fetchingIds.contains(p.id),
                      );
                    }),
                ],
              ),
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Profile card — same Card style as the original screen
// ─────────────────────────────────────────────────────────────────────────────
class _ProfileCard extends StatelessWidget {
  final _Profile      profile;
  final bool          isActive;
  final ColorScheme   colors;
  final AppColors     appColors;
  final VoidCallback? onSetActive;
  final VoidCallback  onEdit;
  final VoidCallback  onDelete;
  // null = plant_name not set, so button is hidden entirely
  final VoidCallback? onFetchData;
  final bool          isFetching;

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

  // Returns a human-readable "X days ago / today / yesterday" label.
  // Used in the Perenual cache status row.
  String _cacheLabel(DateTime cachedAt) {
    final diff = DateTime.now().difference(cachedAt).inDays;
    if (diff == 0) return 'today';
    if (diff == 1) return 'yesterday';
    return '$diff days ago';
  }

  @override
  Widget build(BuildContext context) {
    final cached = profile.perenualCachedAt;

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
            // ── Header row ───────────────────────────────────────────────
            Row(
              children: [
                Icon(PhosphorIcons.plant(), color: appColors.successGreen, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    profile.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (isActive)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color:        AppTheme.teal,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'ACTIVE',
                      style: TextStyle(
                        color:         Colors.white,
                        fontSize:      11,
                        fontWeight:    FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                const SizedBox(width: 4),
                IconButton(
                  onPressed:     onEdit,
                  icon:          Icon(PhosphorIcons.pencilSimple(), size: 18),
                  visualDensity: VisualDensity.compact,
                  tooltip:       'Edit',
                ),
                IconButton(
                  onPressed:     onDelete,
                  icon:          Icon(PhosphorIcons.trash(), size: 18, color: colors.error),
                  visualDensity: VisualDensity.compact,
                  tooltip:       'Delete',
                ),
              ],
            ),

            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 10),

            // ── Details row — plant name + moisture ──────────────────────
            Row(
              children: [
                Expanded(
                  child: _DetailChip(
                    icon:  PhosphorIcons.leaf(),
                    label: profile.plantName.isNotEmpty
                        ? profile.plantName
                        : 'No plant set',
                    faded: profile.plantName.isEmpty,
                  ),
                ),
                const SizedBox(width: 8),
                _DetailChip(
                  icon:  PhosphorIcons.drop(),
                  label: '${profile.minMoisture.round()}% threshold',
                ),
              ],
            ),

            // ── Perenual status row ──────────────────────────────────────
            // Only shown when a plant name has been entered.
            // Green chip  = data is cached (shows when it was last fetched).
            // Amber chip  = no data yet; fetch button is enabled.
            // Stage 2 wires the fetch button to PerenualService.
            if (profile.plantName.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  // Status chip
                  Expanded(
                    child: cached != null
                        ? _DetailChip(
                            icon:  PhosphorIcons.checkCircle(),
                            label: 'Plant data cached · ${_cacheLabel(cached)}',
                            color: AppTheme.teal,
                          )
                        : _DetailChip(
                            icon:  PhosphorIcons.warningCircle(),
                            label: 'No plant data yet',
                            color: const Color(0xFFB45309), // amber-700
                          ),
                  ),
                  const SizedBox(width: 8),
                  // Fetch / Refresh button
                  SizedBox(
                    height: 32,
                    child: isFetching
                        // Loading spinner while the Edge Function is running
                        ? const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: SizedBox(
                              width:  18,
                              height: 18,
                              child:  CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : OutlinedButton.icon(
                            onPressed: onFetchData,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.teal,
                              side: const BorderSide(color: AppTheme.teal),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 0,
                              ),
                              textStyle: const TextStyle(fontSize: 12),
                            ),
                            icon:  Icon(
                              cached != null
                                  ? PhosphorIcons.arrowClockwise()
                                  : PhosphorIcons.arrowSquareOut(),
                              size: 14,
                            ),
                            label: Text(cached != null ? 'Refresh' : 'Fetch Data'),
                          ),
                  ),
                ],
              ),
            ],

            // ── Set Active button ────────────────────────────────────────
            if (onSetActive != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onSetActive,
                  icon:  Icon(PhosphorIcons.check(), size: 16),
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

// ── Small icon + label used inside the card ───────────────────────────────────
class _DetailChip extends StatelessWidget {
  final IconData icon;
  final String   label;
  final bool     faded;
  final Color?   color; // explicit colour overrides the default pine/faded logic
  const _DetailChip({
    required this.icon,
    required this.label,
    this.faded = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final resolved = color ??
        (faded
            ? AppTheme.pine.withValues(alpha: 0.35)
            : AppTheme.pine);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: resolved),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: resolved),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────
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
            Icon(PhosphorIcons.plant(), size: 56,
                color: AppTheme.teal.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text('No profiles yet',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text('Tap the + button to create your first crop profile.',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onAdd,
              icon:  Icon(PhosphorIcons.plus()),
              label: const Text('Add Profile'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bottom sheet — used for both CREATE and EDIT.
// Contains the same slider + fields from the original screen.
// ─────────────────────────────────────────────────────────────────────────────
class _ProfileSheet extends StatefulWidget {
  final _Profile?    existing; // null = create, non-null = edit
  final VoidCallback onSaved;
  const _ProfileSheet({this.existing, required this.onSaved});

  @override
  State<_ProfileSheet> createState() => _ProfileSheetState();
}

class _ProfileSheetState extends State<_ProfileSheet> {
  final _formKey             = GlobalKey<FormState>();
  final _nameController      = TextEditingController();
  final _plantNameController = TextEditingController();

  double _threshold = 30.0;
  bool   _saving    = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      _nameController.text      = widget.existing!.name;
      _plantNameController.text = widget.existing!.plantName;
      _threshold                = widget.existing!.minMoisture;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _plantNameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final userId    = Supabase.instance.client.auth.currentUser?.id;
    final name      = _nameController.text.trim();
    final plantName = _plantNameController.text.trim();

    try {
      if (_isEdit) {
        // If plant name changed, clear Perenual cache so Stage 2 re-fetches
        final plantChanged = plantName != widget.existing!.plantName;
        await Supabase.instance.client
            .from('crop_profiles')
            .update({
              'name':         name.isNotEmpty ? name : 'My Crop Profile',
              'plant_name':   plantName.isNotEmpty ? plantName : null,
              'min_moisture': _threshold,
              if (plantChanged) 'perenual_data':       null,
              if (plantChanged) 'perenual_species_id': null,
              if (plantChanged) 'perenual_cached_at':  null,
            })
            .eq('id', widget.existing!.id);
      } else {
        // New profile — plain INSERT, no conflict issues
        await Supabase.instance.client
            .from('crop_profiles')
            .insert({
              'user_id':      userId,
              'name':         name.isNotEmpty ? name : 'My Crop Profile',
              'plant_name':   plantName.isNotEmpty ? plantName : null,
              'min_moisture': _threshold,
            });
      }

      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        widget.onSaved();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:  Text(_isEdit ? 'Profile updated.' : 'Profile created.'),
            behavior: SnackBarBehavior.floating,
            margin:   const EdgeInsets.all(20),
            shape:    RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:  Text('Error: $e'),
            behavior: SnackBarBehavior.floating,
            margin:   const EdgeInsets.all(20),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors    = Theme.of(context).colorScheme;
    final appColors = Theme.of(context).extension<AppColors>()!;
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 24, 16, 24 + bottomPad),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize:        MainAxisSize.min,
            crossAxisAlignment:  CrossAxisAlignment.start,
            children: [
              // Sheet title
              Row(
                children: [
                  Icon(PhosphorIcons.plant(), color: appColors.successGreen),
                  const SizedBox(width: 8),
                  Text(
                    _isEdit ? 'Edit Profile' : 'New Profile',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Profile name — what the user calls this profile
              TextFormField(
                controller:         _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Profile Name',
                  hintText:  'e.g. Summer Tomato',
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty)
                        ? 'Please enter a profile name'
                        : null,
              ),
              const SizedBox(height: 16),

              // Plant name — common name sent to Perenual in Stage 2
              TextFormField(
                controller:         _plantNameController,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText:  'Plant Name',
                  hintText:   'e.g. Tomato, Wheat, Basil',
                  helperText: 'Used to fetch nutrient & care data from Perenual.',
                  prefixIcon: Icon(PhosphorIcons.leaf(), color: colors.primary),
                ),
                validator: (_) => null,
              ),
              const SizedBox(height: 24),

              // Moisture threshold — same Card + Slider as original screen
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(PhosphorIcons.drop(), color: colors.primary),
                          const SizedBox(width: 8),
                          Text('Dry Threshold (%)',
                              style: Theme.of(context).textTheme.titleMedium),
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
                        value:     _threshold,
                        min:       0,
                        max:       100,
                        divisions: 20,
                        label:     '${_threshold.round()}%',
                        onChanged: (v) => setState(() => _threshold = v),
                      ),
                      Center(
                        child: Text(
                          '${_threshold.round()}%',
                          style: const TextStyle(
                            fontSize:   24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Save button
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2,
                          ),
                        )
                      : Icon(PhosphorIcons.floppyDisk()),
                  label: Text(
                    _saving ? 'Saving…'
                            : (_isEdit ? 'Save Changes' : 'Create Profile'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
