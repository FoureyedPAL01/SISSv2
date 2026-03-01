import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../providers/app_state_provider.dart';

class CropProfilesScreen extends StatefulWidget {
  const CropProfilesScreen({super.key});

  @override
  State<CropProfilesScreen> createState() => _CropProfilesScreenState();
}

class _CropProfilesScreenState extends State<CropProfilesScreen> {
  final _formKey = GlobalKey<FormState>();
  double _dryThreshold = 30.0;
  bool _isSaving = false;

  Future<void> _fetchCurrentProfile() async {
    final deviceId = context.read<AppStateProvider>().deviceId;
    if (deviceId == null) return;

    try {
      final res = await Supabase.instance.client
          .from('devices')
          .select('*, crop_profiles(*)')
          .eq('id', deviceId)
          .single();
          
      if (res['crop_profiles'] != null && mounted) {
        setState(() {
          _dryThreshold = (res['crop_profiles']['min_moisture'] as num).toDouble();
        });
      }
    } catch (e) {
      debugPrint("Could not fetch crop profile: \$e");
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchCurrentProfile();
    });
  }

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();
    
    setState(() => _isSaving = true);
    final deviceId = context.read<AppStateProvider>().deviceId;
    final userId = Supabase.instance.client.auth.currentUser?.id;

    try {
      // 1. Check if user already has a crop profile attached
      final cropRes = await Supabase.instance.client
          .from('crop_profiles')
          .upsert({
            'user_id': userId,
            'name': 'Custom Flutter Profile',
            'min_moisture': _dryThreshold
          })
          .select()
          .single();
          
      // 2. Link the device to this crop profile
      if (deviceId != null) {
        await Supabase.instance.client
            .from('devices')
            .update({'crop_profile_id': cropRes['id']})
            .eq('id', deviceId);
      }

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings saved successfully.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error saving: \$e')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            Text("Crop Thresholds", style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 8),
            const Text("Adjust the minimum soil moisture level. If moisture falls below this percentage, the automated script will turn your pump on."),
            const SizedBox(height: 24),
            
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(LucideIcons.sprout, color: Colors.green),
                        const SizedBox(width: 8),
                        Text("Dry Threshold (%)", style: Theme.of(context).textTheme.titleLarge),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Slider(
                      value: _dryThreshold,
                      min: 0,
                      max: 100,
                      divisions: 20,
                      label: "\${_dryThreshold.round()}%",
                      activeColor: Colors.brown.shade400,
                      onChanged: (val) => setState(() => _dryThreshold = val),
                    ),
                    Center(
                      child: Text("\${_dryThreshold.round()}%", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isSaving ? null : _saveSettings,
              child: _isSaving ? const CircularProgressIndicator(color: Colors.white) : const Text("Save Crop Parameters"),
            )
          ],
        )
      )
    );
  }
}
