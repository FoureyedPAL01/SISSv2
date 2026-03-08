import 'package:flutter/material.dart';
import 'enums.dart';

class ToggleSettingTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final bool value;
  final ValueChanged<bool> onChanged;
  final SaveStatus saveStatus;

  const ToggleSettingTile({
    super.key,
    required this.title,
    this.subtitle,
    required this.icon,
    required this.value,
    required this.onChanged,
    this.saveStatus = SaveStatus.idle,
  });

  @override
  Widget build(BuildContext context) {
    final sectionColor =
        Theme.of(context).textTheme.headlineMedium?.color ??
            Theme.of(context).colorScheme.onSurface;
    return SwitchListTile(
      secondary: _buildLeading(sectionColor),
      title: Text(title, style: TextStyle(color: sectionColor)),
      subtitle: subtitle != null
          ? Text(subtitle!, style: TextStyle(color: sectionColor))
          : null,
      value: value,
      onChanged: saveStatus == SaveStatus.saving ? null : onChanged,
    );
  }

  Widget _buildLeading(Color sectionColor) {
    if (saveStatus == SaveStatus.saving) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: Padding(
          padding: EdgeInsets.all(4),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (saveStatus == SaveStatus.error) {
      return const Icon(Icons.error_outline, color: Colors.red);
    }
    if (saveStatus == SaveStatus.saved) {
      return const Icon(Icons.check_circle, color: Colors.green);
    }
    return Icon(icon, color: sectionColor);
  }
}
