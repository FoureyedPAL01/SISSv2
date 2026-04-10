import 'package:flutter/material.dart';
import 'enums.dart';

class DropdownSettingTile<T> extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;
  final SaveStatus saveStatus;

  const DropdownSettingTile({
    super.key,
    required this.title,
    this.subtitle,
    required this.icon,
    required this.value,
    required this.options,
    required this.onChanged,
    this.saveStatus = SaveStatus.idle,
  });

  @override
  Widget build(BuildContext context) {
    final sectionColor =
        Theme.of(context).textTheme.headlineMedium?.color ??
        Theme.of(context).colorScheme.onSurface;
    return ListTile(
      leading: _buildLeading(sectionColor),
      title: Text(title, style: TextStyle(color: sectionColor)),
      subtitle: subtitle != null
          ? Text(subtitle!, style: TextStyle(color: sectionColor))
          : null,
      trailing: SizedBox(
        width: 140,
        child: SegmentedButton<T>(
          segments: options.entries
              .map((e) => ButtonSegment<T>(value: e.key, label: Text(e.value)))
              .toList(),
          selected: {value},
          onSelectionChanged: saveStatus == SaveStatus.saving
              ? null
              : (selected) {
                  if (selected.isNotEmpty && selected.first != value) {
                    onChanged(selected.first);
                  }
                },
          showSelectedIcon: false,
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            textStyle: const WidgetStatePropertyAll(
              TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
            foregroundColor: WidgetStatePropertyAll(sectionColor),
          ),
        ),
      ),
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
    return Icon(icon, color: sectionColor);
  }
}
