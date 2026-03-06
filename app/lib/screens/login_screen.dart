// lib/screens/login_screen.dart
//
// Uses 'Quicksand' as default font and 'Bungee' for headers
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {

  late TabController _tabController;
  final _emailController    = TextEditingController();
  final _passwordController = TextEditingController();
  final _scrollController   = ScrollController();

  bool _isLoading       = false;
  String? _errorMessage;
  bool _obscurePassword = true;

  bool get _isDarkMode => Theme.of(context).brightness == Brightness.dark;

  // ─── Color Palette ───────────────────────────────────────────────────────────
  // Light
  static const Color _lBg        = Color(0xFFFEF5ED);
  static const Color _lComponent = Color(0xFFF9F7F7);
  static const Color _lText      = Color(0xFF000000);
  static const Color _lButton    = Color(0xFF347433);
  static const Color _lHighlight = Color(0xFF347433);

  // Dark
  static const Color _dBg        = Color(0xFF191919);
  static const Color _dComponent = Color(0xFF2B2B2B);
  static const Color _dFieldInit = Color(0xFFF6F0D7);
  static const Color _dText      = Color(0xFFF5F5F0);
  static const Color _dButton    = Color(0xFF347433);
  static const Color _dHighlight = Color(0xFF059212);
  static const Color _dFieldText = Color(0xFF000000);
  static const Color _sunBorder  = Color(0xFFFFD700);

  // ─── Computed getters ────────────────────────────────────────────────────────
  Color get _bg        => _isDarkMode ? _dBg        : _lBg;
  Color get _component => _isDarkMode ? _dComponent : _lComponent;
  Color get _text      => _isDarkMode ? _dText      : _lText;
  Color get _button    => _isDarkMode ? _dButton    : _lButton;
  Color get _highlight => _isDarkMode ? _dHighlight : _lHighlight;
  Color get _fieldFill => _isDarkMode ? _dFieldInit : _lComponent;
  Color get _fieldText => _isDarkMode ? _dFieldText : _lText;
  Color get _border    => _text.withValues(alpha: 0.18);

  // ─── Typography helper ───────────────────────────────────────────────────────
  // 'Quicksand' is the default font for all text
  // Default size is bigger (16) and bold for most text
  TextStyle _ts({
    double size = 16,
    FontWeight weight = FontWeight.bold,
    Color? color,
    double? letterSpacing,
  }) =>
      TextStyle(
        fontFamily: 'Quicksand',
        fontSize: size,
        fontWeight: weight,
        color: color ?? _text,
        letterSpacing: letterSpacing,
        decoration: TextDecoration.none,
      );

  // Smaller, non-bold text (for hints, buttons)
  TextStyle _tsSmall({
    double size = 14,
    FontWeight weight = FontWeight.normal,
    Color? color,
    double? letterSpacing,
  }) =>
      TextStyle(
        fontFamily: 'Quicksand',
        fontSize: size,
        fontWeight: weight,
        color: color ?? _text,
        letterSpacing: letterSpacing,
        decoration: TextDecoration.none,
      );

  // Heading text style using Bungee
  TextStyle _headerTs({
    double size = 22,
    FontWeight weight = FontWeight.bold,
    Color? color,
  }) =>
      TextStyle(
        fontFamily: 'Bungee',
        fontSize: size,
        fontWeight: weight,
        color: color ?? _text,
        decoration: TextDecoration.none,
      );

  // ─── Lifecycle ───────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        setState(() {
          _errorMessage    = null;
          _obscurePassword = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ─── Auth ────────────────────────────────────────────────────────────────────
  Future<void> _signIn() async {
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
    } on AuthException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (_) {
      setState(() => _errorMessage = 'Unexpected error. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signUp() async {
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      final res = await Supabase.instance.client.auth.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      if (res.user != null && res.session == null) {
        setState(() =>
            _errorMessage = 'Check your email to confirm your account.');
      }
    } on AuthException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (_) {
      setState(() => _errorMessage = 'Unexpected error. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ─── Widgets ─────────────────────────────────────────────────────────────────

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool isPassword = false,
  }) {
    const r = BorderRadius.all(Radius.circular(12));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: _ts(size: 15, weight: FontWeight.w600)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: isPassword && _obscurePassword,
          keyboardType: isPassword
              ? TextInputType.visiblePassword
              : TextInputType.emailAddress,
          style: _tsSmall(size: 15, weight: FontWeight.bold, color: _fieldText),
          cursorColor: _highlight,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: _tsSmall(size: 14, color: _fieldText.withValues(alpha: 0.4)),
            prefixIcon: Icon(icon,
                color: _fieldText.withValues(alpha: 0.5), size: 18),
            suffixIcon: isPassword
                ? IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color: _fieldText.withValues(alpha: 0.5),
                      size: 18,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  )
                : null,
            filled: true,
            fillColor: _fieldFill,
            // Identical radius on every state → shape never changes on focus
            border:          OutlineInputBorder(borderRadius: r, borderSide: BorderSide(color: _border)),
            enabledBorder:   OutlineInputBorder(borderRadius: r, borderSide: BorderSide(color: _border)),
            focusedBorder:   OutlineInputBorder(borderRadius: r, borderSide: BorderSide(color: _highlight, width: 2)),
            disabledBorder:  OutlineInputBorder(borderRadius: r, borderSide: BorderSide(color: _border)),
            errorBorder:     OutlineInputBorder(borderRadius: r, borderSide: BorderSide(color: Colors.redAccent.withValues(alpha: 0.6))),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
      ],
    );
  }

  Widget _buildButton({
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
  }) =>
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: _button,
            disabledBackgroundColor: _button.withValues(alpha: 0.55),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
          icon: _isLoading
              ? const SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2),
                )
              : Icon(icon, size: 18, color: Colors.white),
          label: Text(label,
              style: _tsSmall(size: 15, weight: FontWeight.w600, color: Colors.white)),
        ),
      );

  Widget _buildErrorBox() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(_errorMessage!,
                  style: _tsSmall(size: 13, color: Colors.redAccent)),
            ),
          ],
        ),
      );

  // ─── Tab bodies ──────────────────────────────────────────────────────────────

  Widget _buildSignInTab() => Padding(
        padding: const EdgeInsets.fromLTRB(28, 26, 28, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text('Welcome back!',
                textAlign: TextAlign.center,
                style: _headerTs(size: 28)),
            const SizedBox(height: 22),
            _buildTextField(
              controller: _emailController,
              label: 'Email address',
              hint: 'you@example.com',
              icon: Icons.email_outlined,
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _passwordController,
              label: 'Password',
              hint: 'Enter your password',
              icon: Icons.lock_outline,
              isPassword: true,
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              _buildErrorBox(),
            ],
            const SizedBox(height: 20),
            _buildButton(
              label: 'Sign In',
              icon: Icons.login_rounded,
              onPressed: _isLoading ? null : _signIn,
            ),
            const SizedBox(height: 22),
          ],
        ),
      );

  Widget _buildSignUpTab() => Padding(
        padding: const EdgeInsets.fromLTRB(28, 26, 28, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text('First time here?',
                textAlign: TextAlign.center,
                style: _headerTs(size: 28)),
            const SizedBox(height: 22),
            _buildTextField(
              controller: _emailController,
              label: 'Email address',
              hint: 'you@example.com',
              icon: Icons.email_outlined,
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _passwordController,
              label: 'Password',
              hint: 'Min. 8 characters',
              icon: Icons.lock_outline,
              isPassword: true,
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              _buildErrorBox(),
            ],
            const SizedBox(height: 20),
            _buildButton(
              label: 'Create Account',
              icon: Icons.person_add_outlined,
              onPressed: _isLoading ? null : _signUp,
            ),
            const SizedBox(height: 22),
          ],
        ),
      );

  // ─── Card ────────────────────────────────────────────────────────────────────

  Widget _buildCard() => Container(
        decoration: BoxDecoration(
          color: _component,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: _isDarkMode ? 0.55 : 0.08),
              blurRadius: 36,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Tab bar ── NOTE: tabs: is required by TabBar ──────────────
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(18)),
              child: TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(text: 'Sign In'),
                  Tab(text: 'Sign Up'),
                ],
                labelStyle:
                    TextStyle(fontFamily: 'Quicksand', fontWeight: FontWeight.bold, fontSize: 15),
                unselectedLabelStyle:
                    TextStyle(fontFamily: 'Quicksand', fontWeight: FontWeight.w500, fontSize: 15),
                labelColor: _text,
                unselectedLabelColor: _text.withValues(alpha: 0.4),
                indicatorColor: _button,
                indicatorWeight: 2.5,
                dividerColor: _border,
                overlayColor:
                    WidgetStateProperty.all(_button.withValues(alpha: 0.07)),
              ),
            ),

            // ── Tab content — IndexedStack keeps both trees alive ─────────
            AnimatedBuilder(
              animation: _tabController,
              builder: (_, __) => IndexedStack(
                index: _tabController.index,
                children: [
                  _buildSignInTab(),
                  _buildSignUpTab(),
                ],
              ),
            ),

            // ── Footer inside card ────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Text(
                'SISF v1.3 [Non-release]',
                style: _tsSmall(
                  size: 11,
                  color: _text.withValues(alpha: 0.35),
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ],
        ),
      );



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Stack(
          children: [
            // Scrollbar auto-hides on Desktop (Windows overlay bar) and Android
            Scrollbar(
              controller: _scrollController,
              thumbVisibility: false,
              child: SingleChildScrollView(
                controller: _scrollController,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 64),
                child: Center(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // Wider card on screens >= 600 px
                      final maxW =
                          constraints.maxWidth >= 600 ? 520.0 : 420.0;
                      return ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: maxW),
                        child: Column(
                          children: [
                            // Logo
                            Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                color: _button,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Icon(
                                Icons.energy_savings_leaf_rounded,
                                size: 34,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'SISF Dashboard',
                              style:
                                  _headerTs(size: 26),
                            ),
                            const SizedBox(height: 28),
                            _buildCard(),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


