import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../widgets/double_back_press_wrapper.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final bgColor = Theme.of(context).scaffoldBackgroundColor;

    final items = [
      _MoreItem(icon: Icons.person, label: 'Profile', route: '/profile'),
      _MoreItem(
        icon: Icons.water_drop,
        label: 'Irrigation History',
        route: '/irrigation',
      ),
      _MoreItem(icon: Icons.notifications, label: 'Alerts', route: '/alerts'),
      _MoreItem(icon: Icons.bar_chart, label: 'Water Usage', route: '/water'),
      _MoreItem(
        icon: Icons.science,
        label: 'Fertigation',
        route: '/fertigation',
      ),
      _MoreItem(
        icon: Icons.devices,
        label: 'Device Management',
        route: '/device',
      ),
      _MoreItem(icon: Icons.tune, label: 'Preferences', route: '/preferences'),
      _MoreItem(icon: Icons.settings, label: 'Settings', route: '/settings'),
    ];

    return DoubleBackPressWrapper(
      child: Material(
        type: MaterialType.transparency,
        child: Container(
          color: bgColor,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  color: colors.surfaceContainerHighest,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ClipOval(
                        child: Image.asset(
                          'assets/icon/RootSync.png',
                          width: 88,
                          height: 88,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'RootSync',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: colors.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Divider(
                  height: 1,
                  thickness: 1,
                  color: colors.outline.withValues(alpha: 0.3),
                ),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate((context, i) {
                  if (i.isOdd) {
                    return Divider(
                      height: 1,
                      indent: 56,
                      color: colors.outline.withValues(alpha: 0.3),
                    );
                  }

                  final item = items[i ~/ 2];
                  return ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: colors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(item.icon, color: colors.primary, size: 20),
                    ),
                    title: Text(
                      item.label,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    trailing: Icon(
                      Icons.chevron_right,
                      color: colors.onSurface.withValues(alpha: 0.35),
                    ),
                    onTap: () => context.go(item.route),
                  );
                }, childCount: items.length * 2 - 1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MoreItem {
  final IconData icon;
  final String label;
  final String route;
  const _MoreItem({
    required this.icon,
    required this.label,
    required this.route,
  });
}
