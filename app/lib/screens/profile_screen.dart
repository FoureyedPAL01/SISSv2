import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/app_state_provider.dart';
import '../widgets/settings_section.dart';
import '../widgets/read_only_tile.dart';
import '../widgets/inline_password_tile.dart';
import '../widgets/delete_account_button.dart';
import '../widgets/double_back_press_wrapper.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isEditingUsername = false;
  late TextEditingController _usernameController;
  final FocusNode _usernameFocusNode = FocusNode();
  String? _usernameError;

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _usernameController.text = context.read<AppStateProvider>().username;
    });
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _usernameFocusNode.dispose();
    super.dispose();
  }

  String? _validateUsername(String? value) {
    if (value == null || value.isEmpty) return 'Username is required';
    if (value.length < 3) return 'Username must be at least 3 characters';
    if (value.length > 30) return 'Username must be at most 30 characters';
    final regex = RegExp(r'^[a-zA-Z0-9_]+$');
    if (!regex.hasMatch(value)) return 'Letters, numbers and underscores only';
    return null;
  }

  void _startEditing(String current) {
    setState(() {
      _usernameController.text = current;
      _usernameError = null;
      _isEditingUsername = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _usernameFocusNode.requestFocus();
    });
  }

  Future<void> _saveUsername() async {
    final value = _usernameController.text.trim();
    final error = _validateUsername(value);
    if (error != null) {
      setState(() => _usernameError = error);
      return;
    }
    setState(() => _usernameError = null);
    await context.read<AppStateProvider>().updateUsername(value);
    if (mounted) {
      setState(() => _isEditingUsername = false);
      _usernameFocusNode.unfocus();
    }
  }

  void _cancelEdit(String current) {
    setState(() {
      _usernameController.text = current;
      _usernameError = null;
      _isEditingUsername = false;
    });
    _usernameFocusNode.unfocus();
  }

  Widget _buildUsernameRow(AppStateProvider provider, ColorScheme colors) {
    final labelColor =
        Theme.of(context).textTheme.headlineMedium?.color ?? colors.onSurface;

    if (!_isEditingUsername) {
      return ListTile(
        leading: Icon(Icons.person_rounded, size: 20, color: labelColor),
        title: Text(
          'Username',
          style: TextStyle(fontSize: 12, color: labelColor),
        ),
        subtitle: Text(
          provider.username,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.normal,
            color: labelColor,
          ),
        ),
        trailing: IconButton(
          icon: Icon(Icons.edit_rounded, size: 20, color: labelColor),
          onPressed: () => _startEditing(provider.username),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _usernameController,
            focusNode: _usernameFocusNode,
            decoration: InputDecoration(
              labelText: 'Username',
              errorText: _usernameError,
              border: const OutlineInputBorder(),
              prefixIcon: Icon(Icons.person_rounded, size: 20),
            ),
            onSubmitted: (_) => _saveUsername(),
            textInputAction: TextInputAction.done,
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: provider.isSaving
                    ? null
                    : () => _cancelEdit(provider.username),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: provider.isSaving ? null : _saveUsername,
                icon: provider.isSaving
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colors.onPrimary,
                        ),
                      )
                    : const Icon(Icons.check, size: 18),
                label: Text(provider.isSaving ? 'Saving…' : 'Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _signOut() async {
    await context.read<AppStateProvider>().signOut();
  }

  Future<void> _deleteAccount() async {
    await context.read<AppStateProvider>().deleteAccount();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppStateProvider>();
    final user = Supabase.instance.client.auth.currentUser;
    final colors = Theme.of(context).colorScheme;
    final labelColor =
        Theme.of(context).textTheme.headlineMedium?.color ?? colors.onSurface;

    final display = provider.username.isNotEmpty
        ? provider.username
        : (user?.email ?? '?');
    final initials = display
        .trim()
        .split(RegExp(r'[\s_]+'))
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();

    return DoubleBackPressWrapper(
      child: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 36),
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.08),
              border: Border(
                bottom: BorderSide(
                  color: colors.outline.withValues(alpha: 0.2),
                ),
              ),
            ),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 44,
                  backgroundColor: colors.primary,
                  child: Text(
                    initials,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      fontFamily: 'Poppins',
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  provider.username.isNotEmpty
                      ? provider.username
                      : 'No username set',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: colors.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  user?.email ?? '',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    color: colors.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
          SettingsSection(
            title: 'Account Details',
            leadingIcon: Icon(Icons.badge_rounded, size: 20, color: labelColor),
            children: [
              _buildUsernameRow(provider, colors),
              ReadOnlyTile(
                title: 'Email',
                value: user?.email ?? 'Not logged in',
                icon: Icons.email_rounded,
              ),
            ],
          ),
          SettingsSection(
            title: 'Security',
            leadingIcon: Icon(Icons.lock_rounded, size: 20, color: labelColor),
            children: [
              InlinePasswordTile(
                title: 'Change Password',
                icon: Icons.lock_rounded,
                onUpdate: (current, newPass) =>
                    provider.updatePassword(current, newPass),
                isLoading: provider.isSaving,
                errorMessage: provider.saveError,
              ),
            ],
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: FilledButton.icon(
              onPressed: () => _signOut(),
              style: FilledButton.styleFrom(
                backgroundColor: colors.error.withValues(alpha: 0.85),
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.logout),
              label: const Text('Sign Out'),
            ),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Danger Zone',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: colors.error,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 8),
          DeleteAccountButton(
            onDelete: () => _deleteAccount(),
            isLoading: provider.isSaving,
          ),
        ],
      ),
    );
  }
}
