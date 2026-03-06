import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import '../providers/app_state_provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _signOut(BuildContext context) async {
  // Calls provider.signOut() → Supabase signs out → auth stream emits
  // → GoRouterRefreshStream notifies go_router → redirect fires → '/login'
  // No manual context.go() needed — the router handles it automatically.
  await context.read<AppStateProvider>().signOut();
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          Text("Settings", style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            fontFamily: 'Bungee',
            fontSize: 24,
          )),
          const SizedBox(height: 24),

          Card(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(PhosphorIcons.user()),
                  title: const Text("Account"),
                  subtitle: Text(user?.email ?? "Not logged in"),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(PhosphorIcons.deviceMobile()),
                  title: const Text("Device Configuration"),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {},
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(PhosphorIcons.bell()),
                  title: const Text("Notifications"),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {},
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(PhosphorIcons.gear()),
                  title: const Text("Settings"),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {},
                ),
              ],
            )
          ),

          const SizedBox(height: 32),
          FilledButton(
            onPressed: () => _signOut(context),
            style: FilledButton.styleFrom(foregroundColor: Colors.red),
            child: const Text("Sign Out"),
          )
        ],
      )
    );
  }
}

