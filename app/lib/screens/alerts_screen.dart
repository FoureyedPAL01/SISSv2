// lib/screens/alerts_screen.dart
//
// Changes from the previous version:
//  1. Header shows "Alerts" title, a red unread-count badge, and a "Clear All"
//     button that permanently deletes all alerts for this device.
//  2. Filter tab row: All | Info | Warning | Error — filters on the
//     existing `severity` column (values: 'info', 'warning', 'error').
//  3. "Unread only" toggle — when active, hides rows where is_read = true.
//  4. Alerts are grouped under date headers (e.g. "3/9/2026").
//  5. Tapping a card calls markAsRead(), setting is_read = true in Supabase.
//  6. Each card shows: severity icon, message, relative time, severity chip.
//  7. Real-time stream keeps the list live without a manual refresh.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import '../providers/app_state_provider.dart';
import '../theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Severity helpers
// ─────────────────────────────────────────────────────────────────────────────

// Maps the `severity` text value from Supabase to display properties.
// Supabase stores lowercase: 'info', 'warning', 'error'.
enum _Severity { info, warning, error, unknown }

_Severity _parseSeverity(String? raw) {
  switch (raw?.toLowerCase()) {
    case 'info':    return _Severity.info;
    case 'warning': return _Severity.warning;
    case 'error':   return _Severity.error;
    default:        return _Severity.unknown;
  }
}

// Label shown in the chip and the filter tab
String _severityLabel(_Severity s) {
  switch (s) {
    case _Severity.info:    return 'Info';
    case _Severity.warning: return 'Warning';
    case _Severity.error:   return 'Error';
    case _Severity.unknown: return 'Unknown';
  }
}

// Chip background colour
Color _severityColor(_Severity s) {
  switch (s) {
    case _Severity.info:    return const Color(0xFF3B82F6); // blue
    case _Severity.warning: return const Color(0xFFF59E0B); // amber
    case _Severity.error:   return const Color(0xFFEF4444); // red
    case _Severity.unknown: return Colors.grey;
  }
}

