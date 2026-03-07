import 'package:flutter/material.dart';
import 'enums.dart';

class EditableTextTile extends StatefulWidget {
  final String title;
  final String value;
  final IconData icon;
  final String? hintText;
  final String? errorText;
  final ValueChanged<String> onSave;
  final String? Function(String?)? validator;
  final SaveStatus saveStatus;

  const EditableTextTile({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    this.hintText,
    this.errorText,
    required this.onSave,
    this.validator,
    this.saveStatus = SaveStatus.idle,
  });

  @override
  State<EditableTextTile> createState() => _EditableTextTileState();
}

class _EditableTextTileState extends State<EditableTextTile> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  bool _isEditing = false;
  String? _localError;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(EditableTextTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isEditing && widget.value != oldWidget.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus && _isEditing) {
      _save();
    }
    setState(() {
      _isEditing = _focusNode.hasFocus;
    });
  }

  void _save() {
    final value = _controller.text.trim();

    if (widget.validator != null) {
      final error = widget.validator!(value);
      if (error != null) {
        setState(() {
          _localError = error;
        });
        return;
      }
    }

    setState(() {
      _localError = null;
    });

    widget.onSave(value);
  }

  @override
  Widget build(BuildContext context) {
    final hasError = _localError != null ||
        widget.errorText != null ||
        widget.saveStatus == SaveStatus.error;
    final displayError = _localError ?? widget.errorText;

    return ListTile(
      leading: _buildLeading(),
      title: _isEditing
          ? TextField(
              controller: _controller,
              focusNode: _focusNode,
              autofocus: true,
              decoration: InputDecoration(
                labelText: widget.title,
                hintText: widget.hintText,
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                errorText: displayError,
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _save(),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.title,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  widget.value.isEmpty ? 'Tap to set' : widget.value,
                  style: TextStyle(
                    color: widget.value.isEmpty
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
      trailing: _isEditing
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    _controller.text = widget.value;
                    _focusNode.unfocus();
                    setState(() {
                      _isEditing = false;
                      _localError = null;
                    });
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.check),
                  onPressed: widget.saveStatus == SaveStatus.saving ? null : _save,
                ),
              ],
            )
          : Icon(
              Icons.edit,
              color: hasError
                  ? Theme.of(context).colorScheme.error
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
    );
  }

  Widget _buildLeading() {
    if (widget.saveStatus == SaveStatus.saving) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: Padding(
          padding: EdgeInsets.all(4),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (widget.saveStatus == SaveStatus.error) {
      return const Icon(Icons.error_outline, color: Colors.red);
    }
    if (widget.saveStatus == SaveStatus.saved) {
      return const Icon(Icons.check_circle, color: Colors.green);
    }
    return Icon(widget.icon);
  }
}
