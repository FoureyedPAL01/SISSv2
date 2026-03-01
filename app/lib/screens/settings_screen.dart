import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:lucide_icons/lucide_icons.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _signOut(BuildContext context) async {
    await Supabase.instance.client.auth.signOut();
    // In a full implementation with Auth, this would redirect to a login screen.
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          Text("Settings", style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 24),
          
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(LucideIcons.user),
                  title: const Text("Account"),
                  subtitle: Text(user?.email ?? "Not logged in"),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(LucideIcons.smartphone),
                  title: const Text("Device Configuration"),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {},
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(LucideIcons.bell),
                  title: const Text("Notifications"),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {},
                ),
              ],
            )
          ),
          
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: () => _signOut(context),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade50, foregroundColor: Colors.red),
            child: const Text("Sign Out"),
          )
        ],
      )
    );
  }
}