// Icon shown on the left of the card
PhosphorIconData _severityIcon(_Severity s) {
  switch (s) {
    case _Severity.info:    return PhosphorIcons.info();
    case _Severity.warning: return PhosphorIcons.warning();
    case _Severity.error:   return PhosphorIcons.xCircle();
    case _Severity.unknown: return PhosphorIcons.bell();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Relative time helper  ("10 minutes ago", "about 1 hour ago", …)
// ─────────────────────────────────────────────────────────────────────────────
String _timeAgo(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inSeconds < 60)  return 'just now';
  if (diff.inMinutes < 60)  return '${diff.inMinutes} minutes ago';
  if (diff.inHours   < 2)   return 'about 1 hour ago';
  if (diff.inHours   < 24)  return 'about ${diff.inHours} hours ago';
  if (diff.inDays    < 2)   return 'yesterday';
  return '${diff.inDays} days ago';
}

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────
class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  // Stream is created once in initState so it doesn't re-subscribe on rebuild.
  late final Stream<List<Map<String, dynamic>>> _stream;

  // Active filter: null = All, otherwise matches severity string
  String? _severityFilter; // null | 'info' | 'warning' | 'error'

  // When true, only show rows where is_read = false
  bool _unreadOnly = false;

  @override
  void initState() {
    super.initState();
    // Stream all alerts for this device, newest first, no hard limit.
    // Client-side filtering is applied in build() so switching tabs is instant.
    _stream = Supabase.instance.client
        .from('system_alerts')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false);
  }

  // ── Mark a single alert as read ───────────────────────────────────────────
  // Called when the user taps a card.
  Future<void> _markAsRead(int alertId) async {
    await Supabase.instance.client
        .from('system_alerts')
        .update({'is_read': true})
        .eq('id', alertId);
    // The stream will emit the updated row automatically.
  }

  // ── Delete all alerts for this device ────────────────────────────────────
  // Called by the "Clear All" button. Shows a confirmation dialog first.
  Future<void> _clearAll(String deviceId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Clear All Alerts'),
        content: const Text(
          'This will permanently delete all alerts. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(context, rootNavigator: true).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(context, rootNavigator: true).pop(true),
            child: Text(
              'Delete All',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await Supabase.instance.client
          .from('system_alerts')
          .delete()
          .eq('device_id', deviceId);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final colors    = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final deviceId  = context.watch<AppStateProvider>().deviceId;

    return Scaffold(
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _stream,
        builder: (context, snapshot) {
          // ── Loading ──────────────────────────────────────────────────────
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          // ── Error ────────────────────────────────────────────────────────
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Error: ${snapshot.error}',
                style: TextStyle(color: colors.error),
              ),
            );
          }

          // ── Filter: only show alerts for this device ──────────────────
          // The stream returns all rows the RLS policy allows; we additionally
          // filter by deviceId to be safe when there are multiple devices.
          final all = (snapshot.data ?? []).where((a) {
            if (deviceId != null && a['device_id'] != deviceId) return false;
            return true;
          }).toList();

          // Count unread across all severity types (for the badge)
          final unreadCount = all.where((a) => a['is_read'] != true).length;

          // Apply tab filter
          final filtered = all.where((a) {
            if (_severityFilter != null &&
                a['severity']?.toString().toLowerCase() != _severityFilter) {
              return false;
            }
            if (_unreadOnly && a['is_read'] == true) return false;
            return true;
          }).toList();

          // ── Group by date ─────────────────────────────────────────────
          // Produces a list of mixed items: String (date header) or Map (row).
          final List<dynamic> grouped = [];
          String? lastDate;
          for (final a in filtered) {
            final dt = DateTime.tryParse(a['created_at'] ?? '')?.toLocal();
            final dateStr = dt == null
                ? 'Unknown date'
                : '${dt.month}/${dt.day}/${dt.year}';
            if (dateStr != lastDate) {
              grouped.add(dateStr); // date header
              lastDate = dateStr;
            }
            grouped.add(a);
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Page header ─────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      'Alerts',
                      style: textTheme.headlineMedium?.copyWith(
                        fontFamily: 'GermaniaOne',
                        fontSize:   24,
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Red badge showing unread count (hidden when 0)
                    if (unreadCount > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color:        colors.error,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '$unreadCount',
                          style: const TextStyle(
                            color:      Colors.white,
                            fontSize:   12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),

                    const Spacer(),

                    // Clear All button — only shown when there are alerts
                    if (all.isNotEmpty && deviceId != null)
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: colors.error,
                          side:            BorderSide(color: colors.error),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8,
                          ),
                        ),
                        onPressed: () => _clearAll(deviceId),
                        icon:  Icon(PhosphorIcons.trash(), size: 16),
                        label: const Text('Clear All', style: TextStyle(fontSize: 13)),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 12),
                child: Text(
                  'System notifications & threshold alerts',
                  style: textTheme.bodyMedium,
                ),
              ),

              // ── Filter tabs + Unread toggle ──────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Row(
                  children: [
                    // Segmented filter: All | Info | Warning | Error
                    _FilterTabBar(
                      selected: _severityFilter,
                      onChanged: (v) => setState(() => _severityFilter = v),
                      colors:   colors,
                    ),
                    const SizedBox(width: 10),

                    // Unread only toggle chip
                    GestureDetector(
                      onTap: () => setState(() => _unreadOnly = !_unreadOnly),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: _unreadOnly
                              ? colors.onSurface
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: colors.onSurface.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              PhosphorIcons.bell(),
                              size:  14,
                              color: _unreadOnly
                                  ? colors.surface
                                  : colors.onSurface,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              'Unread only',
                              style: TextStyle(
                                fontSize:   13,
                                color: _unreadOnly
                                    ? colors.surface
                                    : colors.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // ── Alert list ───────────────────────────────────────────────
              Expanded(
                child: filtered.isEmpty
                    ? _buildEmptyState(colors, unreadCount)
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        itemCount: grouped.length,
                        itemBuilder: (_, i) {
                          final item = grouped[i];

                          // Date header
                          if (item is String) {
                            return Padding(
                              padding: const EdgeInsets.only(
                                top: 16, bottom: 8,
                              ),
                              child: Text(
                                item,
                                style: TextStyle(
                                  color:      colors.onSurface,
                                  fontWeight: FontWeight.bold,
                                  fontSize:   13,
                                ),
                              ),
                            );
                          }

                          // Alert card
                          final alert    = item as Map<String, dynamic>;
                          final severity = _parseSeverity(
                            alert['severity'] as String?,
                          );
                          final isRead   = alert['is_read'] == true;
                          final dt       = DateTime.tryParse(
                            alert['created_at'] ?? '',
                          )?.toLocal();

                          return _AlertCard(
                            severity:  severity,
                            message:   alert['message'] as String? ??
                                       alert['alert_type'] as String? ??
                                       'No message',
                            timeAgo:   dt != null ? _timeAgo(dt) : '',
                            isRead:    isRead,
                            colors:    colors,
                            onTap: isRead
                                ? null
                                : () => _markAsRead(alert['id'] as int),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── Empty state ───────────────────────────────────────────────────────────
  Widget _buildEmptyState(ColorScheme colors, int totalUnread) {
    // Differentiate between "no alerts at all" vs "none match current filter"
    final bool isFiltered = _severityFilter != null || _unreadOnly;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isFiltered
                ? PhosphorIcons.funnel()
                : PhosphorIcons.checkCircle(),
            size:  56,
            color: AppTheme.teal,
          ),
          const SizedBox(height: 12),
          Text(
            isFiltered
                ? 'No alerts match this filter'
                : 'All clear — system running smoothly',
            style: TextStyle(
              fontSize:   15,
              color:      colors.onSurface,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (isFiltered) ...[
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => setState(() {
                _severityFilter = null;
                _unreadOnly     = false;
              }),
              child: const Text('Clear filters'),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Filter tab bar: All | Info | Warning | Error
// Selected tab gets a filled background; others are outlined.
// ─────────────────────────────────────────────────────────────────────────────
class _FilterTabBar extends StatelessWidget {
  final String? selected;       // null = All
  final ValueChanged<String?> onChanged;
  final ColorScheme colors;

  const _FilterTabBar({
    required this.selected,
    required this.onChanged,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    // Tabs: label → filter value (null = All)
    final tabs = <String, String?>{
      'All':     null,
      'Info':    'info',
      'Warning': 'warning',
      'Error':   'error',
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: tabs.entries.map((e) {
        final isSelected = selected == e.value;

        // "All" tab uses the primary colour when selected
        // Severity tabs use their own colour when selected
        Color activeBg;
        if (e.value == null) {
          activeBg = AppTheme.teal;
        } else {
          activeBg = _severityColor(_parseSeverity(e.value));
        }

        return GestureDetector(
          onTap: () => onChanged(e.value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.only(right: 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: isSelected ? activeBg : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isSelected
                    ? activeBg
                    : colors.onSurface.withValues(alpha: 0.25),
              ),
            ),
            child: Text(
              e.key,
              style: TextStyle(
                fontSize:   13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color:      isSelected ? Colors.white : colors.onSurface,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Individual alert card
// Unread cards have a slightly stronger background tint.
// Read cards are more muted.
// ─────────────────────────────────────────────────────────────────────────────
class _AlertCard extends StatelessWidget {
  final _Severity severity;
  final String    message;
  final String    timeAgo;
  final bool      isRead;
  final ColorScheme colors;
  final VoidCallback? onTap; // null when already read

  const _AlertCard({
    required this.severity,
    required this.message,
    required this.timeAgo,
    required this.isRead,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final sColor = _severityColor(severity);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          // Unread: slightly tinted; Read: plain surface
          color: isRead
              ? colors.surface
              : colors.surface.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isRead
                ? colors.onSurface.withValues(alpha: 0.1)
                : sColor.withValues(alpha: 0.3),
            width: isRead ? 1 : 1.5,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Severity icon ──────────────────────────────────────────────
            Container(
              width:  36,
              height: 36,
              decoration: BoxDecoration(
                color:        sColor.withValues(alpha: isRead ? 0.1 : 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                _severityIcon(severity),
                color: sColor.withValues(alpha: isRead ? 0.5 : 1.0),
                size:  18,
              ),
            ),
            const SizedBox(width: 12),

            // ── Message + time ─────────────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message,
                    style: TextStyle(
                      color: isRead
                          ? colors.onSurface.withValues(alpha: 0.5)
                          : colors.onSurface,
                      fontSize:   14,
                      fontWeight:
                          isRead ? FontWeight.normal : FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Text(
                        timeAgo,
                        style: TextStyle(
                          color:    colors.onSurface.withValues(alpha: 0.4),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Severity chip
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: sColor.withValues(
                            alpha: isRead ? 0.08 : 0.15,
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _severityLabel(severity),
                          style: TextStyle(
                            color:      sColor.withValues(
                              alpha: isRead ? 0.5 : 1.0,
                            ),
                            fontSize:   11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
