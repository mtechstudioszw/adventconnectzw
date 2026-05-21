import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../services/auth_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

/// Unified login + signup surface, Claude-app style. The user enters
/// an email; we ask Supabase whether an account exists for it; based
/// on that we reveal either the login password field or the full
/// signup form. One screen, one decision point.
///
/// `birthDate` is forwarded from the age-verification step. It's
/// required to *create* a new account but ignored for logins.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, this.birthDate});

  final DateTime? birthDate;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

enum _Stage { email, login, signup }

class _AuthScreenState extends State<AuthScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _nameController = TextEditingController();

  late final FocusNode _emailFocus;
  late final FocusNode _passwordFocus;
  late final FocusNode _nameFocus;

  late final AnimationController _entrance;
  late final Animation<double> _fade;
  late final Animation<double> _slide;

  _Stage _stage = _Stage.email;
  bool _checking = false;
  bool _submitting = false;
  bool _googleBusy = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _acceptedTerms = false;
  // True when emailExists() couldn't tell us. In that case we land on
  // the login stage with an extra "or create account" toggle so the
  // user picks.
  bool _detectionAmbiguous = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _emailFocus = FocusNode();
    _passwordFocus = FocusNode();
    _nameFocus = FocusNode();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    )..forward();
    _fade = CurvedAnimation(parent: _entrance, curve: Curves.easeOut);
    _slide = Tween<double>(begin: 16, end: 0).animate(
      CurvedAnimation(parent: _entrance, curve: Curves.easeOutCubic),
    );
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _emailFocus.requestFocus(),
    );
  }

  @override
  void dispose() {
    _entrance.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _nameController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  String? _validateEmail(String? v) {
    if (v == null || v.trim().isEmpty) return 'Email is required';
    final regex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!regex.hasMatch(v.trim())) return 'Enter a valid email';
    return null;
  }

  String? _validatePassword(String? v) {
    if (v == null || v.isEmpty) return 'Password is required';
    if (_stage == _Stage.signup && v.length < 8) {
      return 'At least 8 characters';
    }
    return null;
  }

  String? _validateConfirm(String? v) {
    if (_stage != _Stage.signup) return null;
    if (v == null || v.isEmpty) return 'Confirm your password';
    if (v != _passwordController.text) return 'Passwords don\'t match';
    return null;
  }

  String? _validateName(String? v) {
    if (_stage != _Stage.signup) return null;
    if (v == null || v.trim().isEmpty) return 'Full name is required';
    if (v.trim().length < 2) return 'Enter your full name';
    return null;
  }

  Future<void> _onContinue() async {
    setState(() => _error = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final email = _emailController.text.trim();
    setState(() => _checking = true);
    final exists = await AuthService.emailExists(email);
    if (!mounted) return;
    // Detection rules:
    //   true  -> account confirmed -> login stage
    //   false -> no account        -> signup stage
    //   null  -> RPC missing       -> default to SIGNUP so we don't
    //                                 dead-end a new user on a password
    //                                 prompt for an account they don't
    //                                 have. If they actually had an
    //                                 account, Supabase will reject the
    //                                 signup with "already registered"
    //                                 and _onSignup auto-swaps to login.
    final next = switch (exists) {
      true => _Stage.login,
      false => _Stage.signup,
      null => _Stage.signup,
    };
    setState(() {
      _checking = false;
      _detectionAmbiguous = exists == null;
      _stage = next;
    });
    HapticFeedback.selectionClick();
    Future.delayed(const Duration(milliseconds: 280), () {
      if (!mounted) return;
      if (_stage == _Stage.signup) {
        _nameFocus.requestFocus();
      } else {
        _passwordFocus.requestFocus();
      }
    });
  }

  Future<void> _onLogin() async {
    setState(() => _error = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _submitting = true);
    final result = await AuthService.signIn(
      email: _emailController.text.trim(),
      password: _passwordController.text,
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (result.isSuccess) {
      HapticFeedback.mediumImpact();
      context.goNamed('home');
      return;
    }
    final message = (result.errorMessage ?? '').toLowerCase();
    if (message.contains('email') && message.contains('confirm')) {
      // Existing account but never verified — push them back to the OTP
      // surface so they can finish.
      context.goNamed(
        'email_verification',
        extra: _emailController.text.trim(),
      );
      return;
    }
    setState(() => _error = result.errorMessage);
  }

  Future<void> _onSignup() async {
    setState(() => _error = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (!_acceptedTerms) {
      setState(() => _error =
          'Please accept the Terms & Conditions to create your account.');
      return;
    }
    final birthDate = widget.birthDate;
    if (birthDate == null) {
      // Should be impossible — splash routes through age_verification
      // first — but guard anyway so we never silently bypass the gate.
      setState(() => _error =
          'We need your date of birth before creating an account. '
          'Please go back and complete the age check.');
      return;
    }
    setState(() => _submitting = true);
    final result = await AuthService.signUp(
      email: _emailController.text.trim(),
      password: _passwordController.text,
      fullName: _nameController.text.trim(),
      birthDate: birthDate,
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (result.isSuccess) {
      HapticFeedback.mediumImpact();
      context.goNamed(
        'email_verification',
        extra: _emailController.text.trim(),
      );
      return;
    }
    // If Supabase tells us the email is already registered, flip the
    // screen to the login stage so the user can just sign in instead
    // of seeing a generic error.
    final message = (result.errorMessage ?? '').toLowerCase();
    if (message.contains('already exists') ||
        message.contains('already registered') ||
        message.contains('try logging in')) {
      setState(() {
        _stage = _Stage.login;
        _passwordController.clear();
        _confirmController.clear();
        _error =
            'Looks like you already have an account — enter your password '
            'to log in.';
      });
      Future.delayed(const Duration(milliseconds: 280), () {
        if (mounted) _passwordFocus.requestFocus();
      });
      return;
    }
    setState(() => _error = result.errorMessage);
  }

  Future<void> _onGoogle() async {
    setState(() {
      _error = null;
      _googleBusy = true;
    });
    final result = await AuthService.signInWithGoogle();
    if (!mounted) return;
    setState(() => _googleBusy = false);
    if (result.isSuccess) {
      // Google has already verified the email — Supabase marks
      // email_confirmed_at automatically, so we can skip the email
      // verification screen and head straight into onboarding (or
      // home if the user has been here before).
      HapticFeedback.mediumImpact();
      final hasFullName = (AuthService.currentUser?.userMetadata?[
              'full_name'] as String?)
              ?.trim()
              .isNotEmpty ==
          true;
      context.goNamed(hasFullName ? 'home' : 'profile_setup');
      return;
    }
    if (result.errorMessage == 'Sign in cancelled.') return;
    setState(() => _error = result.errorMessage);
  }

  void _changeEmail() {
    HapticFeedback.selectionClick();
    setState(() {
      _stage = _Stage.email;
      _detectionAmbiguous = false;
      _passwordController.clear();
      _confirmController.clear();
      _nameController.clear();
      _acceptedTerms = false;
      _error = null;
    });
    Future.delayed(const Duration(milliseconds: 280), () {
      if (mounted) _emailFocus.requestFocus();
    });
  }

  void _switchToSignup() {
    HapticFeedback.selectionClick();
    setState(() => _stage = _Stage.signup);
    Future.delayed(const Duration(milliseconds: 280), () {
      if (mounted) _nameFocus.requestFocus();
    });
  }

  void _switchToLogin() {
    HapticFeedback.selectionClick();
    setState(() => _stage = _Stage.login);
    Future.delayed(const Duration(milliseconds: 280), () {
      if (mounted) _passwordFocus.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightGrey,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: AnimatedBuilder(
            animation: _entrance,
            builder: (context, child) => Opacity(
              opacity: _fade.value,
              child: Transform.translate(
                offset: Offset(0, _slide.value),
                child: child,
              ),
            ),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 24),
                  const _LogoMark(),
                  const SizedBox(height: 28),
                  Text(
                    _headlineForStage(),
                    textAlign: TextAlign.center,
                    style: AppTextStyles.displayMedium.copyWith(
                      color: AppColors.darkNavy,
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _subheadlineForStage(),
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: const Color.fromRGBO(26, 26, 46, 0.65),
                      fontSize: 14,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 28),
                  if (_stage == _Stage.email) ...[
                    _GoogleButton(
                      busy: _googleBusy,
                      onTap: (_googleBusy || _submitting) ? null : _onGoogle,
                    ),
                    const SizedBox(height: 20),
                    const _OrDivider(),
                    const SizedBox(height: 20),
                  ],
                  AnimatedSize(
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 260),
                      switchInCurve: Curves.easeOut,
                      switchOutCurve: Curves.easeIn,
                      transitionBuilder: (child, anim) => FadeTransition(
                        opacity: anim,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.04),
                            end: Offset.zero,
                          ).animate(anim),
                          child: child,
                        ),
                      ),
                      child: _buildStageForm(),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 18),
                    _ErrorBanner(message: _error!),
                  ],
                  const SizedBox(height: 24),
                  _PrimaryButton(
                    label: _primaryLabelForStage(),
                    busy: _submitting || _checking,
                    onTap: _submitting || _checking ? null : _onPrimary,
                  ),
                  const SizedBox(height: 18),
                  if (_stage != _Stage.email)
                    Center(
                      child: TextButton(
                        onPressed: _changeEmail,
                        child: Text(
                          'Use a different email',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: const Color.fromRGBO(26, 26, 46, 0.7),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  if (_stage == _Stage.login && _detectionAmbiguous)
                    Center(
                      child: TextButton(
                        onPressed: _switchToSignup,
                        child: Text(
                          'No account yet? Create one',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.primaryBlue,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  if (_stage == _Stage.signup)
                    Center(
                      child: TextButton(
                        onPressed: _switchToLogin,
                        child: Text(
                          'Already have an account? Log in',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.primaryBlue,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 18),
                  _LegalLine(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _headlineForStage() {
    switch (_stage) {
      case _Stage.email:
        return 'Build community.\nFind your home.';
      case _Stage.login:
        return 'Welcome back';
      case _Stage.signup:
        return 'Create your account';
    }
  }

  String _subheadlineForStage() {
    switch (_stage) {
      case _Stage.email:
        return 'Sign in or create an account — we\'ll figure out which '
            'from your email.';
      case _Stage.login:
        return 'Enter your password to keep going.';
      case _Stage.signup:
        return 'Just a few details and you\'re in.';
    }
  }

  String _primaryLabelForStage() {
    if (_checking) return 'Checking…';
    switch (_stage) {
      case _Stage.email:
        return 'Continue';
      case _Stage.login:
        return _submitting ? 'Signing in…' : 'Log in';
      case _Stage.signup:
        return _submitting ? 'Creating…' : 'Create account';
    }
  }

  void _onPrimary() {
    switch (_stage) {
      case _Stage.email:
        _onContinue();
        break;
      case _Stage.login:
        _onLogin();
        break;
      case _Stage.signup:
        _onSignup();
        break;
    }
  }

  Widget _buildStageForm() {
    switch (_stage) {
      case _Stage.email:
        return _buildEmailStage();
      case _Stage.login:
        return _buildLoginStage();
      case _Stage.signup:
        return _buildSignupStage();
    }
  }

  Widget _buildEmailStage() {
    return Column(
      key: const ValueKey('stage-email'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _GlowField(
          controller: _emailController,
          focusNode: _emailFocus,
          hint: 'Email address',
          icon: Icons.alternate_email,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.go,
          autofillHints: const [AutofillHints.email],
          validator: _validateEmail,
          onSubmitted: (_) => _onContinue(),
        ),
      ],
    );
  }

  Widget _buildLoginStage() {
    return Column(
      key: const ValueKey('stage-login'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _EmailRow(
          email: _emailController.text.trim(),
          onEdit: _changeEmail,
        ),
        const SizedBox(height: 14),
        _GlowField(
          controller: _passwordController,
          focusNode: _passwordFocus,
          hint: 'Password',
          icon: Icons.lock_outline,
          obscure: _obscurePassword,
          textInputAction: TextInputAction.go,
          autofillHints: const [AutofillHints.password],
          validator: _validatePassword,
          onSubmitted: (_) => _onLogin(),
          suffix: IconButton(
            icon: Icon(
              _obscurePassword
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              color: const Color.fromRGBO(26, 26, 46, 0.5),
              size: 20,
            ),
            onPressed: () => setState(
              () => _obscurePassword = !_obscurePassword,
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => context.pushNamed('forgot_password'),
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 32),
              padding: const EdgeInsets.symmetric(horizontal: 6),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              'Forgot password?',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.primaryBlue,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSignupStage() {
    return Column(
      key: const ValueKey('stage-signup'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _EmailRow(
          email: _emailController.text.trim(),
          onEdit: _changeEmail,
        ),
        const SizedBox(height: 14),
        _GlowField(
          controller: _nameController,
          focusNode: _nameFocus,
          hint: 'Full name',
          icon: Icons.person_outline,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.name],
          validator: _validateName,
        ),
        const SizedBox(height: 14),
        _GlowField(
          controller: _passwordController,
          focusNode: _passwordFocus,
          hint: 'Password (8+ characters)',
          icon: Icons.lock_outline,
          obscure: _obscurePassword,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.newPassword],
          validator: _validatePassword,
          suffix: IconButton(
            icon: Icon(
              _obscurePassword
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              color: const Color.fromRGBO(26, 26, 46, 0.5),
              size: 20,
            ),
            onPressed: () => setState(
              () => _obscurePassword = !_obscurePassword,
            ),
          ),
        ),
        const SizedBox(height: 14),
        _GlowField(
          controller: _confirmController,
          hint: 'Confirm password',
          icon: Icons.lock_outline,
          obscure: _obscureConfirm,
          textInputAction: TextInputAction.go,
          validator: _validateConfirm,
          onSubmitted: (_) => _onSignup(),
          suffix: IconButton(
            icon: Icon(
              _obscureConfirm
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              color: const Color.fromRGBO(26, 26, 46, 0.5),
              size: 20,
            ),
            onPressed: () => setState(
              () => _obscureConfirm = !_obscureConfirm,
            ),
          ),
        ),
        const SizedBox(height: 14),
        _TermsCheckbox(
          value: _acceptedTerms,
          onChanged: (v) => setState(() => _acceptedTerms = v ?? false),
        ),
      ],
    );
  }
}

// =============================================================================
// Sub-widgets
// =============================================================================

class _LogoMark extends StatelessWidget {
  const _LogoMark();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryBlue.withValues(alpha: 0.30),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: const Icon(
          Icons.church,
          color: AppColors.goldAccent,
          size: 34,
        ),
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    final line = Expanded(
      child: Container(
        height: 1,
        color: const Color.fromRGBO(26, 26, 46, 0.10),
      ),
    );
    return Row(
      children: [
        line,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            'OR',
            style: AppTextStyles.labelSmall.copyWith(
              color: const Color.fromRGBO(26, 26, 46, 0.45),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
        ),
        line,
      ],
    );
  }
}

class _GoogleButton extends StatelessWidget {
  const _GoogleButton({required this.busy, required this.onTap});

  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null && !busy ? 0.6 : 1,
      child: Material(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(22),
        elevation: 0,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: const Color.fromRGBO(26, 26, 46, 0.12),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: busy
                ? const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: AppColors.primaryBlue,
                      ),
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const _GoogleGlyph(),
                      const SizedBox(width: 12),
                      Text(
                        'Continue with Google',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.darkNavy,
                          fontWeight: FontWeight.w700,
                          fontSize: 14.5,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _GoogleGlyph extends StatelessWidget {
  const _GoogleGlyph();

  @override
  Widget build(BuildContext context) {
    // Lightweight stand-in for the multi-colour G — keeps the bundle
    // free of an extra image asset. The icon is colour-balanced
    // against the app's blue palette.
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: AppColors.white,
        shape: BoxShape.circle,
        border: Border.all(color: const Color.fromRGBO(26, 26, 46, 0.10)),
      ),
      alignment: Alignment.center,
      child: Text(
        'G',
        style: AppTextStyles.labelLarge.copyWith(
          color: AppColors.primaryBlue,
          fontWeight: FontWeight.w800,
          fontSize: 14,
        ),
      ),
    );
  }
}

class _GlowField extends StatefulWidget {
  const _GlowField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.focusNode,
    this.obscure = false,
    this.suffix,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.validator,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final String hint;
  final IconData icon;
  final bool obscure;
  final Widget? suffix;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onSubmitted;

  @override
  State<_GlowField> createState() => _GlowFieldState();
}

class _GlowFieldState extends State<_GlowField> {
  late FocusNode _focus;
  bool _ownsFocus = false;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focus = widget.focusNode ?? FocusNode();
    _ownsFocus = widget.focusNode == null;
    _focus.addListener(_handleFocus);
  }

  void _handleFocus() {
    if (mounted) setState(() => _focused = _focus.hasFocus);
  }

  @override
  void dispose() {
    _focus.removeListener(_handleFocus);
    if (_ownsFocus) _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        boxShadow: _focused
            ? [
                BoxShadow(
                  color: AppColors.primaryBlue.withValues(alpha: 0.18),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ]
            : [],
      ),
      child: TextFormField(
        controller: widget.controller,
        focusNode: _focus,
        obscureText: widget.obscure,
        keyboardType: widget.keyboardType,
        textInputAction: widget.textInputAction,
        autofillHints: widget.autofillHints,
        validator: widget.validator,
        onFieldSubmitted: widget.onSubmitted,
        style: AppTextStyles.bodyLarge.copyWith(fontSize: 15),
        decoration: InputDecoration(
          hintText: widget.hint,
          hintStyle: AppTextStyles.bodyMedium.copyWith(
            color: const Color.fromRGBO(26, 26, 46, 0.5),
          ),
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 18, right: 12),
            child: Icon(
              widget.icon,
              color: _focused
                  ? AppColors.primaryBlue
                  : const Color.fromRGBO(26, 26, 46, 0.5),
              size: 20,
            ),
          ),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 48, minHeight: 48),
          suffixIcon: widget.suffix,
          filled: true,
          fillColor: AppColors.white,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: const BorderSide(
              color: Color.fromRGBO(26, 26, 46, 0.10),
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: const BorderSide(
              color: Color.fromRGBO(26, 26, 46, 0.10),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: const BorderSide(
              color: AppColors.primaryBlue,
              width: 1.6,
            ),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: const BorderSide(color: AppColors.red),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: const BorderSide(color: AppColors.red, width: 1.6),
          ),
        ),
      ),
    );
  }
}

class _EmailRow extends StatelessWidget {
  const _EmailRow({required this.email, required this.onEdit});
  final String email;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: const Color.fromRGBO(26, 26, 46, 0.03),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: const Color.fromRGBO(26, 26, 46, 0.10),
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.alternate_email,
                color: Color.fromRGBO(26, 26, 46, 0.55),
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.darkNavy,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                'Change',
                style: AppTextStyles.labelMedium.copyWith(
                  color: AppColors.primaryBlue,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TermsCheckbox extends StatefulWidget {
  const _TermsCheckbox({required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool?> onChanged;

  @override
  State<_TermsCheckbox> createState() => _TermsCheckboxState();
}

class _TermsCheckboxState extends State<_TermsCheckbox> {
  late final TapGestureRecognizer _termsTap;
  late final TapGestureRecognizer _privacyTap;

  @override
  void initState() {
    super.initState();
    _termsTap = TapGestureRecognizer()
      ..onTap = () => context.pushNamed('terms');
    _privacyTap = TapGestureRecognizer()
      ..onTap = () => context.pushNamed('privacy');
  }

  @override
  void dispose() {
    _termsTap.dispose();
    _privacyTap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final linkStyle = AppTextStyles.bodySmall.copyWith(
      color: AppColors.primaryBlue,
      fontWeight: FontWeight.w700,
      fontSize: 13,
      decoration: TextDecoration.underline,
      decorationColor: AppColors.primaryBlue.withValues(alpha: 0.4),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => widget.onChanged(!widget.value),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color:
                    widget.value ? AppColors.primaryBlue : AppColors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: widget.value
                      ? AppColors.primaryBlue
                      : const Color.fromRGBO(26, 26, 46, 0.25),
                  width: 1.5,
                ),
              ),
              alignment: Alignment.center,
              child: widget.value
                  ? const Icon(
                      Icons.check,
                      size: 14,
                      color: AppColors.white,
                    )
                  : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Text.rich(
                TextSpan(
                  style: AppTextStyles.bodySmall.copyWith(
                    color: const Color.fromRGBO(26, 26, 46, 0.7),
                    fontSize: 13,
                    height: 1.45,
                  ),
                  children: [
                    TextSpan(
                      text: 'I agree to the ',
                      recognizer: TapGestureRecognizer()
                        ..onTap = () => widget.onChanged(!widget.value),
                    ),
                    TextSpan(
                      text: 'Terms & Conditions',
                      style: linkStyle,
                      recognizer: _termsTap,
                    ),
                    const TextSpan(text: ' and '),
                    TextSpan(
                      text: 'Privacy Policy',
                      style: linkStyle,
                      recognizer: _privacyTap,
                    ),
                    const TextSpan(text: '.'),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.busy,
    required this.onTap,
  });

  final String label;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null && !busy ? 0.6 : 1,
      child: Container(
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryBlue.withValues(alpha: 0.32),
              blurRadius: 22,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(22),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 18),
              alignment: Alignment.center,
              child: busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        color: AppColors.white,
                        strokeWidth: 2.4,
                      ),
                    )
                  : Text(
                      label,
                      style: AppTextStyles.buttonText.copyWith(
                        fontSize: 15.5,
                        letterSpacing: 0.4,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.red.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.error_outline, color: AppColors.red, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.red,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegalLine extends StatefulWidget {
  @override
  State<_LegalLine> createState() => _LegalLineState();
}

class _LegalLineState extends State<_LegalLine> {
  late final TapGestureRecognizer _termsTap;
  late final TapGestureRecognizer _privacyTap;

  @override
  void initState() {
    super.initState();
    _termsTap = TapGestureRecognizer()
      ..onTap = () => context.pushNamed('terms');
    _privacyTap = TapGestureRecognizer()
      ..onTap = () => context.pushNamed('privacy');
  }

  @override
  void dispose() {
    _termsTap.dispose();
    _privacyTap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = AppTextStyles.labelSmall.copyWith(
      color: const Color.fromRGBO(26, 26, 46, 0.5),
      fontSize: 11,
      height: 1.45,
    );
    final link = base.copyWith(
      color: AppColors.primaryBlue,
      fontWeight: FontWeight.w700,
      decoration: TextDecoration.underline,
      decorationColor: AppColors.primaryBlue.withValues(alpha: 0.4),
    );
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text.rich(
          TextSpan(
            style: base,
            children: [
              const TextSpan(text: 'By continuing you agree to the '),
              TextSpan(
                text: 'Terms & Conditions',
                style: link,
                recognizer: _termsTap,
              ),
              const TextSpan(text: ' and '),
              TextSpan(
                text: 'Privacy Policy',
                style: link,
                recognizer: _privacyTap,
              ),
              const TextSpan(text: '.'),
            ],
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
