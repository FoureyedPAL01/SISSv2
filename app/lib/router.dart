import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'screens/dashboard_screen.dart';
import 'screens/irrigation_screen.dart';
import 'screens/weather_screen.dart';
import 'screens/pump_control_screen.dart';
import 'screens/crop_profiles_screen.dart';
import 'screens/water_usage_screen.dart';
import 'screens/fertigation_screen.dart';
import 'screens/alerts_screen.dart';
import 'screens/settings_screen.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');
final GlobalKey<NavigatorState> _shellNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'shell');

final GoRouter appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/',
  routes: [
    ShellRoute(
      navigatorKey: _shellNavigatorKey,
      builder: (BuildContext context, GoRouterState state, Widget child) {
        return AppLayoutScaffold(child: child);
      },
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const DashboardScreen(),
        ),
        GoRoute(
          path: '/irrigation',
          builder: (context, state) => const IrrigationScreen(),
        ),
        GoRoute(
          path: '/weather',
          builder: (context, state) => const WeatherScreen(),
        ),
        GoRoute(
          path: '/pump',
          builder: (context, state) => const PumpControlScreen(),
        ),
        GoRoute(
          path: '/crops',
          builder: (context, state) => const CropProfilesScreen(),
        ),
        GoRoute(
          path: '/water',
          builder: (context, state) => const WaterUsageScreen(),
        ),
        GoRoute(
          path: '/fertigation',
          builder: (context, state) => const FertigationScreen(),
        ),
        GoRoute(
          path: '/alerts',
          builder: (context, state) => const AlertsScreen(),
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SettingsScreen(),
        ),
      ],
    ),
  ],
);

// The main layout wrapper corresponding to Layout.tsx
class AppLayoutScaffold extends StatelessWidget {
  const AppLayoutScaffold({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Determine selected index based on current path
    final String location = GoRouterState.of(context).uri.path;
    int currentIndex = 0;
    
    if (location == '/') {
      currentIndex = 0;
    } else if (location.startsWith('/irrigation')) {
      currentIndex = 1;
    } else if (location.startsWith('/pump')) {
      currentIndex = 2;
    } else if (location.startsWith('/weather')) {
      currentIndex = 3;
    } else if (location.startsWith('/settings')) {
      currentIndex = 4;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Irrigation'),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.bell),
            onPressed: () => context.go('/alerts'),
          )
        ],
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(color: Color(0xFF16A34A)),
              child: Text('Navigation', style: TextStyle(color: Colors.white, fontSize: 24)),
            ),
            ListTile(
              leading: const Icon(LucideIcons.home),
              title: const Text('Dashboard'),
              onTap: () { context.go('/'); Navigator.pop(context); },
            ),
            ListTile(
              leading: const Icon(LucideIcons.droplets),
              title: const Text('Irrigation'),
              onTap: () { context.go('/irrigation'); Navigator.pop(context); },
            ),
            ListTile(
              leading: const Icon(LucideIcons.power),
              title: const Text('Pump Control'),
              onTap: () { context.go('/pump'); Navigator.pop(context); },
            ),
            ListTile(
              leading: const Icon(LucideIcons.cloudRain),
              title: const Text('Weather'),
              onTap: () { context.go('/weather'); Navigator.pop(context); },
            ),
            ListTile(
              leading: const Icon(LucideIcons.sprout),
              title: const Text('Crop Profiles'),
              onTap: () { context.go('/crops'); Navigator.pop(context); },
            ),
            ListTile(
              leading: const Icon(LucideIcons.barChart2),
              title: const Text('Water Usage'),
              onTap: () { context.go('/water'); Navigator.pop(context); },
            ),
            ListTile(
              leading: const Icon(LucideIcons.flaskConical),
              title: const Text('Fertigation'),
              onTap: () { context.go('/fertigation'); Navigator.pop(context); },
            ),
            ListTile(
              leading: const Icon(LucideIcons.settings),
              title: const Text('Settings'),
              onTap: () { context.go('/settings'); Navigator.pop(context); },
            ),
          ],
        ),
      ),
      body: child,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: currentIndex,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFF16A34A),
        unselectedItemColor: Colors.grey,
        onTap: (index) {
          switch (index) {
            case 0: context.go('/'); break;
            case 1: context.go('/irrigation'); break;
            case 2: context.go('/pump'); break;
            case 3: context.go('/weather'); break;
            case 4: context.go('/settings'); break;
          }
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(LucideIcons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(LucideIcons.droplets), label: 'Irrigate'),
          BottomNavigationBarItem(icon: Icon(LucideIcons.power), label: 'Pump'),
          BottomNavigationBarItem(icon: Icon(LucideIcons.cloudRain), label: 'Weather'),
          BottomNavigationBarItem(icon: Icon(LucideIcons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}
