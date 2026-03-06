import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

class FertigationScreen extends StatelessWidget {
  const FertigationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          Text("Fertigation Management", style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            fontFamily: 'Bungee',
            fontSize: 24,
          )),
          const SizedBox(height: 8),
          Text("Track nutrient application schedules alongside your irrigation.", style: Theme.of(context).textTheme.titleMedium),
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
                          Icon(PhosphorIcons.flask(), color: Colors.purple),
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
          FilledButton.icon(
            onPressed: () {},
            icon: Icon(PhosphorIcons.plus()),
            label: const Text("Log Fertilizer Application"),
            style: FilledButton.styleFrom(
                          backgroundColor: Colors.purple,
                          foregroundColor: Colors.white,
            ),
          )
        ],
      )
    );
  }
}


