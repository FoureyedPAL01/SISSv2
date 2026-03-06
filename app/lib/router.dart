import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/irrigation_screen.dart';
import 'screens/weather_screen.dart';
import 'screens/pump_control_screen.dart';
import 'screens/crop_profiles_screen.dart';
import 'screens/water_usage_screen.dart';
import 'screens/fertigation_screen.dart';
import 'screens/alerts_screen.dart';
import 'screens/settings_screen.dart';
import 'dart:async';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');
final GlobalKey<NavigatorState> _shellNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'shell');

final GoRouter appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/',

  redirect: (BuildContext context, GoRouterState state) {
    final session = Supabase.instance.client.auth.currentSession;
    final isOnLoginPage = state.matchedLocation == '/login';

    // Not logged in and not already on login → go to login
    if (session == null && !isOnLoginPage) return '/login';

    // Logged in but somehow on the login page → go to dashboard
    if (session != null && isOnLoginPage) return '/';

    // Otherwise, proceed normally
    return null;
  },

  refreshListenable: GoRouterRefreshStream(
    Supabase.instance.client.auth.onAuthStateChange,
  ),

  routes: [
    // ── Login route (outside the ShellRoute so it has no nav bar) ──────────
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginScreen(),
    ),

    ShellRoute(
      navigatorKey: _shellNavigatorKey,
      builder: (context, state, child) => AppLayoutScaffold(child: child),
      routes: [
        GoRoute(path: '/',           builder: (_, _) => const DashboardScreen()),
        GoRoute(path: '/irrigation', builder: (_, _) => const IrrigationScreen()),
        GoRoute(path: '/weather',    builder: (_, _) => const WeatherScreen()),
        GoRoute(path: '/pump',       builder: (_, _) => const PumpControlScreen()),
        GoRoute(path: '/crops',      builder: (_, _) => const CropProfilesScreen()),
        GoRoute(path: '/water',      builder: (_, _) => const WaterUsageScreen()),
        GoRoute(path: '/fertigation',builder: (_, _) => const FertigationScreen()),
        GoRoute(path: '/alerts',     builder: (_, _) => const AlertsScreen()),
        GoRoute(path: '/settings',   builder: (_, _) => const SettingsScreen()),
      ],
    ),
  ],
);

// Inside router.dart — replace AppLayoutScaffold class

