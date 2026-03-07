import 'package:flutter/material.dart';

class StatusBadge extends StatelessWidget {
  final bool isOnline;
  final String? label;

  const StatusBadge({super.key, required this.isOnline, this.label});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isOnline ? colors.primaryContainer : colors.errorContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isOnline ? colors.primary : colors.error,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: isOnline ? colors.primary : colors.error,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label ?? (isOnline ? 'Online' : 'Offline'),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isOnline
                  ? colors.onPrimaryContainer
                  : colors.onErrorContainer,
            ),
          ),
        ],
      ),
    );
  }
}

class DeviceHealthTile extends StatelessWidget {
  final String deviceName;
  final bool isOnline;
  final DateTime? lastSeen;
  final VoidCallback? onRefresh;

  const DeviceHealthTile({
    super.key,
    required this.deviceName,
    required this.isOnline,
    this.lastSeen,
    this.onRefresh,
  });

  String _formatLastSeen() {
    if (lastSeen == null) return 'Unknown';

    final diff = DateTime.now().difference(lastSeen!);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.memory),
      title: Text(deviceName),
      subtitle: Text('Last seen: ${_formatLastSeen()}'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StatusBadge(isOnline: isOnline),
          if (onRefresh != null) ...[
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.refresh, size: 20),
              onPressed: onRefresh,
              tooltip: 'Refresh status',
            ),
          ],
        ],
      ),
    );
  }
}

class ApiConnectivityTile extends StatelessWidget {
  final String serviceName;
  final bool isConnected;

  const ApiConnectivityTile({
    super.key,
    required this.serviceName,
    required this.isConnected,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(
        isConnected ? Icons.cloud_done : Icons.cloud_off,
        color: isConnected ? colors.primary : colors.error,
      ),
      title: Text(serviceName),
      trailing: StatusBadge(
        isOnline: isConnected,
        label: isConnected ? 'Connected' : 'Disconnected',
      ),
    );
  }
}
