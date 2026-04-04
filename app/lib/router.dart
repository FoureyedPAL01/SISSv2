import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'providers/app_state_provider.dart';
import 'screens/alerts_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/device_choice_screen.dart';
import 'screens/device_management_screen.dart';
import 'screens/fertigation_screen.dart';
import 'screens/irrigation_screen.dart';
import 'screens/link_device_screen.dart';
import 'screens/login_screen.dart';
import 'screens/more_screen.dart';
import 'screens/preferences_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/water_usage_screen.dart';
import 'screens/weather_screen.dart';
import 'screens/crop_profiles_screen.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'root',
);

final GlobalKey<NavigatorState> _shellNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'shell',
);

GlobalKey<NavigatorState> get rootNavigatorKey => _rootNavigatorKey;

GoRouter? _router;
_RouterRefreshListenable? _routerRefreshListenable;

class _RouterRefreshListenable extends ChangeNotifier {
  late final StreamSubscription<dynamic> _authSub;
  final AppStateProvider _appState;

  _RouterRefreshListenable(Stream<dynamic> authStream, this._appState) {
    _authSub = authStream.listen((_) => notifyListeners());
    _appState.addListener(notifyListeners);
  }

  @override
  void dispose() {
    _authSub.cancel();
    _appState.removeListener(notifyListeners);
    super.dispose();
  }
}

GoRouter createRouter(AppStateProvider appState) {
  if (_router != null) return _router!;

  _routerRefreshListenable = _RouterRefreshListenable(
    Supabase.instance.client.auth.onAuthStateChange,
    appState,
  );

  _router = GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/',
    refreshListenable: _routerRefreshListenable,
    redirect: (BuildContext context, GoRouterState state) {
      final session = Supabase.instance.client.auth.currentSession;
      final isOnLogin = state.matchedLocation == '/login';
      final isOnLink = state.matchedLocation == '/link-device';
      final hasDevice = appState.hasDevice;

      if (session == null && !isOnLogin) return '/login';

      if (session != null && isOnLogin) {
        return hasDevice ? '/' : '/link-device';
      }

      if (session != null && !hasDevice && !isOnLink) return '/link-device';
      if (session != null && hasDevice && isOnLink) return '/';

      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, _) => const LoginScreen(),
      ),
      GoRoute(
        path: '/link-device',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, _) => const LinkDeviceScreen(),
      ),
      GoRoute(
        path: '/device-choice',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, _) => const DeviceChoiceScreen(),
      ),
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (context, state, child) => AppLayoutScaffold(child: child),
        routes: [
          GoRoute(path: '/', builder: (_, _) => const DashboardScreen()),
          GoRoute(path: '/weather', builder: (_, _) => const WeatherScreen()),
          GoRoute(
            path: '/crops',
            builder: (_, _) => const CropProfilesScreen(),
          ),
          GoRoute(path: '/more', builder: (_, _) => const MoreScreen()),
          GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
          GoRoute(
            path: '/preferences',
            builder: (_, _) => const PreferencesScreen(),
          ),
          GoRoute(
            path: '/device',
            builder: (_, _) => const DeviceManagementScreen(),
          ),
          GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
          GoRoute(
            path: '/irrigation',
            builder: (_, _) => const IrrigationScreen(),
          ),
          GoRoute(path: '/alerts', builder: (_, _) => const AlertsScreen()),
          GoRoute(path: '/water', builder: (_, _) => const WaterUsageScreen()),
          GoRoute(
            path: '/fertigation',
            builder: (_, _) => const FertigationScreen(),
          ),
        ],
      ),
    ],
  );

  return _router!;
}

void disposeRouter() {
  _routerRefreshListenable?.dispose();
  _routerRefreshListenable = null;
  _router = null;
}

const _moreRoutes = [
  '/profile',
  '/irrigation',
  '/water',
  '/fertigation',
  '/preferences',
  '/device',
  '/settings',
];

bool _isMoreRoute(String location) =>
    _moreRoutes.any((r) => location.startsWith(r));