class AppLayoutScaffold extends StatelessWidget {
  const AppLayoutScaffold({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final String location = GoRouterState.of(context).uri.path;

    // Map route → bottom nav index (only the 5 main tabs)
    int currentIndex = switch (location) {
      '/'               => 0,
      var s when s.startsWith('/irrigation') => 1,
      var s when s.startsWith('/pump')       => 2,
      var s when s.startsWith('/weather')    => 3,
      var s when s.startsWith('/settings')   => 4,
      _                 => 0,
    };

    return Scaffold(
      appBar: AppBar(
        title: Text('Smart Irrigation System F', style: TextStyle(fontFamily: 'Bungee', fontSize: 20, color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: Icon(Icons.notifications_outlined),
            onPressed: () => context.go('/alerts'),
            tooltip: 'Alerts',
          ),
          const SizedBox(width: 8),
        ],
      ),

      // ── M3 NavigationDrawer ─────────────────────────────────────────────
      drawer: NavigationDrawer(
        selectedIndex: currentIndex,
        onDestinationSelected: (index) {
          Navigator.pop(context); // close drawer
          switch (index) {
            case 0: context.go('/');             break;
            case 1: context.go('/irrigation');   break;
            case 2: context.go('/pump');          break;
            case 3: context.go('/weather');       break;
            case 4: context.go('/crops');         break;
            case 5: context.go('/water');         break;
            case 6: context.go('/fertigation');   break;
            case 7: context.go('/alerts');        break;
            case 8: context.go('/settings');      break;
          }
        },
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(28, 24, 16, 10),
            child: Text('SISF',
                style: TextStyle(fontFamily: 'Bungee', fontSize: 22, color: Color(0xFF347433), fontWeight: FontWeight.bold)),
          ),
          // NavigationDrawerDestination is the M3 drawer item widget
          NavigationDrawerDestination(
            icon: Icon(Icons.home_outlined, color: Color(0xFF000000)),
            selectedIcon: Icon(Icons.home, color: Color(0xFF000000)),
            label: Text('Dashboard', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF000000))),
          ),
          NavigationDrawerDestination(
            icon: Icon(Icons.water_drop_outlined, color: Color(0xFF000000)),
            selectedIcon: Icon(Icons.water_drop, color: Color(0xFF000000)),
            label: Text('Irrigation', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF000000))),
          ),
          NavigationDrawerDestination(
            icon: Icon(Icons.power_settings_new_outlined, color: Color(0xFF000000)),
            selectedIcon: Icon(Icons.power_settings_new, color: Color(0xFF000000)),
            label: Text('Pump Control', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF000000))),
          ),
          NavigationDrawerDestination(
            icon: Icon(Icons.cloud_outlined, color: Color(0xFF000000)),
            selectedIcon: Icon(Icons.cloud, color: Color(0xFF000000)),
            label: Text('Weather', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF000000))),
          ),
          NavigationDrawerDestination(
            icon: Icon(Icons.eco_outlined, color: Color(0xFF000000)),
            selectedIcon: Icon(Icons.eco, color: Color(0xFF000000)),
            label: Text('Crop Profiles', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF000000))),
          ),
          NavigationDrawerDestination(
            icon: Icon(Icons.bar_chart_outlined, color: Color(0xFF000000)),
            selectedIcon: Icon(Icons.bar_chart, color: Color(0xFF000000)),
            label: Text('Water Usage', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF000000))),
          ),
          NavigationDrawerDestination(
            icon: Icon(Icons.science_outlined, color: Color(0xFF000000)),
            selectedIcon: Icon(Icons.science, color: Color(0xFF000000)),
            label: Text('Fertigation', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF000000))),
          ),
          NavigationDrawerDestination(
            icon: Icon(Icons.notifications_outlined, color: Color(0xFF000000)),
            selectedIcon: Icon(Icons.notifications, color: Color(0xFF000000)),
            label: Text('Alerts', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF000000))),
          ),
          NavigationDrawerDestination(
            icon: Icon(Icons.settings_outlined, color: Color(0xFF000000)),
            selectedIcon: Icon(Icons.settings, color: Color(0xFF000000)),
            label: Text('Settings', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF000000))),
          ),
        ],
      ),

      body: child,

      // ── M3 NavigationBar (replaces BottomNavigationBar) ─────────────────
      // Key M3 differences:
      // - Pill-shaped indicator behind selected icon
      // - No shift animation, labels always visible
      // - Uses colorScheme.secondaryContainer for indicator
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (index) {
          switch (index) {
            case 0: context.go('/');           break;
            case 1: context.go('/irrigation'); break;
            case 2: context.go('/pump');       break;
            case 3: context.go('/weather');    break;
            case 4: context.go('/settings');   break;
          }
        },
        destinations: const [
          NavigationDestination(
            icon:         Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon:         Icon(Icons.water_drop_outlined),
            selectedIcon: Icon(Icons.water_drop),
            label: 'Irrigate',
          ),
          NavigationDestination(
            icon:         Icon(Icons.power_settings_new_outlined),
            selectedIcon: Icon(Icons.power_settings_new),
            label: 'Pump',
          ),
          NavigationDestination(
            icon:         Icon(Icons.cloud_outlined),
            selectedIcon: Icon(Icons.cloud),
            label: 'Weather',
          ),
          NavigationDestination(
            icon:         Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

class GoRouterRefreshStream extends ChangeNotifier {
  late final StreamSubscription<dynamic> _subscription;

  GoRouterRefreshStream(Stream<dynamic> stream) {
    _subscription = stream.listen((_) => notifyListeners());
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

