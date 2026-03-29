import 'dart:io';
import 'package:flutter/material.dart';

class DoubleBackPressWrapper extends StatefulWidget {
  final Widget child;
  final VoidCallback? onExitConfirmed;

  const DoubleBackPressWrapper({
    super.key,
    required this.child,
    this.onExitConfirmed,
  });

  @override
  State<DoubleBackPressWrapper> createState() => _DoubleBackPressWrapperState();
}

class _DoubleBackPressWrapperState extends State<DoubleBackPressWrapper> {
  DateTime? _lastPressedAt;

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid) {
      return widget.child;
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;

        final now = DateTime.now();
        if (_lastPressedAt == null ||
            now.difference(_lastPressedAt!) > const Duration(seconds: 2)) {
          _lastPressedAt = now;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Press back again to exit'),
              duration: Duration(seconds: 2),
            ),
          );
          return;
        }

        if (widget.onExitConfirmed != null) {
          widget.onExitConfirmed!();
        } else {
          exit(0);
        }
      },
      child: widget.child,
    );
  }
}
