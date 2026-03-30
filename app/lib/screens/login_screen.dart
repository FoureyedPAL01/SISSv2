// lib/screens/login_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/notification_service.dart';
import '../widgets/double_back_press_wrapper.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final _signInIdentifierController = TextEditingController();
  final _signInPasswordController = TextEditingController();
  final _signUpEmailController = TextEditingController();
  final _signUpUsernameController = TextEditingController();
  final _signUpPasswordController = TextEditingController();
  final _scrollController = ScrollController();

  bool _isLoading = false;
  String? _errorMessage;
  bool _obscureSignIn = true;
  bool _obscureSignUp = true;

  ColorScheme get _colors => Theme.of(context).colorScheme;
  Color get _bg => Theme.of(context).scaffoldBackgroundColor;
  Color get _text => _colors.onSurface;
  Color get _button => _colors.primary;

  TextStyle _ts({
    double size = 15,
    FontWeight weight = FontWeight.bold,
    Color? color,
  }) => TextStyle(
    fontFamily: 'Poppins',
    fontSize: size,
    fontWeight: weight,
    color: color ?? _text,
    decoration: TextDecoration.none,
  );

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        setState(() {
          _errorMessage = null;
          _obscureSignIn = true;
          _obscureSignUp = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _signInIdentifierController.dispose();
    _signInPasswordController.dispose();
    _signUpEmailController.dispose();
    _signUpUsernameController.dispose();
    _signUpPasswordController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // Auto-detects email vs username by checking for '@'
  Future<void> _signIn() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final raw = _signInIdentifierController.text.trim();
      final isEmail = raw.contains('@');
      String email = raw;

      if (!isEmail) {
        final rows = await Supabase.instance.client
            .from('users')
            .select('email')
            .eq('username', raw)
            .limit(1);
        if (rows.isEmpty || rows[0]['email'] == null) {
          setState(
            () => _errorMessage = 'No account found with that username.',
          );
          return;
        }
        email = rows[0]['email'] as String;
      }

      await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: _signInPasswordController.text,
      );
      await NotificationService.onUserLogin();
    } on AuthException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (_) {
      setState(() => _errorMessage = 'Unexpected error. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signUp() async {
    final email = _signUpEmailController.text.trim();
    final username = _signUpUsernameController.text.trim();
    final password = _signUpPasswordController.text;

    if (username.isEmpty) {
      setState(() => _errorMessage = 'Please enter a username.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final existing = await Supabase.instance.client
          .from('users')
          .select('id')
          .eq('username', username)
          .limit(1);
      if (existing.isNotEmpty) {
        setState(() => _errorMessage = 'That username is already taken.');
        return;
      }

      final res = await Supabase.instance.client.auth.signUp(
        email: email,
        password: password,
      );

      if (res.user != null && res.session != null) {
        await Supabase.instance.client
            .from('users')
            .update({'username': username})
            .eq('id', res.user!.id);
        await NotificationService.onUserLogin();
      }

      if (res.user != null && res.session == null) {
        setState(
          () => _errorMessage = 'Check your email to confirm your account.',
        );
      }
    } on AuthException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (_) {
      setState(() => _errorMessage = 'Unexpected error. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool isPassword = false,
    bool obscure = false,
    VoidCallback? onToggleObscure,
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: _ts(
            size: 12,
            weight: FontWeight.w600,
            color: _text.withValues(alpha: 0.55),
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: isPassword && obscure,
          keyboardType:
              keyboardType ??
              (isPassword
                  ? TextInputType.visiblePassword
                  : TextInputType.emailAddress),
          style: _ts(size: 15, weight: FontWeight.w500),
          cursorColor: _button,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: _ts(
              size: 14,
              weight: FontWeight.w400,
              color: _text.withValues(alpha: 0.28),
            ),
            prefixIcon: Icon(
              icon,
              color: _text.withValues(alpha: 0.38),
              size: 20,
            ),
            suffixIcon: isPassword
                ? IconButton(
                    icon: Icon(
                      obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color: _text.withValues(alpha: 0.38),
                      size: 20,
                    ),
                    onPressed: onToggleObscure,
                  )
                : null,
            filled: true,
            fillColor: _colors.surfaceContainerHighest.withValues(alpha: 0.35),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: _text.withValues(alpha: 0.08),
                width: 1,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: _button, width: 1.8),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 15,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorBox() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: _colors.errorContainer,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: _colors.error.withValues(alpha: 0.3)),
    ),
    child: Row(
      children: [
        Icon(Icons.error_outline_rounded, color: _colors.error, size: 17),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _errorMessage!,
            style: _ts(
              size: 13,
              weight: FontWeight.w500,
              color: _colors.onErrorContainer,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _buildPrimaryButton(
    String label,
    IconData icon,
    VoidCallback? onPressed,
  ) => SizedBox(
    width: double.infinity,
    child: FilledButton.icon(
      onPressed: onPressed,
      icon: _isLoading
          ? SizedBox(
              width: 17,
              height: 17,
              child: CircularProgressIndicator(
                color: _colors.onPrimary,
                strokeWidth: 2.2,
              ),
            )
          : Icon(icon, size: 19),
      label: Text(label, style: _ts(size: 15, color: _colors.onPrimary)),
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
  );

  Widget _buildSignInTab() => Padding(
    padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildField(
          controller: _signInIdentifierController,
          label: 'Email or Username',
          hint: 'you@example.com  or  your_username',
          icon: Icons.account_circle_outlined,
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 14),
        _buildField(
          controller: _signInPasswordController,
          label: 'Password',
          hint: 'Enter your password',
          icon: Icons.lock_person_outlined,
          isPassword: true,
          obscure: _obscureSignIn,
          onToggleObscure: () =>
              setState(() => _obscureSignIn = !_obscureSignIn),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 12),
          _buildErrorBox(),
        ],
        const SizedBox(height: 22),
        _buildPrimaryButton(
          'Sign In',
          Icons.login_rounded,
          _isLoading ? null : _signIn,
        ),
      ],
    ),
  );

  Widget _buildSignUpTab() => Padding(
    padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildField(
          controller: _signUpEmailController,
          label: 'Email address',
          hint: 'you@example.com',
          icon: Icons.mail_outline_rounded,
        ),
        const SizedBox(height: 14),
        _buildField(
          controller: _signUpUsernameController,
          label: 'Username',
          hint: 'e.g. john_farmer',
          icon: Icons.badge_outlined,
          keyboardType: TextInputType.text,
        ),
        const SizedBox(height: 14),
        _buildField(
          controller: _signUpPasswordController,
          label: 'Password',
          hint: 'Min. 8 characters',
          icon: Icons.lock_person_outlined,
          isPassword: true,
          obscure: _obscureSignUp,
          onToggleObscure: () =>
              setState(() => _obscureSignUp = !_obscureSignUp),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 12),
          _buildErrorBox(),
        ],
        const SizedBox(height: 22),
        _buildPrimaryButton(
          'Create Account',
          Icons.person_add_rounded,
          _isLoading ? null : _signUp,
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return DoubleBackPressWrapper(
      child: Scaffold(
        backgroundColor: _bg,
        body: SafeArea(
          child: Scrollbar(
            controller: _scrollController,
            thumbVisibility: false,
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 48),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    children: [
                      // App icon
                      ClipOval(
                        child: Image.asset(
                          'assets/icon/master.png',
                          width: 58,
                          height: 58,
                          fit: BoxFit.cover,
                        ),
                      ),

                      const SizedBox(height: 32),

                      // Flush card
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TabBar(
                            controller: _tabController,
                            tabs: const [
                              Tab(text: 'Sign In'),
                              Tab(text: 'Sign Up'),
                            ],
                            labelStyle: const TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                            unselectedLabelStyle: const TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                            labelColor: _text,
                            unselectedLabelColor: _text.withValues(alpha: 0.35),
                            indicatorColor: _button,
                            indicatorWeight: 2.5,
                            dividerColor: _text.withValues(alpha: 0.08),
                            overlayColor: WidgetStateProperty.all(
                              _button.withValues(alpha: 0.06),
                            ),
                          ),
                          AnimatedBuilder(
                            animation: _tabController,
                            builder: (context, _) => IndexedStack(
                              index: _tabController.index,
                              children: [_buildSignInTab(), _buildSignUpTab()],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
