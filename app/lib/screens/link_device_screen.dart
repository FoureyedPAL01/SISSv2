// lib/screens/link_device_screen.dart
// SISS v2 -- Shown automatically when the logged-in user has no device linked.
// User enters the device UUID from the sticker on the ESP32 box.
// On submit, updates devices.user_id to the current user (claiming).
// Previous owner loses access. All historical data becomes visible to new owner.

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/app_state_provider.dart';

class LinkDeviceScreen extends StatefulWidget {
  const LinkDeviceScreen({super.key});

  @override
  State<LinkDeviceScreen> createState() => _LinkDeviceScreenState();
}

class _LinkDeviceScreenState extends State<LinkDeviceScreen> {
  final _controller = TextEditingController();
  bool    _isLoading = false;
  String? _error;

  // Validates UUID format: 8-4-4-4-12 hex characters separated by dashes.
  bool _isValidUuid(String s) {
    final regex = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}'
      r'-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    );
    return regex.hasMatch(s.trim());
  }

  Future<void> _linkDevice() async {
    final uuid = _controller.text.trim();
    debugPrint('[DEBUG] Attempting claim with UUID: $uuid');
    debugPrint('[DEBUG] User: ${Supabase.instance.client.auth.currentUser?.id}');
    
    if (!_isValidUuid(uuid)) {
      setState(() => _error = 'Please enter a valid device UUID.');
      return;
    }

    setState(() { _isLoading = true; _error = null; });

    try {
      final userId = Supabase.instance.client.auth.currentUser!.id;

      final response = await Supabase.instance.client
          .from('devices')
          .update({
        'user_id':    userId,
        'claimed_at': DateTime.now().toIso8601String(),
      })
          .eq('id', uuid)
          .select();

      debugPrint('[DEBUG] Claim response: $response');

      if (response.isEmpty) {
        setState(() {
          _error = 'Device not found. Check the UUID and try again.';
          _isLoading = false;
        });
        return;
      }

      if (!mounted) return;
      await context.read<AppStateProvider>().refresh();

    } on PostgrestException catch (e) {
      print('[DEBUG] Full error: $e');
      setState(() {
        _error = 'Failed to link device: ${e.message}';
        _isLoading = false;
      });
    } catch (e) {
      print('[DEBUG] Full error: $e');
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: SingleChildScrollView(          // prevents overflow when keyboard opens
          padding: const EdgeInsets.all(32.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 48),      // top spacing replaces mainAxisAlignment center
              Icon(Icons.sensors, size: 72, color: colors.primary),
              const SizedBox(height: 24),
              Text(
                'Link Your Device',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Enter the Device UUID printed on the sticker\n'
                    'on your SISS hardware unit.',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              TextField(
                controller:         _controller,
                autocorrect:        false,
                enableSuggestions:  false,
                textCapitalization: TextCapitalization.none,
                decoration: InputDecoration(
                  labelText: 'Device UUID',
                  hintText:  'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx',
                  border:    const OutlineInputBorder(),
                  errorText: _error,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _isLoading ? null : _linkDevice,
                child: _isLoading
                    ? const SizedBox(
                  height: 20, width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                    : const Text('Link Device'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}