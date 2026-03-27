// lib/screens/alerts_screen.dart
//
// Table columns used (public.alerts):
//   id          bigserial
//   device_id   uuid
//   alert_type  text
//   message     text
//   resolved    boolean  (default false)
//   created_at  timestamptz
//
// Design: fetch once on load, store rows in local state, mutate locally
// and persist to Supabase. No stream — no timing conflicts.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import '../providers/app_state_provider.dart';
import '../utils/date_helpers.dart';

// ── Impact classification ─────────────────────────────────────────────────────

enum _Impact { critical, warning, info }

_Impact _classify(String alertType) {
  final t = alertType.toLowerCase();
  if (t.contains('sensor_stuck') ||
      t.contains('no_flow') ||
      t.contains('fault')) {
    return _Impact.critical;
  }
  if (t.contains('pump') ||
      t.contains('wifi') ||
      t.contains('offline') ||
      t.contains('reconnect')) {
    return _Impact.warning;
  }
  return _Impact.info;
}

Color _impactColor(_Impact i) {
  switch (i) {
    case _Impact.critical:
      return const Color(0xFFEF4444);
    case _Impact.warning:
      return const Color(0xFFF59E0B);
    case _Impact.info:
      return const Color(0xFF3B82F6);
  }
}

String _impactLabel(_Impact i) {
  switch (i) {
    case _Impact.critical:
      return 'CRITICAL';
    case _Impact.warning:
      return 'WARNING';
    case _Impact.info:
      return 'INFO';
  }
}

IconData _impactIcon(_Impact i) {
  switch (i) {
    case _Impact.critical:
      return Icons.error_rounded;
    case _Impact.warning:
      return Icons.warning_amber_rounded;
    case _Impact.info:
      return Icons.info_rounded;
  }
}

// ── Time helper removed natively (using DateHelpers) ──────────────────────────

