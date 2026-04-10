import 'package:flutter/material.dart';

class DeleteAccountButton extends StatefulWidget {
  final VoidCallback onDelete;
  final bool isLoading;

  const DeleteAccountButton({
    super.key,
    required this.onDelete,
    this.isLoading = false,
  });

  @override
  State<DeleteAccountButton> createState() => _DeleteAccountButtonState();
}

class _DeleteAccountButtonState extends State<DeleteAccountButton> {
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: widget.isLoading
              ? null
              : () => _showDeleteConfirmation(context),
          icon: widget.isLoading
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.delete_forever, color: Colors.white),
          label: const Text(
            'Delete Account',
            style: TextStyle(color: Colors.white),
          ),
          style: FilledButton.styleFrom(
            backgroundColor: colors.error,
            disabledBackgroundColor: colors.error.withValues(alpha: 0.6),
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      ),
    );
  }

  Future<void> _showDeleteConfirmation(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => const _DeleteConfirmDialog(),
    );

    if (confirmed == true) {
      widget.onDelete();
    }
  }
}

class _DeleteConfirmDialog extends StatefulWidget {
  const _DeleteConfirmDialog();

  @override
  State<_DeleteConfirmDialog> createState() => _DeleteConfirmDialogState();
}

class _DeleteConfirmDialogState extends State<_DeleteConfirmDialog> {
  final _confirmController = TextEditingController();
  bool _isButtonEnabled = false;

  @override
  void initState() {
    super.initState();
    _confirmController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _confirmController.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final isEnabled = _confirmController.text.trim().toLowerCase() == 'delete';
    if (isEnabled != _isButtonEnabled) {
      setState(() {
        _isButtonEnabled = isEnabled;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: colors.error),
          const SizedBox(width: 8),
          const Text('Delete Account'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'This action cannot be undone. All your data including devices, sensor readings, and alerts will be permanently deleted.\n',
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.errorContainer,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.error.withValues(alpha: 0.5)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: colors.onErrorContainer,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Type "DELETE" below to confirm',
                    style: TextStyle(
                      color: colors.onErrorContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _confirmController,
            autofocus: true,
            textCapitalization: TextCapitalization.none,
            decoration: const InputDecoration(
              labelText: 'Confirmation',
              hintText: 'Type DELETE',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isButtonEnabled
              ? () => Navigator.of(context).pop(true)
              : null,
          style: FilledButton.styleFrom(
            backgroundColor: colors.error,
            foregroundColor: Colors.white,
            disabledBackgroundColor: colors.error.withValues(alpha: 0.5),
          ),
          child: const Text('Delete Account'),
        ),
      ],
    );
  }
}
