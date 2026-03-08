import 'package:flutter/material.dart';

class ReadOnlyTile extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;

  const ReadOnlyTile({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final textColor =
        Theme.of(context).textTheme.headlineMedium?.color ??
            Theme.of(context).colorScheme.onSurface;
    return ListTile(
      leading: Icon(icon, color: textColor),
      title: Text(title, style: TextStyle(color: textColor)),
      subtitle: Text(
        value,
        style: TextStyle(color: textColor),
      ),
    );
  }
}
