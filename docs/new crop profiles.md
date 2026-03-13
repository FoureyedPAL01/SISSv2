// lib/screens/crop_profiles_screen.dart
//
// Changes from previous version:
//  1. Added a "Plant Name" TextFormField above the moisture slider.
//     This name is what Stage 2 sends to Perenual to fetch plant data.
//  2. _fetchCurrentProfile() now also loads plant_name from Supabase.
//  3. _saveSettings() now writes plant_name into crop_profiles.
//     The hardcoded name 'Custom Flutter Profile' is replaced with the
//     user's plant name (or kept as fallback if left empty).
//  4. Existing moisture threshold slider logic is completely unchanged.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme.dart';
import '../providers/app_state_provider.dart';

class CropProfilesScreen extends StatefulWidget {
  const CropProfilesScreen({super.key});

  @override
  State<CropProfilesScreen> createState() => _CropProfilesScreenState();
}

class _CropProfilesScreenState extends State<CropProfilesScreen> {
  final _formKey             = GlobalKey<FormState>();
  final _plantNameController = TextEditingController();

  double _dryThreshold = 30.0;
  bool   _isSaving     = false;

  // ── Load existing profile on open ─────────────────────────────────────────
  // Reads both min_moisture and plant_name from the linked crop profile.
  Future<void> _fetchCurrentProfile() async {
    final deviceId = context.read<AppStateProvider>().deviceId;
    if (deviceId == null) return;

    try {
      final res = await Supabase.instance.client
          .from('devices')
          .select('*, crop_profiles(*)')
          .eq('id', deviceId)
          .single();

      final profile = res['crop_profiles'];
      if (profile != null && mounted) {
        setState(() {
          _dryThreshold = (profile['min_moisture'] as num).toDouble();
          // plant_name may be null for existing profiles created before this migration
          _plantNameController.text = profile['plant_name'] as String? ?? '';
        });
      }
    } catch (e) {
      debugPrint('Could not fetch crop profile: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchCurrentProfile());
  }

  @override
  void dispose() {
    _plantNameController.dispose();
    super.dispose();
  }

  // ── Save ──────────────────────────────────────────────────────────────────
  // Writes plant_name + min_moisture to crop_profiles, then links the device.
  // perenual_data is intentionally NOT cleared here — Stage 2 will refresh it
  // automatically when it detects the plant_name has changed.
  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    setState(() => _isSaving = true);

    final deviceId = context.read<AppStateProvider>().deviceId;
    final userId   = Supabase.instance.client.auth.currentUser?.id;
    final name     = _plantNameController.text.trim();

    try {
      // upsert keyed on user_id — one profile per user for now
      final cropRes = await Supabase.instance.client
          .from('crop_profiles')
          .upsert({
            'user_id':      userId,
            // Use the plant name as the profile display name.
            // Falls back to 'My Crop Profile' if no name was entered.
            'name':         name.isNotEmpty ? name : 'My Crop Profile',
            'plant_name':   name.isNotEmpty ? name : null,
            'min_moisture': _dryThreshold,
          })
          .select()
          .single();

      // Link this device to the profile
      if (deviceId != null) {
        await Supabase.instance.client
            .from('devices')
            .update({'crop_profile_id': cropRes['id']})
            .eq('id', deviceId);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Crop profile saved.'),
            behavior:      SnackBarBehavior.floating,
            margin:        const EdgeInsets.all(20),
            shape:         RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:  Text('Error saving: $e'),
            behavior: SnackBarBehavior.floating,
            margin:   const EdgeInsets.all(20),
            shape:    RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final colors    = Theme.of(context).colorScheme;
    final appColors = Theme.of(context).extension<AppColors>()!;

    return Scaffold(
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            // ── Page title ────────────────────────────────────────────────
            Text(
              'Crop Profile',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontFamily: 'Bungee',
                fontSize:   24,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Set your plant name and soil moisture threshold. '
              'The plant name is used to fetch nutrient schedules '
              'on the Fertigation screen.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),

            // ── Plant Name card ───────────────────────────────────────────
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Section header
                    Row(
                      children: [
                        Icon(
                          PhosphorIcons.plant(),
                          color: appColors.successGreen,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Plant Name',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Enter the common name of your crop, e.g. Tomato, Wheat, Basil.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Text field — user types the crop name here
                    TextFormField(
                      controller: _plantNameController,
                      // Capitalise first letter automatically
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        hintText:    'e.g. Tomato',
                        prefixIcon:  Icon(
                          PhosphorIcons.magnifyingGlass(),
                          color: colors.primary,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        // Info note below the field
                        helperText:
                            'Used to fetch watering, nutrient & disease info '
                            'from Perenual plant database.',
                        helperMaxLines: 2,
                      ),
                      // Not required — user can save without a name,
                      // but the fertigation screen will prompt them to add one.
                      validator: (_) => null,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ── Moisture Threshold card ───────────────────────────────────
            // Unchanged from original — slider sets the pump trigger level.
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          PhosphorIcons.drop(),
                          color: colors.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Dry Threshold (%)',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'If soil moisture drops below this value, '
                      'the pump will turn on automatically.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Slider(
                      value:       _dryThreshold,
                      min:         0,
                      max:         100,
                      divisions:   20,
                      label:       '${_dryThreshold.round()}%',
                      activeColor: colors.primary,
                      onChanged:   (val) => setState(() => _dryThreshold = val),
                    ),
                    Center(
                      child: Text(
                        '${_dryThreshold.round()}%',
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

            // ── Save button ───────────────────────────────────────────────
            FilledButton.icon(
              onPressed: _isSaving ? null : _saveSettings,
              icon:  _isSaving
                  ? const SizedBox(
                      width:  18,
                      height: 18,
                      child:  CircularProgressIndicator(
                        color:       Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Icon(PhosphorIcons.floppyDisk()),
              label: Text(_isSaving ? 'Saving…' : 'Save Crop Profile'),
            ),

            const SizedBox(height: 12),

            // ── Hint: where to see the data ───────────────────────────────
            Center(
              child: Text(
                'Nutrient schedules are shown on the Fertigation screen.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.onSurface.withValues(alpha: 0.45),
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
