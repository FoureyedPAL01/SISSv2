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
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(
        value,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
