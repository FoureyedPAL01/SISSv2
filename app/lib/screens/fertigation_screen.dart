import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

class FertigationScreen extends StatelessWidget {
  const FertigationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          Text("Fertigation Management", style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          const Text("Track nutrient application schedules alongside your irrigation."),
          const SizedBox(height: 24),
          
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                   Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(LucideIcons.flaskConical, color: Colors.purple),
                          const SizedBox(width: 8),
                          Text("Nutrition Status", style: Theme.of(context).textTheme.titleLarge),
                        ],
                      ),
                      Text("Good", style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.green)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text("Days since last application"),
                    trailing: Text("12 Days", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                  const Divider(),
                  const ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text("Next scheduled application"),
                    trailing: Text("In 2 Days", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {},
            icon: const Icon(LucideIcons.plus),
            label: const Text("Log Fertilizer Application"),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.purple),
          )
        ],
      )
    );
  }
}
