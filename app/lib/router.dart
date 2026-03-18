import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'providers/app_state_provider.dart';
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
import 'screens/link_device_screen.dart';
import 'theme.dart';
import 'dart:async';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');
final GlobalKey<NavigatorState> _shellNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'shell');

// Combines auth stream AND AppStateProvider so the router re-evaluates
// redirect whenever either changes — fixes the stuck link-device screen.
class _RouterRefreshListenable extends ChangeNotifier {
  late final StreamSubscription<dynamic> _authSub;
  final AppStateProvider _appState;

  _RouterRefreshListenable(Stream<dynamic> authStream, this._appState) {
    // Re-evaluate redirect on every auth change
    _authSub = authStream.listen((_) => notifyListeners());
    // Re-evaluate redirect whenever AppStateProvider notifies
    // (e.g. after device is claimed and hasDevice becomes true)
    _appState.addListener(notifyListeners);
  }

  @override
  void dispose() {
    _authSub.cancel();
    _appState.removeListener(notifyListeners);
    super.dispose();
  }
}

GoRouter createRouter(AppStateProvider appState) => GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/',

  // Now refreshes on BOTH auth changes and AppStateProvider changes
  refreshListenable: _RouterRefreshListenable(
    Supabase.instance.client.auth.onAuthStateChange,
    appState,
  ),

  redirect: (BuildContext context, GoRouterState state) {
    final session = Supabase.instance.client.auth.currentSession;
    final isOnLoginPage = state.matchedLocation == '/login';
    final isOnLinkPage  = state.matchedLocation == '/link-device';
    final hasDevice     = appState.hasDevice;

    // Not logged in → go to login
    if (session == null && !isOnLoginPage) return '/login';

    // Logged in but on login page → check device
    if (session != null && isOnLoginPage) {
      return hasDevice ? '/' : '/link-device';
    }

    // Logged in but no device → link-device screen
    if (session != null && !hasDevice && !isOnLinkPage) return '/link-device';

    // Logged in with device but on link-device → dashboard
    if (session != null && hasDevice && isOnLinkPage) return '/';

    return null;
  },

  routes: [
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: '/link-device',
      builder: (context, state) => const LinkDeviceScreen(),
    ),
    ShellRoute(
      navigatorKey: _shellNavigatorKey,
      builder: (context, state, child) => AppLayoutScaffold(child: child),
      routes: [
        GoRoute(path: '/',            builder: (context, state) => const DashboardScreen()),
        GoRoute(path: '/irrigation',  builder: (context, state) => const IrrigationScreen()),
        GoRoute(path: '/weather',     builder: (context, state) => const WeatherScreen()),
        GoRoute(path: '/pump',        builder: (context, state) => const PumpControlScreen()),
        GoRoute(path: '/crops',       builder: (context, state) => const CropProfilesScreen()),
        GoRoute(path: '/water',       builder: (context, state) => const WaterUsageScreen()),
        GoRoute(path: '/fertigation', builder: (context, state) => const FertigationScreen()),
        GoRoute(path: '/alerts',      builder: (context, state) => const AlertsScreen()),
        GoRoute(path: '/settings',    builder: (context, state) => const SettingsScreen()),
      ],
    ),
  ],
);

// ── AppLayoutScaffold ──────────────────────────────────────────────────────

