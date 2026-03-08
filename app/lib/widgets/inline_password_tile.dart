import 'package:flutter/material.dart';

class InlinePasswordTile extends StatefulWidget {
  final String title;
  final IconData icon;
  final Future<void> Function(String currentPassword, String newPassword) onUpdate;
  final bool isLoading;
  final String? errorMessage;

  const InlinePasswordTile({
    super.key,
    required this.title,
    required this.icon,
    required this.onUpdate,
    this.isLoading = false,
    this.errorMessage,
  });

  @override
  State<InlinePasswordTile> createState() => _InlinePasswordTileState();
}

class _InlinePasswordTileState extends State<InlinePasswordTile> {
  bool _isExpanded = false;
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  String? _localError;
  bool _isSaving = false;

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleUpdate() async {
    final current = _currentPasswordController.text;
    final newPass = _newPasswordController.text;
    final confirm = _confirmPasswordController.text;

    if (current.isEmpty || newPass.isEmpty || confirm.isEmpty) {
      setState(() {
        _localError = 'All fields are required';
      });
      return;
    }

    if (newPass.length < 8) {
      setState(() {
        _localError = 'Password must be at least 8 characters';
      });
      return;
    }

    if (newPass != confirm) {
      setState(() {
        _localError = 'New passwords do not match';
      });
      return;
    }

    setState(() {
      _localError = null;
      _isSaving = true;
    });

    try {
      await widget.onUpdate(current, newPass);
      if (mounted) {
        setState(() {
          _isExpanded = false;
          _currentPasswordController.clear();
          _newPasswordController.clear();
          _confirmPasswordController.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Password updated successfully'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _localError = _extractErrorMessage(e.toString());
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  String _extractErrorMessage(String error) {
    if (error.toLowerCase().contains('invalid login') ||
        error.toLowerCase().contains('invalid credentials')) {
      return 'Current password is incorrect';
    }
    if (error.toLowerCase().contains('same as current')) {
      return 'New password must be different from current password';
    }
    return 'Failed to update password. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    final displayError = _localError ?? widget.errorMessage;
    final sectionColor =
        Theme.of(context).textTheme.headlineMedium?.color ??
            Theme.of(context).colorScheme.onSurface;

    return Column(
      children: [
        ListTile(
          leading: Icon(widget.icon, color: sectionColor),
          title: Text(widget.title, style: TextStyle(color: sectionColor)),
          trailing: widget.isLoading || _isSaving
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  _isExpanded ? Icons.expand_less : Icons.expand_more,
                  color: sectionColor,
                ),
          onTap: widget.isLoading || _isSaving
              ? null
              : () {
                  setState(() {
                    _isExpanded = !_isExpanded;
                  });
                },
        ),
        if (_isExpanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              children: [
                TextField(
                  controller: _currentPasswordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'Current Password',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    errorText: displayError?.contains('incorrect') == true
                        ? displayError
                        : null,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _newPasswordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'New Password',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _confirmPasswordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'Confirm New Password',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    errorText: displayError?.contains('match') == true ||
                            displayError?.contains('characters') == true
                        ? displayError
                        : null,
                  ),
                ),
                if (displayError != null &&
                    !displayError.contains('incorrect') &&
                    !displayError.contains('match') &&
                    !displayError.contains('characters')) ...[
                  const SizedBox(height: 8),
                  Text(
                    displayError,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _isSaving ? null : _handleUpdate,
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Update Password'),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