// ── Screen ────────────────────────────────────────────────────────────────────

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  // Single source of truth — managed entirely in local state.
  List<Map<String, dynamic>> _alerts = [];
  bool _loading = true;
  String? _error;
  String? _selectedAlertType;

  @override
  void initState() {
    super.initState();
    // Wait one frame so Provider is available.
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetch());
  }

  // ── Fetch ─────────────────────────────────────────────────────────────────

  Future<void> _fetch() async {
    final deviceId = context.read<AppStateProvider>().deviceId;
    if (deviceId == null) {
      setState(() {
        _loading = false;
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final rows = await Supabase.instance.client
          .from('alerts')
          .select()
          .eq('device_id', deviceId)
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _alerts = List<Map<String, dynamic>>.from(rows);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  // ── Resolve one alert ─────────────────────────────────────────────────────
  // 1. Update local list immediately → UI reflects change at once.
  // 2. Persist to Supabase in background.
  // 3. On failure, revert the local change and show a snackbar.

  Future<void> _resolve(int id) async {
    // Local update.
    final index = _alerts.indexWhere((a) => a['id'] == id);
    if (index == -1) return;

    setState(() {
      _alerts[index] = Map.from(_alerts[index])..['resolved'] = true;
    });

    // Persist.
    try {
      await Supabase.instance.client
          .from('alerts')
          .update({'resolved': true})
          .eq('id', id);
    } catch (e) {
      // Revert.
      if (mounted) {
        setState(() {
          _alerts[index] = Map.from(_alerts[index])..['resolved'] = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not resolve alert. Try again.')),
        );
      }
    }
  }

  // ── Delete all alerts ─────────────────────────────────────────────────────
  // 1. Confirm with user.
  // 2. Snapshot the current list in case we need to revert.
  // 3. Clear local list immediately → UI shows empty state at once.
  // 4. Persist delete to Supabase in background.
  // 5. On failure, restore the snapshot and show a snackbar.

  Future<void> _deleteAll() async {
    final deviceId = context.read<AppStateProvider>().deviceId;
    if (deviceId == null || _alerts.isEmpty) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Clear all alerts?'),
        content: const Text(
          'This permanently deletes every alert for this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Delete all',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;

    // Snapshot for potential rollback.
    final snapshot = List<Map<String, dynamic>>.from(_alerts);

    // Clear locally.
    setState(() => _alerts = []);

    // Persist.
    try {
      await Supabase.instance.client
          .from('alerts')
          .delete()
          .eq('device_id', deviceId);
    } catch (e) {
      // Revert.
      if (mounted) {
        setState(() => _alerts = snapshot);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not delete alerts. Try again.')),
        );
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  List<String> get _availableAlertTypes {
    final types = _alerts
        .map((a) => (a['alert_type'] as String?)?.trim())
        .whereType<String>()
        .where((type) => type.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return types;
  }

  List<Map<String, dynamic>> get _visibleAlerts {
    if (_selectedAlertType == null) {
      return _alerts;
    }
    return _alerts
        .where((a) => (a['alert_type'] as String?) == _selectedAlertType)
        .toList();
  }

  String _formatAlertTypeLabel(String type) {
    return type
        .split('_')
        .where((part) => part.isNotEmpty)
        .map(
          (part) => part[0].toUpperCase() + part.substring(1).toLowerCase(),
        )
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Material(
      type: MaterialType.transparency,
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _buildError(cs)
          : _buildContent(cs),
    );
  }

  Widget _buildError(ColorScheme cs) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.cloud_off_rounded,
            size: 48,
            color: cs.onSurface.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'Could not load alerts.',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: cs.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _fetch,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    ),
  );

  Widget _buildContent(ColorScheme cs) {
    final unreadCount = _alerts.where((a) => a['resolved'] != true).length;
    final visibleAlerts = _visibleAlerts;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header ───────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 16, 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    unreadCount > 0 ? '$unreadCount unresolved' : 'All clear',
                    style: TextStyle(
                      fontSize: 13,
                      color: unreadCount > 0
                          ? cs.error
                          : cs.onSurface.withValues(alpha: 0.45),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              // Refresh
              IconButton(
                onPressed: _fetch,
                icon: const Icon(Icons.refresh_rounded),
                tooltip: 'Refresh',
                color: cs.onSurface.withValues(alpha: 0.5),
              ),
              // Clear all
              if (_alerts.isNotEmpty)
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: cs.error),
                  onPressed: _deleteAll,
                  icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                  label: const Text('Clear all'),
                ),
            ],
          ),
        ),

        // ── Impact legend ─────────────────────────────────────────────────
        if (_alerts.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Row(
              children: [
                _LegendDot(
                  color: _impactColor(_Impact.critical),
                  label: 'Critical',
                ),
                const SizedBox(width: 14),
                _LegendDot(
                  color: _impactColor(_Impact.warning),
                  label: 'Warning',
                ),
                const SizedBox(width: 14),
                _LegendDot(color: _impactColor(_Impact.info), label: 'Info'),
              ],
            ),
          ),

        if (_alerts.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: const Text('All'),
                      selected: _selectedAlertType == null,
                      onSelected: (_) {
                        setState(() => _selectedAlertType = null);
                      },
                    ),
                  ),
                  for (final type in _availableAlertTypes)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(_formatAlertTypeLabel(type)),
                        selected: _selectedAlertType == type,
                        onSelected: (_) {
                          setState(() {
                            _selectedAlertType =
                                _selectedAlertType == type ? null : type;
                          });
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),

        const Divider(height: 1),

        // ── List / empty ──────────────────────────────────────────────────
        Expanded(
          child: _alerts.isEmpty
              ? const _EmptyState()
              : visibleAlerts.isEmpty
              ? _FilteredEmptyState(
                  selectedLabel: _formatAlertTypeLabel(_selectedAlertType!),
                  onClearFilter: () {
                    setState(() => _selectedAlertType = null);
                  },
                )
              : RefreshIndicator(
                  onRefresh: _fetch,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    itemCount: visibleAlerts.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final a = visibleAlerts[i];
                      final resolved = a['resolved'] == true;
                      final type = (a['alert_type'] as String?) ?? 'alert';
                      final dt = a['created_at'] != null
                          ? DateTime.tryParse(
                              a['created_at'] as String,
                            )?.toLocal()
                          : null;

                      return _AlertTile(
                        alertType: type,
                        message: (a['message'] as String?) ?? '',
                        timeAgo: dt != null ? DateHelpers.timeAgoShort(dt) : '',
                        impact: _classify(type),
                        resolved: resolved,
                        onResolve: resolved
                            ? null
                            : () => _resolve(a['id'] as int),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}

// ── Alert tile ────────────────────────────────────────────────────────────────

class _AlertTile extends StatelessWidget {
  final String alertType;
  final String message;
  final String timeAgo;
  final _Impact impact;
  final bool resolved;
  final VoidCallback? onResolve;

  const _AlertTile({
    required this.alertType,
    required this.message,
    required this.timeAgo,
    required this.impact,
    required this.resolved,
    this.onResolve,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = resolved
        ? cs.onSurface.withValues(alpha: 0.25)
        : _impactColor(impact);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      decoration: BoxDecoration(
        color: resolved
            ? cs.surfaceContainerHighest.withValues(alpha: 0.35)
            : cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: resolved
              ? cs.onSurface.withValues(alpha: 0.08)
              : _impactColor(impact).withValues(alpha: 0.4),
          width: resolved ? 1 : 1.5,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Impact icon
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              resolved
                  ? Icons.check_circle_outline_rounded
                  : _impactIcon(impact),
              size: 18,
              color: accent,
            ),
          ),
          const SizedBox(width: 12),

          // Text
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _impactLabel(impact),
                        style: TextStyle(
                          fontSize: 9,
                          letterSpacing: 0.8,
                          fontWeight: FontWeight.bold,
                          color: accent,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        alertType.replaceAll('_', ' '),
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurface.withValues(alpha: 0.4),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: TextStyle(
                    fontSize: 14,
                    color: resolved
                        ? cs.onSurface.withValues(alpha: 0.38)
                        : cs.onSurface,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  resolved ? 'Resolved · $timeAgo' : timeAgo,
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurface.withValues(alpha: 0.35),
                  ),
                ),
              ],
            ),
          ),

          // Resolve button
          if (onResolve != null) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onResolve,
              child: Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: _impactColor(impact).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _impactColor(impact).withValues(alpha: 0.3),
                  ),
                ),
                child: Icon(
                  Icons.check_rounded,
                  size: 16,
                  color: _impactColor(impact),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Legend dot ────────────────────────────────────────────────────────────────

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.notifications_none_rounded,
            size: 64,
            color: cs.onSurface.withValues(alpha: 0.18),
          ),
          const SizedBox(height: 16),
          Text(
            'No alerts',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: cs.onSurface.withValues(alpha: 0.45),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Everything looks good.',
            style: TextStyle(
              fontSize: 14,
              color: cs.onSurface.withValues(alpha: 0.3),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilteredEmptyState extends StatelessWidget {
  final String selectedLabel;
  final VoidCallback onClearFilter;

  const _FilteredEmptyState({
    required this.selectedLabel,
    required this.onClearFilter,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.filter_list_off_rounded,
              size: 56,
              color: cs.onSurface.withValues(alpha: 0.2),
            ),
            const SizedBox(height: 16),
            Text(
              'No $selectedLabel alerts',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: cs.onSurface.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Try another alert type or clear the filter.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: cs.onSurface.withValues(alpha: 0.35),
              ),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: onClearFilter,
              icon: const Icon(Icons.filter_alt_off_rounded),
              label: const Text('Clear filter'),
            ),
          ],
        ),
      ),
    );
  }
}