class AppLayoutScaffold extends StatelessWidget {
  const AppLayoutScaffold({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final String location = GoRouterState.of(context).uri.path;
    final colors = Theme.of(context).colorScheme;

    int currentIndex = switch (location) {
      '/'                                      => 0,
      var s when s.startsWith('/irrigation')   => 1,
      var s when s.startsWith('/pump')         => 2,
      var s when s.startsWith('/weather')      => 3,
      var s when s.startsWith('/settings')     => 4,
      _                                        => 0,
    };
    int drawerSelectedIndex = switch (location) {
      '/'                                       => 0,
      var s when s.startsWith('/irrigation')    => 1,
      var s when s.startsWith('/pump')          => 2,
      var s when s.startsWith('/weather')       => 3,
      var s when s.startsWith('/crops')         => 4,
      var s when s.startsWith('/water')         => 5,
      var s when s.startsWith('/fertigation')   => 6,
      var s when s.startsWith('/alerts')        => 7,
      var s when s.startsWith('/settings')      => 8,
      _                                         => 0,
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Smart Irrigation System F',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 20,
            color: colors.onSurface,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          Builder(
            builder: (context) {
              final username = context.select<AppStateProvider, String>((p) => p.username);
              if (username.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.person_outline, size: 18, color: colors.onSurface),
                    const SizedBox(width: 4),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 120),
                      child: Text(
                        username,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () => context.go('/alerts'),
            tooltip: 'Alerts',
          ),
          const SizedBox(width: 8),
        ],
      ),

      drawer: NavigationDrawer(
        selectedIndex: drawerSelectedIndex,
        onDestinationSelected: (index) {
          Navigator.pop(context);
          switch (index) {
            case 0: context.go('/');              break;
            case 1: context.go('/irrigation');    break;
            case 2: context.go('/pump');           break;
            case 3: context.go('/weather');        break;
            case 4: context.go('/crops');          break;
            case 5: context.go('/water');          break;
            case 6: context.go('/fertigation');    break;
            case 7: context.go('/alerts');         break;
            case 8: context.go('/settings');       break;
          }
        },
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 24, 16, 10),
            child: Text('SISF',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 22,
                    color: colors.primary,
                    fontWeight: FontWeight.bold)),
          ),
          Builder(
            builder: (context) {
              final username = context.select<AppStateProvider, String>((p) => p.username);
              if (username.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.fromLTRB(28, 16, 16, 8),
                child: Row(
                  children: [
                    Icon(Icons.person_outline, size: 20, color: colors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        username,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontWeight: FontWeight.bold, color: colors.primary),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          NavigationDrawerDestination(
            icon: Icon(Icons.home_outlined, color: colors.onSurface),
            selectedIcon: const Icon(Icons.home, color: Colors.white),
            label: Text('Dashboard',
                style: TextStyle(fontWeight: FontWeight.bold,
                    color: drawerSelectedIndex == 0 ? Colors.white : colors.onSurface)),
          ),
          NavigationDrawerDestination(
            icon: Icon(Icons.water_drop_outlined, color: colors.onSurface),
            selectedIcon: const Icon(Icons.water_drop, color: Colors.white),
            label: Text('Irrigation',
                style: TextStyle(fontWeight: FontWeight.bold,
                    color: drawerSelectedIndex == 1 ? Colors.white : colors.onSurface)),
          ),
          NavigationDrawerDestination(
            icon: Icon(Icons.power_settings_new_outlined, color: colors.onSurface),
            selectedIcon: const Icon(Icons.power_settings_new, color: Colors.white),
            label: Text('Pump Control',
                style: TextStyle(fontWeight: FontWeight.bold,
                    color: drawerSelectedIndex == 2 ? Colors.white : colors.onSurface)),
          ),
          NavigationDrawerDestination(
            icon: Icon(Icons.cloud_outlined, color: colors.onSurface),
            selectedIcon: const Icon(Icons.cloud, color: Colors.white),
            label: Text('Weather',
                style: TextStyle(fontWeight: FontWeight.bold,
                    color: drawerSelectedIndex == 3 ? Colors.white : colors.onSurface)),
          ),
          NavigationDrawerDestination(
            icon: Icon(Icons.eco_outlined, color: colors.onSurface),
            selectedIcon: const Icon(Icons.eco, color: Colors.white),
            label: Text('Crop Profiles',
                style: TextStyle(fontWeight: FontWeight.bold,
                    color: drawerSelectedIndex == 4 ? Colors.white : colors.onSurface)),
          ),
          NavigationDrawerDestination(
            icon: Icon(Icons.bar_chart_outlined, color: colors.onSurface),
            selectedIcon: const Icon(Icons.bar_chart, color: Colors.white),
            label: Text('Water Usage',
                style: TextStyle(fontWeight: FontWeight.bold,
                    color: drawerSelectedIndex == 5 ? Colors.white : colors.onSurface)),
          ),
          NavigationDrawerDestination(
            icon: Icon(Icons.science_outlined, color: colors.onSurface),
            selectedIcon: const Icon(Icons.science, color: Colors.white),
            label: Text('Fertigation',
                style: TextStyle(fontWeight: FontWeight.bold,
                    color: drawerSelectedIndex == 6 ? Colors.white : colors.onSurface)),
          ),
          NavigationDrawerDestination(
            icon: Icon(Icons.notifications_outlined, color: colors.onSurface),
            selectedIcon: const Icon(Icons.notifications, color: Colors.white),
            label: Text('Alerts',
                style: TextStyle(fontWeight: FontWeight.bold,
                    color: drawerSelectedIndex == 7 ? Colors.white : colors.onSurface)),
          ),
          NavigationDrawerDestination(
            icon: Icon(Icons.settings_outlined, color: colors.onSurface),
            selectedIcon: const Icon(Icons.settings, color: Colors.white),
            label: Text('Settings',
                style: TextStyle(fontWeight: FontWeight.bold,
                    color: drawerSelectedIndex == 8 ? Colors.white : colors.onSurface)),
          ),
        ],
      ),

      body: child,

      bottomNavigationBar: Container(
        color: Theme.of(context).scaffoldBackgroundColor,
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
        child: Row(
          children: [
            _BottomNavItem(label: 'Home',     icon: Icons.home_outlined,              selectedIcon: Icons.home,              selected: currentIndex == 0, onTap: () => context.go('/')),
            _BottomNavItem(label: 'Irrigate', icon: Icons.water_drop_outlined,        selectedIcon: Icons.water_drop,        selected: currentIndex == 1, onTap: () => context.go('/irrigation')),
            _BottomNavItem(label: 'Pump',     icon: Icons.power_settings_new_outlined, selectedIcon: Icons.power_settings_new, selected: currentIndex == 2, onTap: () => context.go('/pump')),
            _BottomNavItem(label: 'Weather',  icon: Icons.cloud_outlined,             selectedIcon: Icons.cloud,             selected: currentIndex == 3, onTap: () => context.go('/weather')),
            _BottomNavItem(label: 'Settings', icon: Icons.settings_outlined,          selectedIcon: Icons.settings,          selected: currentIndex == 4, onTap: () => context.go('/settings')),
          ],
        ),
      ),
    );
  }
}

class _BottomNavItem extends StatelessWidget {
  const _BottomNavItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
              decoration: BoxDecoration(
                color: selected ? AppTheme.deepLeaf : Colors.transparent,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(selected ? selectedIcon : icon,
                      color: selected ? Colors.white : colors.onSurface),
                  const SizedBox(height: 4),
                  Text(label,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: selected ? Colors.white : colors.onSurface)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