class AppLayoutScaffold extends StatelessWidget {
  const AppLayoutScaffold({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final String location = GoRouterState.of(context).uri.path;
    final colors = Theme.of(context).colorScheme;

    if (_isMoreRoute(location)) {
      return _MoreLayout(child: child);
    }

    if (location == '/alerts') {
      return _AlertsShell(child: child);
    }

    final int currentIndex;
    if (location == '/') {
      currentIndex = 0;
    } else if (location.startsWith('/crops')) {
      currentIndex = 1;
    } else if (location.startsWith('/weather')) {
      currentIndex = 2;
    } else {
      currentIndex = 3;
    }

    final String appBarTitle;
    if (location == '/') {
      appBarTitle = 'Dashboard';
    } else if (location.startsWith('/crops')) {
      appBarTitle = 'Crop Profiles';
    } else if (location.startsWith('/weather')) {
      appBarTitle = 'Weather';
    } else if (location.startsWith('/irrigation')) {
      appBarTitle = 'Irrigation';
    } else if (location.startsWith('/water')) {
      appBarTitle = 'Water Usage';
    } else if (location.startsWith('/fertigation')) {
      appBarTitle = 'Fertigation';
    } else if (location.startsWith('/alerts')) {
      appBarTitle = 'Alerts';
    } else if (location.startsWith('/settings')) {
      appBarTitle = 'Settings';
    } else if (location.startsWith('/profile')) {
      appBarTitle = 'Profile';
    } else if (location.startsWith('/preferences')) {
      appBarTitle = 'Preferences';
    } else if (location.startsWith('/device')) {
      appBarTitle = 'Device Management';
    } else if (location.startsWith('/more')) {
      appBarTitle = 'More';
    } else {
      appBarTitle = 'RootSync';
    }

    return Scaffold(
      backgroundColor: colors.surfaceContainerHighest,
      appBar: AppBar(
        title: Text(
          appBarTitle,
          style: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 20,
            color: colors.onSurface,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          if (location != '/more' && location != '/alerts')
            IconButton(
              icon: Icon(Icons.warning_amber_rounded, color: colors.onSurface),
              onPressed: () => context.go('/alerts'),
              tooltip: 'Alerts',
            ),
          const SizedBox(width: 4),
          if (location != '/more')
            IconButton(
              icon: Icon(Icons.settings_outlined, color: colors.onSurface),
              onPressed: () => context.go('/settings'),
              tooltip: 'Settings',
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: child,
      bottomNavigationBar: Container(
        color: colors.surface,
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
        child: Row(
          children: [
            _BottomNavItem(
              label: 'Home',
              icon: Icons.home_outlined,
              selectedIcon: Icons.home,
              selected: currentIndex == 0,
              onTap: () => context.go('/'),
            ),
            _BottomNavItem(
              label: 'Crops',
              icon: Icons.eco_outlined,
              selectedIcon: Icons.eco,
              selected: currentIndex == 1,
              onTap: () => context.go('/crops'),
            ),
            _BottomNavItem(
              label: 'Weather',
              icon: Icons.cloud_outlined,
              selectedIcon: Icons.cloud,
              selected: currentIndex == 2,
              onTap: () => context.go('/weather'),
            ),
            _BottomNavItem(
              label: 'More',
              icon: Icons.more_horiz_outlined,
              selectedIcon: Icons.more_horiz,
              selected: currentIndex == 3,
              onTap: () => context.go('/more'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlertsShell extends StatelessWidget {
  const _AlertsShell({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: cs.onSurface),
          onPressed: () => context.go('/'),
        ),
        title: Text(
          'Alerts',
          style: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: cs.onSurface,
          ),
        ),
      ),
      body: child,
      bottomNavigationBar: Container(
        color: cs.surface,
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
        child: Row(
          children: [
            _BottomNavItem(
              label: 'Home',
              icon: Icons.home_outlined,
              selectedIcon: Icons.home,
              selected: true,
              onTap: () => context.go('/'),
            ),
            _BottomNavItem(
              label: 'Crops',
              icon: Icons.eco_outlined,
              selectedIcon: Icons.eco,
              selected: false,
              onTap: () => context.go('/crops'),
            ),
            _BottomNavItem(
              label: 'Weather',
              icon: Icons.cloud_outlined,
              selectedIcon: Icons.cloud,
              selected: false,
              onTap: () => context.go('/weather'),
            ),
            _BottomNavItem(
              label: 'More',
              icon: Icons.more_horiz_outlined,
              selectedIcon: Icons.more_horiz,
              selected: false,
              onTap: () => context.go('/more'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MoreLayout extends StatelessWidget {
  const _MoreLayout({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final colors = Theme.of(context).colorScheme;

    final String title;
    if (location.startsWith('/irrigation')) {
      title = 'Irrigation History';
    } else if (location.startsWith('/water')) {
      title = 'Water Usage';
    } else if (location.startsWith('/fertigation')) {
      title = 'Fertigation';
    } else if (location.startsWith('/settings')) {
      title = 'Settings';
    } else if (location.startsWith('/profile')) {
      title = 'Profile';
    } else if (location.startsWith('/preferences')) {
      title = 'Preferences';
    } else if (location.startsWith('/device')) {
      title = 'Device Management';
    } else {
      title = 'More';
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/more'),
          tooltip: 'Back',
        ),
        title: Text(
          title,
          style: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: colors.onSurface,
          ),
        ),
      ),
      body: child,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final Color selectedColor = isDark
        ? colors.onPrimaryContainer
        : colors.onPrimaryContainer;
    final Color unselectedColor = colors.onSurfaceVariant;

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
                color: selected ? colors.primaryContainer : Colors.transparent,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    selected ? selectedIcon : icon,
                    color: selected ? selectedColor : unselectedColor,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: selected ? selectedColor : unselectedColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
