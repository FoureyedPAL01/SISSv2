import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import '../providers/app_state_provider.dart';

// ─── Safety limit: auto-stop after this duration ──────────────────────────────
const _kSafetyLimit = Duration(minutes: 2);

class PumpControlScreen extends StatefulWidget {
  const PumpControlScreen({super.key});

  @override
  State<PumpControlScreen> createState() => _PumpControlScreenState();
}

class _PumpControlScreenState extends State<PumpControlScreen> {
  bool _isRunning = false;   // is pump ON right now
  bool _isChanging = false;  // HTTP request in-flight — disable button

  DateTime? _sessionStart;   // when current manual session started
  Duration _elapsed = Duration.zero;

  Timer? _tickTimer;    // updates elapsed every second
  Timer? _safetyTimer;  // fires after 2 min to force-stop

  // ── Computed string from elapsed ─────────────────────────────────────────
  String get _elapsedLabel {
    final s = _elapsed.inSeconds;
    final m = _elapsed.inMinutes;
    return m > 0 ? '${m}m ${s % 60}s' : '${s}s';
  }

  // ── Start counting up ────────────────────────────────────────────────────
  void _startTimers() {
    _sessionStart = DateTime.now();
    _elapsed = Duration.zero;

    // Tick every second to refresh UI
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _elapsed = DateTime.now().difference(_sessionStart!);
      });
    });

    // Safety: force-stop after _kSafetyLimit
    _safetyTimer = Timer(_kSafetyLimit, () async {
      if (!mounted || !_isRunning) return;
      final deviceId = context.read<AppStateProvider>().deviceId;
      if (deviceId != null) {
        await _sendCommand(deviceId, 'pump_off');
      }
      if (mounted) {
        setState(() => _isRunning = false);
        _stopTimers();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Safety limit reached — pump stopped after 2 minutes.'),
            backgroundColor: Color(0xFFF59E0B),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    });
  }

  // ── Cancel both timers ───────────────────────────────────────────────────
  void _stopTimers() {
    _tickTimer?.cancel();
    _safetyTimer?.cancel();
    _tickTimer = null;
    _safetyTimer = null;
  }

  @override
  void dispose() {
    _stopTimers();
    super.dispose();
  }

  // ── Confirmation dialog (reused for start + stop) ─────────────────────────
  Future<bool> _showConfirmDialog({
    required String title,
    required String message,
    required String confirmLabel,
    required Color confirmColor,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Quicksand')),
        content: Text(message,
            style: const TextStyle(fontFamily: 'Quicksand')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: confirmColor),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  // ── Raw HTTP call to backend ──────────────────────────────────────────────
  Future<bool> _sendCommand(String deviceId, String command) async {
    try {
      final url = dotenv.env['PYTHON_BACKEND_URL'] ?? 'http://localhost:8000';
      final response = await http
          .post(
            Uri.parse('$url/api/pump/toggle'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'device_id': deviceId, 'command': command}),
          )
          .timeout(const Duration(seconds: 10));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ── Main toggle logic called by the power button ──────────────────────────
  Future<void> _onButtonPressed(String deviceId) async {
    if (_isChanging) return;

    if (!_isRunning) {
      // ── Start flow ────────────────────────────────────────────────────────
      final confirmed = await _showConfirmDialog(
        title: 'Manual Override',
        message:
            'You are about to start the pump manually.\n'
            'Auto-irrigation logic will be bypassed.\n'
            'The pump will stop automatically after 2 minutes.',
        confirmLabel: 'Start Pump',
        confirmColor: const Color(0xFF2D9D5C),
      );
      if (!confirmed) return;

      setState(() => _isChanging = true);
      final ok = await _sendCommand(deviceId, 'pump_on');
      if (!mounted) return;

      if (ok) {
        setState(() {
          _isRunning = true;
          _isChanging = false;
        });
        _startTimers();
      } else {
        setState(() => _isChanging = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to reach backend. Try again.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } else {
      // ── Stop flow ─────────────────────────────────────────────────────────
      final confirmed = await _showConfirmDialog(
        title: 'Stop Pump',
        message: 'Stop the pump and end the manual override session?',
        confirmLabel: 'Stop Pump',
        confirmColor: const Color(0xFFEE4E4E),
      );
      if (!confirmed) return;

      setState(() => _isChanging = true);
      final ok = await _sendCommand(deviceId, 'pump_off');
      if (!mounted) return;

      _stopTimers();
      setState(() {
        _isRunning = false;
        _isChanging = false;
        _elapsed = Duration.zero;
        _sessionStart = null;
      });

      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Command may not have reached device.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppStateProvider>();
    final deviceId = state.deviceId;
    final flowRate =
        (state.latestSensorData['flow_litres'] as num? ?? 0).toDouble();

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 36),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Screen title ─────────────────────────────────────────────
            Text(
              'Pump Control',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontFamily: 'Bungee',
                    fontSize: 28,
                  ),
            ),
            const SizedBox(height: 20),

            // ── Override banner (visible only while running) ──────────────
            if (_isRunning) ...[
              _OverrideBanner(elapsed: _elapsed, safetyLimit: _kSafetyLimit),
              const SizedBox(height: 12),
            ],

            // ── No device guard ──────────────────────────────────────────
            if (deviceId == null)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Text('No device linked to this account.'),
                ),
              )
            else ...[
              // ── Main control card ────────────────────────────────────
              _PumpControlCard(
                isRunning: _isRunning,
                isChanging: _isChanging,
                elapsed: _elapsed,
                onPressed: () => _onButtonPressed(deviceId),
              ),
              const SizedBox(height: 16),

              // ── Stats row (session runtime + flow rate) ───────────────
              Row(
                children: [
                  Expanded(
                    child: _StatCard(
                      icon: PhosphorIcons.timer(),
                      label: 'Session Runtime',
                      value: _isRunning ? _elapsedLabel : '—',
                      valueColor: _isRunning
                          ? const Color(0xFF2D9D5C)
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatCard(
                      icon: PhosphorIcons.waveform(),
                      label: 'Flow Rate',
                      value: _isRunning
                          ? '${flowRate.toStringAsFixed(1)} L/min'
                          : '—',
                      valueColor: _isRunning
                          ? const Color(0xFF2D9D5C)
                          : null,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Yellow override banner
// ─────────────────────────────────────────────────────────────────────────────
class _OverrideBanner extends StatelessWidget {
  final Duration elapsed;
  final Duration safetyLimit;

  const _OverrideBanner({required this.elapsed, required this.safetyLimit});

  @override
  Widget build(BuildContext context) {
    final remaining = safetyLimit - elapsed;
    final remSec = remaining.inSeconds.clamp(0, safetyLimit.inSeconds);
    final remMin = remSec ~/ 60;
    final remS = remSec % 60;
    final remLabel = remMin > 0 ? '${remMin}m ${remS}s' : '${remS}s';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: Color(0xFFF59E0B), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Manual Override Active',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    fontFamily: 'Quicksand',
                    color: Color(0xFF92400E),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Pump is running manually. Auto-irrigation logic is bypassed.',
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'Quicksand',
                    color: const Color(0xFF92400E).withValues(alpha: 0.8),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Auto-stop in $remLabel',
                  style: const TextStyle(
                    fontSize: 12,
                    fontFamily: 'Quicksand',
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFB45309),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Central power button card
// ─────────────────────────────────────────────────────────────────────────────
class _PumpControlCard extends StatelessWidget {
  final bool isRunning;
  final bool isChanging;
  final Duration elapsed;
  final VoidCallback onPressed;

  const _PumpControlCard({
    required this.isRunning,
    required this.isChanging,
    required this.elapsed,
    required this.onPressed,
  });

  String get _subtitle {
    if (isRunning) {
      final s = elapsed.inSeconds;
      final m = elapsed.inMinutes;
      final label = m > 0 ? '${m}m ${s % 60}s' : '${s}s';
      return 'Running for $label';
    }
    return 'Pump is idle';
  }

  @override
  Widget build(BuildContext context) {
    // Green when running, red when idle
    const colorOn = Color(0xFF2D9D5C);
    const colorOff = Color(0xFFEE4E4E);
    final btnColor = isRunning ? colorOn : colorOff;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        children: [
          // Title
          Text(
            'Pump Control',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Quicksand',
                ),
          ),
          const SizedBox(height: 4),
          // Subtitle — idle / running timer
          Text(
            _subtitle,
            style: TextStyle(
              fontSize: 13,
              fontFamily: 'Quicksand',
              color: isRunning ? colorOn : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 28),

          // Power button with glow
          GestureDetector(
            onTap: isChanging ? null : onPressed,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: btnColor,
                boxShadow: [
                  BoxShadow(
                    color: btnColor.withValues(alpha: isRunning ? 0.45 : 0.25),
                    blurRadius: isRunning ? 28 : 12,
                    spreadRadius: isRunning ? 6 : 2,
                  ),
                ],
              ),
              child: isChanging
                  ? const Center(
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      ),
                    )
                  : const Icon(Icons.power_settings_new_rounded,
                      color: Colors.white, size: 44),
            ),
          ),
          const SizedBox(height: 20),

          // Status dot + label
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isRunning ? colorOn : Colors.transparent,
                  border: isRunning
                      ? null
                      : Border.all(color: Colors.grey.shade400),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                isRunning ? 'PUMP ON' : 'PUMP OFF',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Quicksand',
                  color: isRunning ? colorOn : Colors.grey.shade600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            isRunning ? 'Tap to stop pump' : 'Tap to start pump',
            style: TextStyle(
              fontSize: 12,
              fontFamily: 'Quicksand',
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small stat card (session runtime / flow rate)
// ─────────────────────────────────────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'Quicksand',
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              fontFamily: 'Quicksand',
              color: valueColor ?? Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
